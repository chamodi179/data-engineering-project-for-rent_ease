import sys
from snowflake_ops.common import get_snowflake_conn

def backfill(table: str):
    table_upper = table.upper()
    conn = get_snowflake_conn()
    cur = conn.cursor()
    try:
        cur.execute(f"TRUNCATE TABLE RENTEASE_RAW.MYSQL.{table_upper}")
        cur.execute(f"""
            COPY INTO RENTEASE_RAW.MYSQL.{table_upper}
            FROM @RENTEASE_RAW.MYSQL.{table_upper}_STAGE
            FILE_FORMAT = (FORMAT_NAME = RENTEASE_RAW.MYSQL.CSV_STANDARD)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            FORCE = TRUE
        """)
        result = cur.fetchall()
        print(f"[OK] {table}: backfilled — {result}")
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python -m snowflake_ops.backfill <table>")
        sys.exit(1)
    backfill(sys.argv[1])