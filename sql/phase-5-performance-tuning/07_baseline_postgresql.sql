-- =============================================================================
-- Phase 5: Performance Baseline & Tuning
-- Baseline queries — PostgreSQL (run against source, before any tuning)
-- =============================================================================
-- Six queries covering different real-world access patterns, so the baseline
-- reflects a realistic workload rather than one type of query:
--   Q1 - point lookup (single row by primary key)
--   Q2 - join + filter (provider services for one state)
--   Q3 - group-by aggregation (provider counts by type)
--   Q4 - join + group-by aggregation (service volume by state)
--   Q5 - filtered range scan (pattern match + numeric threshold)
--   Q6 - heavy join + aggregation + sort + top-N (most expensive query)
--
-- \timing is on so I get wall-clock time for each query printed automatically.
-- I'm running each query twice: once cold, once warm (immediately after), so I
-- can see caching effects rather than mistaking a cold cache for a real
-- performance problem.
-- =============================================================================

\timing on

-- -----------------------------------------------------------------------------
-- Q1: Point lookup — single provider by primary key
-- -----------------------------------------------------------------------------
SELECT * FROM cms.providers WHERE rndrng_npi = '1538144910';

-- -----------------------------------------------------------------------------
-- Q2: Join + filter — all service lines for providers in one state
-- -----------------------------------------------------------------------------
SELECT p.last_org_name, s.hcpcs_cd, s.tot_srvcs, s.avg_sbmtd_chrg
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
WHERE p.state_abbr = 'CA';

-- -----------------------------------------------------------------------------
-- Q3: Group-by aggregation — provider counts and average RUCA by provider type
-- -----------------------------------------------------------------------------
SELECT provider_type, COUNT(*) AS provider_count, AVG(ruca) AS avg_ruca
FROM cms.providers
GROUP BY provider_type
ORDER BY provider_count DESC;

-- -----------------------------------------------------------------------------
-- Q4: Join + group-by aggregation — total services and avg charge by state
-- -----------------------------------------------------------------------------
SELECT p.state_abbr, SUM(s.tot_srvcs) AS total_services, AVG(s.avg_sbmtd_chrg) AS avg_charge
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
GROUP BY p.state_abbr
ORDER BY total_services DESC;

-- -----------------------------------------------------------------------------
-- Q5: Filtered range scan — evaluation & management codes with high volume
-- -----------------------------------------------------------------------------
SELECT *
FROM cms.provider_services
WHERE hcpcs_cd LIKE '99%' AND tot_srvcs > 10000
ORDER BY tot_srvcs DESC;

-- -----------------------------------------------------------------------------
-- Q6: Heavy join + aggregation + sort — top 20 providers by estimated total
-- Medicare payment (the most expensive query: touches both large tables,
-- aggregates, and sorts the full result)
-- -----------------------------------------------------------------------------
SELECT
    p.rndrng_npi,
    p.last_org_name,
    p.state_abbr,
    SUM(s.avg_mdcr_pymt_amt * s.tot_srvcs) AS est_total_medicare_payment
FROM cms.providers p
JOIN cms.provider_services s ON p.rndrng_npi = s.rndrng_npi
GROUP BY p.rndrng_npi, p.last_org_name, p.state_abbr
ORDER BY est_total_medicare_payment DESC
LIMIT 20;

-- Run the whole block a second time immediately after, to capture warm-cache
-- timings alongside the cold ones.
