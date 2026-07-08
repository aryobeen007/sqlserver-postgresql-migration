-- =============================================================================
-- Phase 2: Schema Conversion
-- Converting the PostgreSQL "healthcare_dba" schema to T-SQL for SQL Server 2025
-- =============================================================================
-- I'm recreating both PostgreSQL schemas (cms, audit) as SQL Server schemas,
-- then converting each table's columns, keys, and indexes based on the
-- inventory I built in Phase 1 (see sql/phase-1-assessment/01_source_inventory.sql).
--
-- I'm NOT including the audit trigger/function conversion in this file — that's
-- a bigger, separate piece (rewriting a PL/pgSQL JSONB audit logger as a T-SQL
-- trigger using the native JSON type), so it gets its own script.
--
-- Run this against the SQLDBA-Primary default instance, in the target database
-- (create the database first if it doesn't exist yet).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Create the database (skip if it already exists)
-- -----------------------------------------------------------------------------
-- IF DB_ID('healthcare_dba') IS NULL
-- BEGIN
--     CREATE DATABASE healthcare_dba;
-- END
-- GO
-- USE healthcare_dba;
-- GO


-- -----------------------------------------------------------------------------
-- 1. Create schemas
-- -----------------------------------------------------------------------------
-- PostgreSQL had two schemas: cms (core data) and audit (logging). SQL Server
-- supports schemas the same way, so this is a direct 1:1 mapping.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'cms')
    EXEC('CREATE SCHEMA cms');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC('CREATE SCHEMA audit');
GO


-- -----------------------------------------------------------------------------
-- 2. cms.providers
-- -----------------------------------------------------------------------------
-- Type mapping notes:
--  - character varying(n)  -> NVARCHAR(n)   (Unicode-safe; source data includes
--                                             provider names/addresses)
--  - text                  -> NVARCHAR(MAX) (ruca_desc has no fixed length in PG)
--  - numeric (no precision)-> DECIMAL(10,4) (ruca is a small coded value; I picked
--                                             a safe fixed precision since PG's
--                                             unconstrained numeric has none)
--  - state_abbr, medicare_participating, hcpcs_drug_ind, place_of_service are
--    fixed-width codes in the source, but I kept them as NVARCHAR to match the
--    exact PostgreSQL definition rather than tightening to CHAR — safer for a
--    first-pass migration, can optimize later in Performance Tuning if needed.
-- -----------------------------------------------------------------------------
CREATE TABLE cms.providers (
    rndrng_npi              NVARCHAR(10)   NOT NULL,
    last_org_name           NVARCHAR(100)  NOT NULL,
    first_name              NVARCHAR(50)   NULL,
    middle_initial          NVARCHAR(5)    NULL,
    credentials             NVARCHAR(50)   NULL,
    entity_code             NVARCHAR(5)    NULL,
    street1                 NVARCHAR(100)  NULL,
    street2                 NVARCHAR(100)  NULL,
    city                    NVARCHAR(50)   NULL,
    state_abbr              NVARCHAR(2)    NULL,
    state_fips              NVARCHAR(3)    NULL,
    zip5                    NVARCHAR(5)    NULL,
    ruca                    DECIMAL(10,4)  NULL,
    ruca_desc                NVARCHAR(MAX)  NULL,
    country                  NVARCHAR(5)    NULL,
    provider_type            NVARCHAR(100)  NULL,
    medicare_participating   NVARCHAR(1)    NULL,
    CONSTRAINT pk_providers PRIMARY KEY (rndrng_npi)
);
GO

CREATE INDEX idx_providers_state ON cms.providers (state_abbr);
CREATE INDEX idx_providers_state_type ON cms.providers (state_abbr, provider_type);
CREATE INDEX idx_providers_type ON cms.providers (provider_type);
GO


-- -----------------------------------------------------------------------------
-- 3. cms.provider_services
-- -----------------------------------------------------------------------------
-- Type mapping notes:
--  - id BIGSERIAL (PG sequence-backed PK) -> BIGINT IDENTITY(1,1)
--  - numeric (no precision) -> DECIMAL(18,2) for the dollar-amount and count
--    columns; PostgreSQL's numeric here holds currency-style values, so 2
--    decimal places is the safe, sensible choice.
--  - Foreign key to cms.providers preserved exactly as in the source.
-- -----------------------------------------------------------------------------
CREATE TABLE cms.provider_services (
    id                      BIGINT IDENTITY(1,1) NOT NULL,
    rndrng_npi              NVARCHAR(10)   NOT NULL,
    hcpcs_cd                NVARCHAR(10)   NOT NULL,
    hcpcs_desc              NVARCHAR(MAX)  NULL,
    hcpcs_drug_ind          NVARCHAR(1)    NULL,
    place_of_service        NVARCHAR(1)    NULL,
    tot_benes               INT            NULL,
    tot_srvcs               DECIMAL(18,2)  NULL,
    tot_bene_day_srvcs      DECIMAL(18,2)  NULL,
    avg_sbmtd_chrg          DECIMAL(18,2)  NULL,
    avg_mdcr_alowd_amt      DECIMAL(18,2)  NULL,
    avg_mdcr_pymt_amt       DECIMAL(18,2)  NULL,
    avg_mdcr_stdzd_amt      DECIMAL(18,2)  NULL,
    CONSTRAINT pk_provider_services PRIMARY KEY (id),
    CONSTRAINT fk_provider_services_npi FOREIGN KEY (rndrng_npi)
        REFERENCES cms.providers (rndrng_npi)
);
GO

