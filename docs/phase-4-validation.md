# Phase 4: Validation & Integrity Testing

**Status:** ✅ Complete

## Overview

Row counts from Phase 3 only proved I moved the right *quantity* of data. This phase proves the data, the rules, and real query behavior all migrated correctly too — not just that PostgreSQL and SQL Server have the same number of rows, but that they agree on the actual values, enforce the same constraints, and answer the same questions identically.

I ran three layers of validation: aggregate checksums, constraint enforcement tests, and representative query diffing.

## 1. Aggregate Checksums

Beyond row counts, I compared sums, distinct counts, min/max values, and null counts for every table — a lightweight but effective way to catch silent data corruption that a row count alone would miss.

| Table | Check | PostgreSQL | SQL Server | Match |
|---|---|---|---|---|
| `cms.providers` | total_rows | 1,175,281 | 1,175,281 | ✅ |
| | distinct_npi | 1,175,281 | 1,175,281 | ✅ |
| | distinct_states | 62 | 62 | ✅ |
| | non_null_ruca_count | 1,174,260 | 1,174,260 | ✅ |
| | sum_ruca | 1,891,711.8 | 1,891,711.8000 | ✅ |
| | null_city_count | 0 | 0 | ✅ |
| `cms.provider_services` | total_rows | 9,660,647 | 9,660,647 | ✅ |
| | min_id / max_id | 1 / 9,660,647 | 1 / 9,660,647 | ✅ |
| | distinct_npi | 1,175,281 | 1,175,281 | ✅ |
| | distinct_hcpcs | 6,405 | 6,405 | ✅ |
| | sum_tot_benes | 824,740,808 | 824,740,808 | ✅ |
| | sum_tot_srvcs | 2,645,589,825.30 | 2,645,589,825.30 | ✅ |
| | sum_avg_sbmtd_chrg | 4,026,836,405.50 | 4,026,836,405.50 | ✅ |
| `cms.user_state_access` | total_rows | 2 | 2 | ✅ |
| `cms.staging_raw` | total_rows | 9,660,647 | 9,660,647 | ✅ |

Every single value matched exactly. See [`sql/phase-4-validation/04_validation_postgresql.sql`](../sql/phase-4-validation/04_validation_postgresql.sql) and [`04_validation_sqlserver.sql`](../sql/phase-4-validation/04_validation_sqlserver.sql).

## 2. Constraint Enforcement Testing

Matching data is only half the story — I also needed to prove SQL Server enforces the same rules PostgreSQL did. I ran four intentionally-bad inserts against the target, each wrapped in TRY/CATCH:

| Test | Attempted | Result |
|---|---|---|
| 1. Duplicate primary key | Insert a `cms.providers` row with an NPI that already exists | ✅ Rejected — `Violation of PRIMARY KEY constraint 'pk_providers'` |
| 2. Invalid foreign key | Insert a `cms.provider_services` row referencing a non-existent NPI | ✅ Rejected — `FOREIGN KEY constraint "fk_provider_services_npi"` conflict |
| 3. NULL in NOT NULL column | Insert a provider with `last_org_name = NULL` | ✅ Rejected — `column does not allow nulls` |
| 4. Duplicate composite primary key | Insert a duplicate `(username, state_abbr)` pair | ✅ Rejected — `Violation of PRIMARY KEY constraint 'pk_user_state_access'` |

All four were correctly rejected with the expected, specific error message, and I confirmed the row counts on all three affected tables were unchanged afterward — none of the bad inserts leaked through.

See [`sql/phase-4-validation/05_constraint_tests.sql`](../sql/phase-4-validation/05_constraint_tests.sql).

## 3. Representative Query Diffing

Finally, I ran three realistic, application-style queries against both systems to confirm they answer the same questions identically:

**Query A — Top 10 states by provider count:** identical states, identical order, identical counts on both systems (California highest at 93,498, down through New Jersey at 36,541).

**Query B — Top 10 billing codes (HCPCS) by total services, with average charge:** identical codes, identical order, identical totals on both systems.

**Query C — Full record lookup for the single busiest provider:** both systems returned the exact same result — Laboratory Corporation Of America Holdings, Burlington NC, 658 service line items.

**One difference worth noting, not a defect:** `avg_charge` in Query B showed more decimal places in PostgreSQL (e.g. `12.1390770659854693`) than SQL Server (`12.139077`). Since the underlying `SUM(avg_sbmtd_chrg)` values matched exactly in the aggregate checks above, this is purely a difference in how each engine's `AVG()` function handles display precision internally — not a sign of data corruption or a migration defect.

See [`sql/phase-4-validation/06_query_diff_postgresql.sql`](../sql/phase-4-validation/06_query_diff_postgresql.sql) and [`06_query_diff_sqlserver.sql`](../sql/phase-4-validation/06_query_diff_sqlserver.sql).

## Summary

| Validation Layer | Result |
|---|---|
| Row counts (4 tables) | ✅ Exact match |
| Aggregate checksums (sums, distinct counts, min/max, nulls) | ✅ Exact match |
| Constraint enforcement (PK, FK, NOT NULL, composite PK) | ✅ All 4 correctly rejected |
| Representative query diffing (3 queries) | ✅ Match (minor engine-level rounding difference noted, not a defect) |

I'm confident at this point that the migration is not just complete, but correct — data, rules, and real-world query behavior all check out.

## Repository & Evidence

```
sqlserver-postgresql-migration/
├── sql/phase-4-validation/
│   ├── 04_validation_postgresql.sql
│   ├── 04_validation_sqlserver.sql
│   ├── 05_constraint_tests.sql
│   ├── 06_query_diff_postgresql.sql
│   └── 06_query_diff_sqlserver.sql
├── docs/                              ← this file
```

## What's Next: Phase 5 — Performance Baseline & Tuning

- [ ] Select 5–6 representative queries covering typical read/write/aggregate patterns
- [ ] Baseline execution time for each query on PostgreSQL before comparing
- [ ] Run the same queries on SQL Server and capture execution plans
- [ ] Diagnose any regressions (missing indexes, stale statistics, parameter sniffing)
- [ ] Apply fixes and re-measure — document before/after timing
