import sys
from snowflake_ops.common import get_snowflake_conn
from extract.config import TABLES, PRIMARY_KEYS


def dedupe(table: str, conn):
    table_upper = table.upper()
    key_col = PRIMARY_KEYS[table]
    cur = conn.cursor()
    try:
        cur.execute(f"SELECT COUNT(*) FROM RENTEASE_RAW.MYSQL.{table_upper}")
        before = cur.fetchone()[0]

        cur.execute(f"""
            CREATE OR REPLACE TABLE RENTEASE_RAW.MYSQL.{table_upper} AS
            SELECT * EXCLUDE rn FROM (
                SELECT *, ROW_NUMBER() OVER (
                    PARTITION BY {key_col} ORDER BY _loaded_at DESC
                ) AS rn
                FROM RENTEASE_RAW.MYSQL.{table_upper}
            )
            WHERE rn = 1
        """)

        cur.execute(f"SELECT COUNT(*) FROM RENTEASE_RAW.MYSQL.{table_upper}")
        after = cur.fetchone()[0]

        removed = before - after
        print(
            f"[OK] {table:28} {before:>7} -> {after:>7}  ({removed} duplicate(s) removed)")
        return True
    except Exception as e:
        print(f"[FAILED] {table:28} {e}")
        return False
    finally:
        cur.close()


def main():
    # optional: pass specific table names as args, e.g. `python -m snowflake_ops.dedupe_all bookings payments`
    # no args = dedupe every table in TABLES
    tables_to_run = sys.argv[1:] if len(sys.argv) > 1 else list(TABLES.keys())

    invalid = [t for t in tables_to_run if t not in TABLES]
    if invalid:
        print(f"Unknown table(s): {', '.join(invalid)}")
        print(f"Valid tables: {', '.join(TABLES.keys())}")
        sys.exit(1)

    conn = get_snowflake_conn()
    try:
        results = [dedupe(t, conn) for t in tables_to_run]
    finally:
        conn.close()

    failed = results.count(False)
    if failed:
        print(f"\n{failed} table(s) failed to dedupe.")
        sys.exit(1)
    else:
        print(
            f"\nAll {
                len(tables_to_run)} table(s) deduplicated successfully.")


if __name__ == "__main__":
    main()
