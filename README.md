# PostgreSQL to SQL Server Migration Project

A production-style, end-to-end migration of a PostgreSQL healthcare database to Microsoft SQL Server 2025, built as a portfolio project. I moved ~20.5 million rows across 5 tables and 2 schemas, converted a custom PL/pgSQL audit trigger to native T-SQL, and validated the result at three levels — data, constraints, and real query behavior — before baselining and tuning performance against the source system.

## Project Overview

I used a CMS Medicare provider and services dataset (~20.5 million rows across 5 tables) to simulate a real production healthcare database migration. The project covers assessment, schema conversion, data migration, validation, and performance tuning — the full scope of what a database migration actually requires, not just moving tables.

## Stats

| | |
|---|---|
| **Rows Migrated** | ~20.5 million |
| **Tables** | 5, across 2 schemas |
| **Migration Duration** | ~14.8 minutes |
| **Validation Checks** | Row counts, aggregate checksums, constraint enforcement, query diffing — all passed |
| **Performance** | SQL Server faster on 4 of 6 baseline queries; 1 investigated bottleneck documented as structural |
| **Phases** | 6 |

## Tech Stack

`PostgreSQL 18` · `SQL Server 2025 Enterprise Developer Edition` · `Hyper-V` · `Windows Server 2025` · `Python (psycopg2, pyodbc)` · `T-SQL` · `SSMS 21`

## Phases

| Phase | Topic | Status |
|---|---|---|
| 1 | [Assessment & Environment Prep](docs/phase-1-assessment-environment-prep.md) | ✅ Complete |
| 2 | [Schema Conversion](docs/phase-2-schema-conversion.md) | ✅ Complete |
| 3 | [Data Migration](docs/phase-3-data-migration.md) | ✅ Complete |
| 4 | [Validation & Integrity Testing](docs/phase-4-validation.md) | ✅ Complete |
| 5 | [Performance Baseline & Tuning](docs/phase-5-performance-tuning.md) | ✅ Complete |
| 6 | Documentation & Portfolio Packaging | 🟡 In Progress |

## What This Project Demonstrates

- **Real-world troubleshooting** — TCP/IP and firewall configuration, ODBC driver setup, permission scoping, and a live login-failure diagnosis, all documented as they happened rather than smoothed over
- **A genuine tooling pivot** — discovered mid-project that Microsoft's SSMA no longer supports PostgreSQL as a source, and adapted with a custom Python ETL instead of forcing an unavailable tool
- **A non-trivial schema conversion challenge** — rewriting a generic PL/pgSQL audit-logging function (shared across multiple triggers via dynamic metadata) as table-specific T-SQL triggers using the native `JSON` type and `FOR JSON PATH`
- **Rigorous validation** — not just row counts, but aggregate checksums, constraint enforcement testing, and representative query diffing against the live source
- **Honest performance analysis** — four different tuning attempts on one underperforming query, concluding with a documented structural finding rather than a forced or misleading "fix"

## Repository Structure

```
sqlserver-postgresql-migration/
├── sql/
│   ├── phase-1-assessment/
│   ├── phase-2-schema-conversion/
│   ├── phase-3-data-migration/
│   ├── phase-4-validation/
│   └── phase-5-performance-tuning/
├── docs/              ← detailed write-up for each phase
├── diagrams/
├── screenshots/       ← evidence captured at each milestone
└── backups/
```

## Architecture

Built on a single Windows 11 Pro laptop (64 GB RAM) using Hyper-V: a Windows Server 2025 VM runs SQL Server 2025 Enterprise Developer Edition, networked to a native PostgreSQL 18 installation on the host. Full details in the [Phase 1 documentation](docs/phase-1-assessment-environment-prep.md).

## Related Project

This database now serves as the foundation for a follow-on [Enterprise SQL Server DBA Project](https://github.com/aryobeen007/sqlserver-enterprise-dba), covering installation, storage/maintenance, security, auditing, automation, Always On Availability Groups, and monitoring.
