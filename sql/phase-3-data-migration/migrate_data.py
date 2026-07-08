"""
Phase 3: Data Migration
Moves all data from PostgreSQL (healthcare_dba) to SQL Server (SQLDBA-Primary).

I built this as a straightforward, table-by-table ETL script rather than using
a GUI migration tool, since SSMA doesn't support PostgreSQL as a source (see
docs/phase-1-assessment-environment-prep.md for that finding).

Design decisions:
  - Passwords are prompted at runtime (getpass), never hardcoded, so nothing
    sensitive ends up committed to the repo.
  - I load in FK-safe order: providers before provider_services.
  - I disable the audit triggers on cms.providers and cms.provider_services
    before the bulk load and re-enable them immediately after. Without this,
    every one of the ~10.8 million rows I'm inserting into those two tables
    would fire the audit trigger, flooding audit.data_access_log with
    migration noise instead of real activity, and slowing the load
    dramatically with row-by-row trigger overhead.
  - I use pyodbc's fast_executemany with batching for the two large tables,
    since row-by-row inserts would take far too long at this scale (~20.5M
    rows total).
  - provider_services.id is an IDENTITY column, but I need to preserve the
    exact source IDs (since nothing else references them, but I want an
    honest 1:1 copy) — so I turn on IDENTITY_INSERT during that table's load,
    then reseed the identity counter afterward so future inserts continue
    correctly.
  - I log start/end time, row counts, and throughput for every table, and
    validate row counts against the source at the end.
"""

import time
import getpass
import psycopg2
import pyodbc

# -----------------------------------------------------------------------------
# Connection details — non-secret values only; passwords are prompted below.
# -----------------------------------------------------------------------------
PG_HOST = "localhost"
PG_PORT = 5432
PG_DB = "healthcare_dba"
PG_USER = "postgres"

SQL_SERVER_HOST = "192.168.1.198"
SQL_DB = "healthcare_dba"
SQL_USER = "etl_service"

BATCH_SIZE = 10000

pg_password = getpass.getpass("PostgreSQL password for 'postgres': ")
sql_password = getpass.getpass("SQL Server password for 'etl_service': ")

# -----------------------------------------------------------------------------
# Connect to both databases
# -----------------------------------------------------------------------------
print("Connecting to PostgreSQL...")
pg_conn = psycopg2.connect(
    host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=pg_password
)

print("Connecting to SQL Server...")
sql_conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={SQL_SERVER_HOST};DATABASE={SQL_DB};"
    f"UID={SQL_USER};PWD={sql_password};"
    f"Encrypt=yes;TrustServerCertificate=yes;"
)
sql_conn.autocommit = False
sql_cursor = sql_conn.cursor()
sql_cursor.fast_executemany = True

migration_log = []


def migrate_table(source_query, target_table, target_columns, identity_insert=False):
    """
    Reads all rows from PostgreSQL for a given query and bulk-inserts them
    into the named SQL Server table, in batches, using fast_executemany.
    Returns (row_count, elapsed_seconds).
    """
    print(f"\nMigrating {target_table} ...")
    start = time.time()

    pg_cursor = pg_conn.cursor(name=f"cursor_{target_table.replace('.', '_')}")
    pg_cursor.itersize = BATCH_SIZE
    pg_cursor.execute(source_query)

    col_list = ", ".join(target_columns)
    placeholders = ", ".join(["?"] * len(target_columns))
    insert_sql = f"INSERT INTO {target_table} ({col_list}) VALUES ({placeholders})"

    if identity_insert:
        sql_cursor.execute(f"SET IDENTITY_INSERT {target_table} ON")

    total_rows = 0
    while True:
        rows = pg_cursor.fetchmany(BATCH_SIZE)
        if not rows:
            break
        sql_cursor.executemany(insert_sql, rows)
        sql_conn.commit()
        total_rows += len(rows)
        print(f"  ... {total_rows:,} rows loaded", end="\r")

    if identity_insert:
        sql_cursor.execute(f"SET IDENTITY_INSERT {target_table} OFF")
        sql_conn.commit()

    pg_cursor.close()
    elapsed = time.time() - start
    print(f"  Done: {total_rows:,} rows in {elapsed:.1f}s ({total_rows/elapsed:.0f} rows/sec)")
    migration_log.append((target_table, total_rows, elapsed))
    return total_rows, elapsed


# -----------------------------------------------------------------------------
# Disable audit triggers before bulk loading providers / provider_services
# -----------------------------------------------------------------------------
print("Disabling audit triggers for bulk load...")
sql_cursor.execute("ALTER TABLE cms.providers DISABLE TRIGGER trg_audit_providers")
sql_cursor.execute("ALTER TABLE cms.provider_services DISABLE TRIGGER trg_audit_provider_services")
sql_conn.commit()

