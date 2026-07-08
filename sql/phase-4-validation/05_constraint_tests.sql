-- =============================================================================
-- Phase 4: Validation & Integrity Testing
-- Constraint Enforcement Tests (run against SQL Server target)
-- =============================================================================
-- Row counts and aggregates prove the data matches. This proves the RULES
-- migrated too — that SQL Server actually rejects bad data the same way
-- PostgreSQL's constraints would have. Each test wraps an intentionally bad
-- insert in TRY/CATCH so I can confirm it was rejected, then prints the
-- actual error message SQL Server raised.
-- =============================================================================

USE healthcare_dba;
GO

-- -----------------------------------------------------------------------------
-- Test 1: Duplicate primary key on cms.providers
-- -----------------------------------------------------------------------------
-- I'm trying to insert a second row with an NPI that already exists.
-- Expected: rejected with a primary key violation.
-- -----------------------------------------------------------------------------
BEGIN TRY
    INSERT INTO cms.providers (rndrng_npi, last_org_name, city, state_abbr, provider_type)
    SELECT TOP 1 rndrng_npi, 'Duplicate PK Test', 'Testville', 'VA', 'Test Type'
    FROM cms.providers;

    PRINT 'TEST 1 FAILED: duplicate PK insert was allowed!';
END TRY
BEGIN CATCH
    PRINT 'TEST 1 PASSED: duplicate PK insert correctly rejected.';
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- Test 2: Invalid foreign key on cms.provider_services
-- -----------------------------------------------------------------------------
-- I'm trying to insert a service row referencing an NPI that does not exist
-- in cms.providers. Expected: rejected with a foreign key violation.
-- -----------------------------------------------------------------------------
BEGIN TRY
    INSERT INTO cms.provider_services
        (rndrng_npi, hcpcs_cd, tot_benes, tot_srvcs, avg_sbmtd_chrg)
    VALUES
        ('0000000000', 'TESTCODE', 1, 1, 100.00);

    PRINT 'TEST 2 FAILED: invalid FK insert was allowed!';
END TRY
BEGIN CATCH
    PRINT 'TEST 2 PASSED: invalid FK insert correctly rejected.';
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- Test 3: NULL in a NOT NULL column on cms.providers
-- -----------------------------------------------------------------------------
-- last_org_name is NOT NULL in both PostgreSQL and SQL Server.
-- Expected: rejected with a NULL constraint violation.
-- -----------------------------------------------------------------------------
BEGIN TRY
    INSERT INTO cms.providers (rndrng_npi, last_org_name, city, state_abbr, provider_type)
    VALUES ('TESTNULL01', NULL, 'Testville', 'VA', 'Test Type');

    PRINT 'TEST 3 FAILED: NULL insert into NOT NULL column was allowed!';
END TRY
BEGIN CATCH
    PRINT 'TEST 3 PASSED: NULL insert correctly rejected.';
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- Test 4: Duplicate composite primary key on cms.user_state_access
-- -----------------------------------------------------------------------------
-- Expected: rejected, since (username, state_abbr) together must be unique.
-- -----------------------------------------------------------------------------
BEGIN TRY
    INSERT INTO cms.user_state_access (username, state_abbr)
    SELECT TOP 1 username, state_abbr
    FROM cms.user_state_access;

    PRINT 'TEST 4 FAILED: duplicate composite PK insert was allowed!';
END TRY
BEGIN CATCH
    PRINT 'TEST 4 PASSED: duplicate composite PK insert correctly rejected.';
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- Cleanup check — confirm none of the failed test inserts actually landed
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS providers_count_should_be_unchanged FROM cms.providers;
SELECT COUNT(*) AS provider_services_count_should_be_unchanged FROM cms.provider_services;
SELECT COUNT(*) AS user_state_access_count_should_be_unchanged FROM cms.user_state_access;
