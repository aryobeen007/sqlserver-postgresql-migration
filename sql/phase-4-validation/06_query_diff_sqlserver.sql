-- =============================================================================
-- Phase 4: Validation & Integrity Testing
-- Representative Query Diffing — SQL Server version (run against target)
-- =============================================================================
-- Same three queries as 06_query_diff_postgresql.sql, translated to T-SQL
-- syntax (TOP instead of LIMIT). Results should match exactly, row for row.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Query A: Top 10 states by provider count
-- -----------------------------------------------------------------------------
SELECT TOP 10 state_abbr, COUNT(*) AS provider_count
FROM cms.providers
GROUP BY state_abbr
ORDER BY provider_count DESC;

-- -----------------------------------------------------------------------------
-- Query B: Top 10 HCPCS billing codes by total services, with average charge
-- -----------------------------------------------------------------------------
SELECT TOP 10
    hcpcs_cd,
    SUM(tot_srvcs) AS total_services,
    AVG(avg_sbmtd_chrg) AS avg_charge
FROM cms.provider_services
GROUP BY hcpcs_cd
ORDER BY total_services DESC;

-- -----------------------------------------------------------------------------
-- Query C: Full detail lookup for the single busiest provider
-- -----------------------------------------------------------------------------
WITH top_provider AS (
    SELECT TOP 1 rndrng_npi, COUNT(*) AS service_count
    FROM cms.provider_services
    GROUP BY rndrng_npi
    ORDER BY COUNT(*) DESC, rndrng_npi ASC
)
SELECT p.rndrng_npi, p.last_org_name, p.city, p.state_abbr, tp.service_count
FROM top_provider tp
JOIN cms.providers p ON p.rndrng_npi = tp.rndrng_npi;
