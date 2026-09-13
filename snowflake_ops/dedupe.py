import sys
from snowflake_ops.common import get_snowflake_conn


def dedupe(table: str, key_col: str = "id"):
    table_upper = table.upper()
    conn = get_snowflake_conn()
    cur = conn.cursor()
    try:
        # keep only the most-recently-loaded row per primary key
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
        count = cur.fetchone()[0]
        print(f"[OK] {table}: deduplicated — {count} rows remain")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python -m snowflake_ops.dedupe <table>")
        sys.exit(1)
    dedupe(sys.argv[1])
