-- =============================================================================
-- Phase 5: Performance Baseline & Tuning
-- Baseline queries — SQL Server (run against target, before any tuning)
-- =============================================================================
-- Same six queries as 07_baseline_postgresql.sql, translated to T-SQL.
-- SET STATISTICS TIME ON gives me CPU/elapsed time per query.
-- SET STATISTICS IO ON gives me logical reads, which will matter for
-- diagnosing any regressions (missing indexes show up as high logical reads).
--
-- I'll also turn on "Include Actual Execution Plan" in SSMS before running
-- this, so I have execution plans captured for every query, not just timings.
-- =============================================================================

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

-- -----------------------------------------------------------------------------
-- Q1: Point lookup — single provider by primary key
-- -----------------------------------------------------------------------------
SELECT * FROM cms.providers WHERE rndrng_npi = '1538144910';
GO

-- -----------------------------------------------------------------------------
-- Q2: Join + filter — all service lines for providers in one state
-- -----------------------------------------------------------------------------
SELECT p.last_org_name, s.hcpcs_cd, s.tot_srvcs, s.avg_sbmtd_chrg
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
WHERE p.state_abbr = 'CA';
GO

-- -----------------------------------------------------------------------------
-- Q3: Group-by aggregation — provider counts and average RUCA by provider type
-- -----------------------------------------------------------------------------
SELECT provider_type, COUNT(*) AS provider_count, AVG(ruca) AS avg_ruca
FROM cms.providers
GROUP BY provider_type
ORDER BY provider_count DESC;
GO

-- -----------------------------------------------------------------------------
-- Q4: Join + group-by aggregation — total services and avg charge by state
-- -----------------------------------------------------------------------------
SELECT p.state_abbr, SUM(s.tot_srvcs) AS total_services, AVG(s.avg_sbmtd_chrg) AS avg_charge
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
GROUP BY p.state_abbr
ORDER BY total_services DESC;
GO

-- -----------------------------------------------------------------------------
-- Q5: Filtered range scan — evaluation & management codes with high volume
-- -----------------------------------------------------------------------------
SELECT *
FROM cms.provider_services
WHERE hcpcs_cd LIKE '99%' AND tot_srvcs > 10000
ORDER BY tot_srvcs DESC;
GO

-- -----------------------------------------------------------------------------
-- Q6: Heavy join + aggregation + sort — top 20 providers by estimated total
-- Medicare payment
-- -----------------------------------------------------------------------------
SELECT TOP 20
    p.rndrng_npi,
    p.last_org_name,
    p.state_abbr,
    SUM(s.avg_mdcr_pymt_amt * s.tot_srvcs) AS est_total_medicare_payment
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
GROUP BY p.rndrng_npi, p.last_org_name, p.state_abbr
ORDER BY est_total_medicare_payment DESC;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
