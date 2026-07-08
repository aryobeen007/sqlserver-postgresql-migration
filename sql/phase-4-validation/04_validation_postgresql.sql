-- =============================================================================
-- Phase 4: Validation & Integrity Testing
-- PostgreSQL-side aggregate checksums (run against the source healthcare_dba)
-- =============================================================================
-- Row counts alone (done in Phase 3) only prove I moved the right NUMBER of
-- rows, not that the actual VALUES are correct. Here I compute aggregate
-- checksums per table — sums, distinct counts, min/max — on the PostgreSQL
-- source, then run the matching queries against SQL Server
-- (04_validation_sqlserver.sql) and compare the two sets of results by eye.
--
-- If every aggregate matches, that's strong evidence the data itself, not
-- just the row count, migrated correctly.
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
    COUNT(*) FILTER (WHERE city IS NULL) AS null_city_count
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