try:
    # -------------------------------------------------------------------------
    # 1. cms.providers — no dependencies, must load before provider_services
    # -------------------------------------------------------------------------
    migrate_table(
        source_query="""
            SELECT rndrng_npi, last_org_name, first_name, middle_initial, credentials,
                   entity_code, street1, street2, city, state_abbr, state_fips, zip5,
                   ruca, ruca_desc, country, provider_type, medicare_participating
            FROM cms.providers
        """,
        target_table="cms.providers",
        target_columns=[
            "rndrng_npi", "last_org_name", "first_name", "middle_initial", "credentials",
            "entity_code", "street1", "street2", "city", "state_abbr", "state_fips", "zip5",
            "ruca", "ruca_desc", "country", "provider_type", "medicare_participating",
        ],
    )

    # -------------------------------------------------------------------------
    # 2. cms.provider_services — depends on providers via FK; preserving source IDs
    # -------------------------------------------------------------------------
    migrate_table(
        source_query="""
            SELECT id, rndrng_npi, hcpcs_cd, hcpcs_desc, hcpcs_drug_ind, place_of_service,
                   tot_benes, tot_srvcs, tot_bene_day_srvcs, avg_sbmtd_chrg,
                   avg_mdcr_alowd_amt, avg_mdcr_pymt_amt, avg_mdcr_stdzd_amt
            FROM cms.provider_services
        """,
        target_table="cms.provider_services",
        target_columns=[
            "id", "rndrng_npi", "hcpcs_cd", "hcpcs_desc", "hcpcs_drug_ind", "place_of_service",
            "tot_benes", "tot_srvcs", "tot_bene_day_srvcs", "avg_sbmtd_chrg",
            "avg_mdcr_alowd_amt", "avg_mdcr_pymt_amt", "avg_mdcr_stdzd_amt",
        ],
        identity_insert=True,
    )

    # -------------------------------------------------------------------------
    # 3. cms.user_state_access — small, no dependencies
    # -------------------------------------------------------------------------
    migrate_table(
        source_query="SELECT username, state_abbr FROM cms.user_state_access",
        target_table="cms.user_state_access",
        target_columns=["username", "state_abbr"],
    )

    # -------------------------------------------------------------------------
    # 4. cms.staging_raw — no dependencies, migrated as-is (all varchar)
    # -------------------------------------------------------------------------
    migrate_table(
        source_query="""
            SELECT rndrng_npi, last_org_name, first_name, middle_initial, credentials,
                   entity_code, street1, street2, city, state_abbr, state_fips, zip5,
                   ruca, ruca_desc, country, provider_type, medicare_participating,
                   hcpcs_cd, hcpcs_desc, hcpcs_drug_ind, place_of_service,
                   tot_benes, tot_srvcs, tot_bene_day_srvcs, avg_sbmtd_chrg,
                   avg_mdcr_alowd_amt, avg_mdcr_pymt_amt, avg_mdcr_stdzd_amt
            FROM cms.staging_raw
        """,
        target_table="cms.staging_raw",
        target_columns=[
            "rndrng_npi", "last_org_name", "first_name", "middle_initial", "credentials",
            "entity_code", "street1", "street2", "city", "state_abbr", "state_fips", "zip5",
            "ruca", "ruca_desc", "country", "provider_type", "medicare_participating",
            "hcpcs_cd", "hcpcs_desc", "hcpcs_drug_ind", "place_of_service",
            "tot_benes", "tot_srvcs", "tot_bene_day_srvcs", "avg_sbmtd_chrg",
            "avg_mdcr_alowd_amt", "avg_mdcr_pymt_amt", "avg_mdcr_stdzd_amt",
        ],
    )

finally:
    # -------------------------------------------------------------------------
    # Always re-enable the audit triggers, even if something above failed
    # -------------------------------------------------------------------------
    print("\nRe-enabling audit triggers...")
    sql_cursor.execute("ALTER TABLE cms.providers ENABLE TRIGGER trg_audit_providers")
    sql_cursor.execute("ALTER TABLE cms.provider_services ENABLE TRIGGER trg_audit_provider_services")
    sql_conn.commit()

# -----------------------------------------------------------------------------
# Reseed the IDENTITY counter on provider_services after explicit ID inserts
# -----------------------------------------------------------------------------
print("Reseeding IDENTITY on cms.provider_services...")
sql_cursor.execute("DBCC CHECKIDENT ('cms.provider_services', RESEED)")
sql_conn.commit()

# -----------------------------------------------------------------------------
# Row count validation — compare source vs. target for every table migrated
# -----------------------------------------------------------------------------
print("\n=== Row count validation ===")
pg_check_cursor = pg_conn.cursor()
tables_to_check = [
    ("cms.providers", "cms.providers"),
    ("cms.provider_services", "cms.provider_services"),
    ("cms.user_state_access", "cms.user_state_access"),
    ("cms.staging_raw", "cms.staging_raw"),
]
for pg_table, sql_table in tables_to_check:
    pg_check_cursor.execute(f"SELECT COUNT(*) FROM {pg_table}")
    pg_count = pg_check_cursor.fetchone()[0]

    sql_cursor.execute(f"SELECT COUNT(*) FROM {sql_table}")
    sql_count = sql_cursor.fetchone()[0]

    status = "MATCH" if pg_count == sql_count else "MISMATCH"
    print(f"  {sql_table}: source={pg_count:,}  target={sql_count:,}  [{status}]")

# -----------------------------------------------------------------------------
# Migration summary
# -----------------------------------------------------------------------------
print("\n=== Migration summary ===")
total_rows = sum(r for _, r, _ in migration_log)
total_time = sum(t for _, _, t in migration_log)
for table, rows, elapsed in migration_log:
    print(f"  {table}: {rows:,} rows in {elapsed:.1f}s")
print(f"  TOTAL: {total_rows:,} rows in {total_time:.1f}s ({total_rows/total_time:.0f} rows/sec)")

pg_conn.close()
sql_conn.close()
print("\nMigration complete.")
