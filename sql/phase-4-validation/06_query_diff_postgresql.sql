-- =============================================================================
-- Phase 4: Validation & Integrity Testing
-- Representative Query Diffing — PostgreSQL version (run against source)
-- =============================================================================
-- Row counts and aggregates prove the data matches at a bulk level. This step
-- runs realistic, application-style queries against both systems and confirms
-- they return identical results — the kind of check a real cutover would
-- depend on before trusting the new system with production traffic.
--
-- Run these three queries here, then run 06_query_diff_sqlserver.sql against
-- SQL Server and compare the two sets of results by eye.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Query A: Top 10 states by provider count
-- -----------------------------------------------------------------------------
SELECT state_abbr, COUNT(*) AS provider_count
FROM cms.providers
GROUP BY state_abbr
ORDER BY provider_count DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Query B: Top 10 HCPCS billing codes by total services, with average charge
-- -----------------------------------------------------------------------------
SELECT
    hcpcs_cd,
    SUM(tot_srvcs) AS total_services,
    AVG(avg_sbmtd_chrg) AS avg_charge
FROM cms.provider_services
GROUP BY hcpcs_cd
ORDER BY total_services DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Query C: Full detail lookup for the single busiest provider
-- (the provider with the most service line items) — a realistic
-- "look up one provider's full record" application query.
-- -----------------------------------------------------------------------------
WITH top_provider AS (
    SELECT rndrng_npi, COUNT(*) AS service_count
    FROM cms.provider_services
    GROUP BY rndrng_npi
    ORDER BY service_count DESC, rndrng_npi ASC
    LIMIT 1
)
SELECT p.rndrng_npi, p.last_org_name, p.city, p.state_abbr, tp.service_count
FROM top_provider tp
JOIN cms.providers p ON p.rndrng_npi = tp.rndrng_npi;