CREATE INDEX idx_provider_services_hcpcs ON cms.provider_services (hcpcs_cd);
CREATE INDEX idx_provider_services_npi ON cms.provider_services (rndrng_npi);
GO


-- -----------------------------------------------------------------------------
-- 4. cms.user_state_access
-- -----------------------------------------------------------------------------
-- PostgreSQL had a composite primary key on (username, state_abbr) — both
-- columns together, not a surrogate key. T-SQL supports this directly by
-- listing both columns in the PRIMARY KEY constraint.
-- -----------------------------------------------------------------------------
CREATE TABLE cms.user_state_access (
    username        NVARCHAR(50)  NOT NULL,
    state_abbr      NVARCHAR(2)   NOT NULL,
    CONSTRAINT pk_user_state_access PRIMARY KEY (username, state_abbr)
);
GO


-- -----------------------------------------------------------------------------
-- 5. cms.staging_raw
-- -----------------------------------------------------------------------------
-- Migrating this as-is, matching my decision in Phase 1: every column stays
-- NVARCHAR (even the numeric-looking ones), no constraints, no PK — this
-- mirrors the source exactly, since it's a raw landing table rather than a
-- true relational entity.
-- -----------------------------------------------------------------------------
CREATE TABLE cms.staging_raw (
    rndrng_npi              NVARCHAR(10)   NULL,
    last_org_name           NVARCHAR(100)  NULL,
    first_name              NVARCHAR(50)   NULL,
    middle_initial          NVARCHAR(5)    NULL,
    credentials             NVARCHAR(50)   NULL,
    entity_code             NVARCHAR(5)    NULL,
    street1                 NVARCHAR(100)  NULL,
    street2                 NVARCHAR(100)  NULL,
    city                    NVARCHAR(50)   NULL,
    state_abbr              NVARCHAR(2)    NULL,
    state_fips              NVARCHAR(3)    NULL,
    zip5                    NVARCHAR(5)    NULL,
    ruca                    NVARCHAR(10)   NULL,
    ruca_desc               NVARCHAR(MAX)  NULL,
    country                 NVARCHAR(5)    NULL,
    provider_type           NVARCHAR(100)  NULL,
    medicare_participating  NVARCHAR(1)    NULL,
    hcpcs_cd                NVARCHAR(10)   NULL,
    hcpcs_desc              NVARCHAR(MAX)  NULL,
    hcpcs_drug_ind          NVARCHAR(1)    NULL,
    place_of_service        NVARCHAR(1)    NULL,
    tot_benes               NVARCHAR(20)   NULL,
    tot_srvcs               NVARCHAR(20)   NULL,
    tot_bene_day_srvcs      NVARCHAR(20)   NULL,
    avg_sbmtd_chrg          NVARCHAR(20)   NULL,
    avg_mdcr_alowd_amt      NVARCHAR(20)   NULL,
    avg_mdcr_pymt_amt       NVARCHAR(20)   NULL,
    avg_mdcr_stdzd_amt      NVARCHAR(20)   NULL
);
GO


-- -----------------------------------------------------------------------------
-- 6. audit.data_access_log
-- -----------------------------------------------------------------------------
-- Type mapping notes:
--  - log_id BIGSERIAL -> BIGINT IDENTITY(1,1)
--  - timestamp with time zone -> DATETIMEOFFSET (preserves the time zone info,
--    unlike plain DATETIME2)
--  - inet (client_addr) -> NVARCHAR(45), long enough for an IPv6 address in
--    text form; SQL Server has no native network-address type
--  - jsonb (old_data, new_data) -> JSON, using SQL Server 2025's native JSON
--    type, which is the one PostgreSQL-specific type that actually maps cleanly
--    here rather than falling back to NVARCHAR(MAX)
-- -----------------------------------------------------------------------------
CREATE TABLE audit.data_access_log (
    log_id           BIGINT IDENTITY(1,1)     NOT NULL,
    log_timestamp    DATETIMEOFFSET           NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    db_user          NVARCHAR(100)            NOT NULL,
    client_addr      NVARCHAR(45)             NULL,
    application      NVARCHAR(100)            NULL,
    schema_name      NVARCHAR(50)             NOT NULL,
    table_name       NVARCHAR(100)            NOT NULL,
    operation        NVARCHAR(10)             NOT NULL,
    old_data         JSON                     NULL,
    new_data         JSON                     NULL,
    CONSTRAINT pk_data_access_log PRIMARY KEY (log_id)
);
GO

CREATE INDEX idx_audit_log_table ON audit.data_access_log (schema_name, table_name);
CREATE INDEX idx_audit_log_timestamp ON audit.data_access_log (log_timestamp DESC);
CREATE INDEX idx_audit_log_user ON audit.data_access_log (db_user);
GO


-- =============================================================================
-- Verification queries — run these after executing the script above to confirm
-- everything was created correctly before moving on to data migration.
-- =============================================================================

-- Confirm all 5 tables exist across both schemas
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('cms', 'audit')
ORDER BY s.name, t.name;

-- Confirm primary keys
SELECT s.name AS schema_name, t.name AS table_name, i.name AS pk_name
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE i.is_primary_key = 1 AND s.name IN ('cms', 'audit')
ORDER BY s.name, t.name;

-- Confirm the foreign key
SELECT
    fk.name AS fk_name,
    OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS child_table,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS parent_table
FROM sys.foreign_keys fk;

-- Confirm all indexes
SELECT s.name AS schema_name, t.name AS table_name, i.name AS index_name, i.type_desc
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('cms', 'audit') AND i.name IS NOT NULL
ORDER BY s.name, t.name, i.name;
