-- =============================================================================
-- Phase 1: Assessment & Environment Prep
-- Source Database Inventory — PostgreSQL "healthcare_dba"
-- =============================================================================
-- I ran these queries against the PostgreSQL source database to build a full
-- inventory of everything that needs to convert to SQL Server: tables, columns,
-- constraints, indexes, triggers, functions, sequences, and extensions.
-- Run these in order in psql or pgAdmin, connected to the healthcare_dba database.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Table list with estimated row counts and on-disk size
-- -----------------------------------------------------------------------------
-- Gives me a first pass at scale before going deeper: which tables are large,
-- which are small, and roughly how much data I'm actually migrating.
-- -----------------------------------------------------------------------------
SELECT
    relname AS table_name,
    n_live_tup AS estimated_rows,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- Result:
-- staging_raw          9,661,005 rows   3305 MB
-- provider_services    9,664,660 rows   1936 MB
-- providers            1,175,260 rows    322 MB
-- data_access_log               2 rows     80 kB
-- user_state_access              2 rows     24 kB


-- -----------------------------------------------------------------------------
-- 2. Confirm which schema each table actually lives in
-- -----------------------------------------------------------------------------
-- My first column-inventory attempt against the "public" schema returned
-- nothing — these tables turned out to live in two dedicated schemas,
-- not public. This query is how I found that out.
-- -----------------------------------------------------------------------------
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name IN ('staging_raw', 'provider_services', 'providers', 'data_access_log', 'user_state_access');

-- Result:
-- cms   .providers
-- cms   .provider_services
-- cms   .user_state_access
-- cms   .staging_raw
-- audit .data_access_log


-- -----------------------------------------------------------------------------
-- 3. Full column inventory: names, data types, lengths, nullability, defaults
-- -----------------------------------------------------------------------------
-- This is the core of the schema conversion mapping work — every column and
-- its PostgreSQL type, which I'll map to the closest SQL Server equivalent
-- (e.g. character varying -> NVARCHAR, jsonb -> JSON, inet -> VARCHAR/VARBINARY).
-- -----------------------------------------------------------------------------
SELECT
    table_schema,
    table_name,
    column_name,
    data_type,
    character_maximum_length,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema IN ('cms', 'audit')
ORDER BY table_schema, table_name, ordinal_position;

-- Notable findings:
--  - audit.data_access_log.client_addr is type "inet" — no direct SQL Server
--    equivalent; I'll map this to VARCHAR(45) or VARBINARY(16).
--  - audit.data_access_log.old_data / new_data are "jsonb" — SQL Server 2025
--    has a native JSON type, so this maps cleanly for once.
--  - cms.staging_raw stores nearly every column as character varying, even
--    numeric-looking fields (tot_benes, avg_sbmtd_chrg, etc.) — this looks like
--    a raw landing table ahead of cleanup into providers/provider_services,
--    and I still need to decide whether it's worth migrating at all.


-- -----------------------------------------------------------------------------
-- 4. Primary keys, foreign keys, and other table constraints
-- -----------------------------------------------------------------------------
-- I need this to preserve every relationship and rule when I recreate the
-- schema in T-SQL.
-- -----------------------------------------------------------------------------
SELECT
    tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema IN ('cms', 'audit')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_type;

