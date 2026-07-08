# Phase 2: Schema Conversion

**Status:** ✅ Complete

## Overview

With the PostgreSQL source fully inventoried in Phase 1, I converted the entire `healthcare_dba` schema to T-SQL for SQL Server 2025 — five tables across two schemas, all keys and indexes, and a full rewrite of the one piece of custom logic in the database: a generic audit-logging trigger.

## Object Mapping Matrix

| PostgreSQL Type/Feature | SQL Server Equivalent | Notes |
|---|---|---|
| `character varying(n)` | `NVARCHAR(n)` | Unicode-safe; source includes provider names/addresses |
| `text` | `NVARCHAR(MAX)` | Used for `ruca_desc`, `hcpcs_desc` (no fixed length in PostgreSQL) |
| `numeric` (no precision) | `DECIMAL(10,4)` or `DECIMAL(18,2)` | I picked a fixed precision per column — `DECIMAL(10,4)` for the coded `ruca` value, `DECIMAL(18,2)` for currency-style amounts, since PostgreSQL's unconstrained `numeric` has no direct T-SQL equivalent |
| `bigint` (`BIGSERIAL`-backed) | `BIGINT IDENTITY(1,1)` | Used for `provider_services.id` and `data_access_log.log_id` |
| `timestamp with time zone` | `DATETIMEOFFSET` | Preserves time zone info, unlike plain `DATETIME2` |
| `inet` | `NVARCHAR(45)` | SQL Server has no native network-address type; 45 chars is enough for any IPv6 address in text form |
| `jsonb` | `JSON` | SQL Server 2025's native JSON type — the one PostgreSQL-specific type that maps cleanly, rather than falling back to `NVARCHAR(MAX)` |
| Composite primary key | `PRIMARY KEY (col1, col2)` | `cms.user_state_access` — both columns listed directly in the constraint, same as PostgreSQL |
| Generic trigger function (`TG_TABLE_NAME`, `TG_OP`, `to_jsonb()`) | One T-SQL trigger per table | T-SQL triggers are bound to a single table, so I wrote separate triggers for `cms.providers` and `cms.provider_services` instead of one shared function |

## Steps I Completed

### 1. Decided on `cms.staging_raw`

I chose to migrate it as-is — every column stays `NVARCHAR`, matching the source exactly, since it's a raw landing table rather than a real relational entity (no PK, no constraints in PostgreSQL either).

### 2. Wrote the core schema DDL

I created both schemas (`cms`, `audit`) and all 5 tables, including:
- All 4 primary keys (1 composite, on `cms.user_state_access`)
- The 1 foreign key (`cms.provider_services.rndrng_npi` → `cms.providers.rndrng_npi`)
- All 8 secondary indexes, matching the originals

I verified everything with catalog queries against `sys.tables`, `sys.indexes`, and `sys.foreign_keys` — all 5 tables, 4 primary keys, 1 foreign key, and 8 secondary indexes came back exactly as expected.

See [`sql/phase-2-schema-conversion/02_schema_conversion.sql`](../sql/phase-2-schema-conversion/02_schema_conversion.sql) for the full script.

### 3. Converted the audit trigger

This was the most interesting part of the whole schema. PostgreSQL used a single generic function (`audit.log_data_changes()`) shared by both triggers, relying on dynamic trigger metadata (`TG_TABLE_NAME`, `TG_TABLE_SCHEMA`, `TG_OP`) and `to_jsonb(OLD)`/`to_jsonb(NEW)` to log a full row snapshot on every INSERT, UPDATE, and DELETE.

T-SQL has no equivalent to one function shared across multiple table triggers with dynamic table awareness, so I wrote two separate triggers — `cms.trg_audit_providers` and `cms.trg_audit_provider_services` — each following the same pattern:

1. Compare the `inserted`/`deleted` pseudo-tables to determine the operation
2. Use a correlated subquery with `FOR JSON PATH` to serialize each affected row individually — the T-SQL equivalent of `to_jsonb(OLD)`/`to_jsonb(NEW)`
3. Insert one audit row per affected row, preserving the original's row-level granularity

I tested both by inserting, updating, and deleting a throwaway test row on `cms.providers` and confirming `audit.data_access_log` captured all three operations correctly:

- **INSERT** — `old_data` NULL, `new_data` populated
- **UPDATE** — both `old_data` and `new_data` populated, correctly reflecting the changed column
- **DELETE** — `old_data` populated with the last known state, `new_data` NULL

I then cleaned up the test rows so the audit table only reflects genuine activity going forward.

See [`sql/phase-2-schema-conversion/03_audit_trigger_conversion.sql`](../sql/phase-2-schema-conversion/03_audit_trigger_conversion.sql) for the full script and test.

## Repository & Evidence

```
sqlserver-postgresql-migration/
├── sql/phase-2-schema-conversion/
│   ├── 02_schema_conversion.sql        ← tables, keys, indexes
│   └── 03_audit_trigger_conversion.sql ← trigger rewrite + verification test
├── docs/                                ← this file
```

## What's Next: Phase 3 — Data Migration

- [ ] Build the ETL pipeline (Python, `psycopg2` + `pyodbc`) to move data from PostgreSQL into the new SQL Server schema
- [ ] Load in FK-safe order: `cms.providers` before `cms.provider_services`
- [ ] Re-seed `IDENTITY` values on `provider_services.id` after loading, so new inserts continue from the correct point
- [ ] Decide how to handle `audit.data_access_log` — the 2 existing PostgreSQL rows are trivial, but I need to confirm whether to carry them over or start fresh now that the SQL Server triggers are live
- [ ] Log the migration run: start/end time, rows loaded per table, throughput, and any errors
