-- =============================================================================
-- Phase 4: Validation & Integrity Testing
-- SQL Server-side aggregate checksums (run against the target healthcare_dba)
-- =============================================================================
-- These queries mirror 04_validation_postgresql.sql exactly, column for
-- column, so I can compare the two result sets directly and confirm the
-- actual data (not just row counts) migrated correctly.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- cms.providers
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT rndrng_npi) AS distinct_npi,
    COUNT(DISTINCT state_abbr) AS distinct_states,
    COUNT(ruca) AS non_null_ruca_count,
    SUM(ruca) AS sum_ruca,
    SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) AS null_city_count
FROM cms.providers;

-- -----------------------------------------------------------------------------
-- cms.provider_services
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    MIN(id) AS min_id,
    MAX(id) AS max_id,
    COUNT(DISTINCT rndrng_npi) AS distinct_npi,
    COUNT(DISTINCT hcpcs_cd) AS distinct_hcpcs,
    SUM(tot_benes) AS sum_tot_benes,
    SUM(tot_srvcs) AS sum_tot_srvcs,
    SUM(avg_sbmtd_chrg) AS sum_avg_sbmtd_chrg
FROM cms.provider_services;

-- -----------------------------------------------------------------------------
-- cms.user_state_access
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT username) AS distinct_usernames,
    COUNT(DISTINCT state_abbr) AS distinct_states
FROM cms.user_state_access;

-- -----------------------------------------------------------------------------
-- cms.staging_raw
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT rndrng_npi) AS distinct_npi
FROM cms.staging_raw;