-- Result:
--  - audit.data_access_log: PK on log_id
--  - cms.provider_services: PK on id, FK on rndrng_npi -> cms.providers
--  - cms.providers: PK on rndrng_npi
--  - cms.user_state_access: composite PK on (username, state_abbr)
--  - cms.staging_raw: no constraints at all (confirms it's a raw staging table)


-- -----------------------------------------------------------------------------
-- 5. Indexes
-- -----------------------------------------------------------------------------
-- All standard B-tree indexes here — no exotic PostgreSQL index types
-- (GIN/GiST/BRIN) to worry about, so these translate directly to T-SQL.
-- -----------------------------------------------------------------------------
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname IN ('cms', 'audit')
ORDER BY schemaname, tablename, indexname;

-- Result: 8 secondary indexes plus the 4 PK indexes, mostly single-column
-- lookups (hcpcs_cd, rndrng_npi, state_abbr, provider_type) plus one
-- composite index on providers (state_abbr, provider_type).


-- -----------------------------------------------------------------------------
-- 6. Views, functions/routines, and triggers
-- -----------------------------------------------------------------------------
-- Checking for any business logic living inside the database itself, since
-- that all needs to be rewritten in T-SQL, not just the tables.
-- -----------------------------------------------------------------------------
SELECT table_schema, table_name, view_definition
FROM information_schema.views
WHERE table_schema IN ('cms', 'audit');
-- Result: no views defined.

SELECT routine_schema, routine_name, routine_type, data_type AS return_type
FROM information_schema.routines
WHERE routine_schema IN ('cms', 'audit');
-- Result: none returned directly under cms/audit routine listing
-- (the actual trigger function turned out to live in the audit schema —
-- see query 7 below for how I found it).

SELECT event_object_schema, event_object_table, trigger_name, action_timing, event_manipulation
FROM information_schema.triggers
WHERE event_object_schema IN ('cms', 'audit');

-- Result:
--  - cms.provider_services: trg_audit_provider_services (AFTER INSERT/UPDATE/DELETE)
--  - cms.providers: trg_audit_providers (AFTER INSERT/UPDATE/DELETE)


-- -----------------------------------------------------------------------------
-- 7. Trigger function source code
-- -----------------------------------------------------------------------------
-- Both triggers call the same function, so I pulled its actual PL/pgSQL source
-- to plan the T-SQL rewrite for the Schema Conversion phase.
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS function_schema,
    p.proname AS function_name,
    pg_get_functiondef(p.oid) AS function_source
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE t.tgname IN ('trg_audit_provider_services', 'trg_audit_providers');

-- Result: audit.log_data_changes() — a single generic audit-logging function
-- used by both triggers. It serializes the entire OLD/NEW row to JSONB using
-- to_jsonb() and dynamic trigger metadata (TG_TABLE_NAME, TG_OP, TG_TABLE_SCHEMA).
-- This is the most interesting conversion challenge in the whole schema:
-- T-SQL has no to_jsonb(), but SQL Server 2025's native JSON type combined
-- with FOR JSON PATH against the inserted/deleted pseudo-tables can replicate
-- this same generic, table-agnostic pattern.


-- -----------------------------------------------------------------------------
-- 8. Sequences
-- -----------------------------------------------------------------------------
-- Confirms which columns are backed by auto-incrementing sequences, so I can
-- recreate them as IDENTITY columns in SQL Server.
-- -----------------------------------------------------------------------------
SELECT sequence_schema, sequence_name, data_type, start_value, increment
FROM information_schema.sequences
WHERE sequence_schema IN ('cms', 'audit');

-- Result:
--  - cms.provider_services_id_seq   (bigint, start 1, increment 1)
--  - audit.data_access_log_log_id_seq (bigint, start 1, increment 1)
-- Both are standard identity-style sequences -> IDENTITY(1,1) in SQL Server.


-- -----------------------------------------------------------------------------
-- 9. Extensions in use
-- -----------------------------------------------------------------------------
-- Checking for anything that would need a SQL Server equivalent (e.g. PostGIS,
-- uuid-ossp, pgcrypto).
-- -----------------------------------------------------------------------------
SELECT extname, extversion
FROM pg_extension;

-- Result:
--  - plpgsql (1.0)             — PostgreSQL's built-in procedural language,
--                                 not something to migrate; just how the
--                                 trigger function above is written.
--  - pg_stat_statements (1.12) — monitoring/performance extension only,
--                                 no application data lives here.
-- No custom extensions in use — one less thing to worry about in conversion.


-- =============================================================================
-- Summary of findings
-- =============================================================================
-- Schemas:                2 (cms, audit)
-- Tables:                 5
-- Rows (approx.):         ~20.5 million total
-- Size:                   ~5.5 GB
-- Primary keys:           4 (1 composite: user_state_access)
-- Foreign keys:           1 (provider_services.rndrng_npi -> providers.rndrng_npi)
-- Indexes (secondary):    8, all standard B-tree
-- Triggers:               2 (both call the same audit function)
-- Functions:              1 (generic JSONB audit logger)
-- Views:                  0
-- Sequences:              2, standard bigint identity-style
-- Extensions:             2 (plpgsql, pg_stat_statements) — neither migrates
-- PostgreSQL-specific
--   types flagged:        jsonb (2 columns), inet (1 column)
-- =============================================================================
