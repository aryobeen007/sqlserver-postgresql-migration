-- =============================================================================
-- Phase 2: Schema Conversion — Audit Trigger Conversion
-- Rewriting PostgreSQL's audit.log_data_changes() as T-SQL triggers
-- =============================================================================
-- In PostgreSQL, one generic trigger function (audit.log_data_changes())
-- served both cms.providers and cms.provider_services. It used PostgreSQL's
-- dynamic trigger metadata (TG_TABLE_NAME, TG_TABLE_SCHEMA, TG_OP) and
-- to_jsonb(OLD)/to_jsonb(NEW) to log a full row snapshot on every INSERT,
-- UPDATE, and DELETE.
--
-- T-SQL has no equivalent to a single function shared across multiple table
-- triggers with dynamic table-name awareness — each trigger is bound to one
-- table. So instead of one generic function, I wrote one trigger per table,
-- each following the same pattern:
--   1. Figure out the operation (INSERT / UPDATE / DELETE) by checking which
--      of the inserted/deleted pseudo-tables have rows
--   2. Use a correlated subquery with FOR JSON PATH to serialize each
--      affected row individually — this is the T-SQL equivalent of
--      PostgreSQL's per-row to_jsonb(OLD)/to_jsonb(NEW)
--   3. Insert one audit row per affected row, matching the row-level
--      granularity of the original PostgreSQL trigger
--
-- I capture db_user, client address, and application name using SQL Server's
-- own session functions (SUSER_SNAME(), CONNECTIONPROPERTY(), APP_NAME()) as
-- the equivalents of PostgreSQL's current_user, inet_client_addr(), and
-- current_setting('application_name').
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Trigger on cms.providers
-- -----------------------------------------------------------------------------
-- Primary key: rndrng_npi (single column) — used to correlate inserted/deleted
-- rows so I can pull each row's own old/new JSON snapshot individually.
-- -----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER cms.trg_audit_providers
ON cms.providers
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.data_access_log
        (db_user, client_addr, application, schema_name, table_name, operation, old_data, new_data)
    SELECT
        SUSER_SNAME(),
        CONVERT(NVARCHAR(45), CONNECTIONPROPERTY('client_net_address')),
        APP_NAME(),
        N'cms',
        N'providers',
        CASE
            WHEN i.rndrng_npi IS NOT NULL AND d.rndrng_npi IS NOT NULL THEN N'UPDATE'
            WHEN i.rndrng_npi IS NOT NULL THEN N'INSERT'
            ELSE N'DELETE'
        END,
        (SELECT d2.* FROM deleted d2 WHERE d2.rndrng_npi = d.rndrng_npi
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
        (SELECT i2.* FROM inserted i2 WHERE i2.rndrng_npi = i.rndrng_npi
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.rndrng_npi = d.rndrng_npi;
END;
GO


-- -----------------------------------------------------------------------------
-- 2. Trigger on cms.provider_services
-- -----------------------------------------------------------------------------
-- Primary key: id (single column, IDENTITY) — same pattern as above, just
-- correlated on a different key column.
-- -----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER cms.trg_audit_provider_services
ON cms.provider_services
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.data_access_log
        (db_user, client_addr, application, schema_name, table_name, operation, old_data, new_data)
    SELECT
        SUSER_SNAME(),
        CONVERT(NVARCHAR(45), CONNECTIONPROPERTY('client_net_address')),
        APP_NAME(),
        N'cms',
        N'provider_services',
        CASE
            WHEN i.id IS NOT NULL AND d.id IS NOT NULL THEN N'UPDATE'
            WHEN i.id IS NOT NULL THEN N'INSERT'
            ELSE N'DELETE'
        END,
        (SELECT d2.* FROM deleted d2 WHERE d2.id = d.id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
        (SELECT i2.* FROM inserted i2 WHERE i2.id = i.id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id = d.id;
END;
GO


-- =============================================================================
-- 3. Verification — test the triggers actually work before moving on
-- =============================================================================
-- I'll run one INSERT, one UPDATE, and one DELETE against cms.providers with
-- a throwaway test row, then check that audit.data_access_log picked up all
-- three operations with the right JSON snapshots.
-- =============================================================================

-- Test INSERT
INSERT INTO cms.providers (rndrng_npi, last_org_name, city, state_abbr, provider_type)
VALUES ('TEST00001', 'Trigger Test Provider', 'Testville', 'VA', 'Test Type');

-- Test UPDATE
UPDATE cms.providers
SET city = 'Updated Testville'
WHERE rndrng_npi = 'TEST00001';

-- Test DELETE
DELETE FROM cms.providers
WHERE rndrng_npi = 'TEST00001';

-- Check the results — I expect 3 rows here: one INSERT, one UPDATE, one DELETE,
-- each with the correct old_data/new_data JSON populated (or NULL where
-- expected — no old_data on INSERT, no new_data on DELETE).
SELECT log_id, log_timestamp, db_user, schema_name, table_name, operation, old_data, new_data
FROM audit.data_access_log
WHERE table_name = 'providers'
ORDER BY log_id DESC;
