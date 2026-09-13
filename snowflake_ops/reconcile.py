import sys
from extract.common import get_mysql_conn
from snowflake_ops.common import get_snowflake_conn
from extract.config import PRIMARY_KEYS


def reconcile(table: str, auto_mark: bool = True) -> int:
    """
    Compares primary keys between MySQL (source of truth) and the Snowflake
    raw table. Rows in Snowflake but no longer in MySQL are hard-deletes
    that batch extraction cannot otherwise detect.

    If auto_mark=True, marks them is_deleted=TRUE, deleted_at=now() —
    a soft delete, not a physical DELETE. Returns the count of newly
    marked rows.
    """
    table_upper = table.upper()
    key_col = PRIMARY_KEYS[table]

    mysql_conn = get_mysql_conn()
    with mysql_conn.cursor() as cur:
        cur.execute(f"SELECT {key_col} FROM {table}")
        mysql_ids = {row[0] for row in cur.fetchall()}
    mysql_conn.close()

    sf_conn = get_snowflake_conn()
    sf_cur = sf_conn.cursor()
    try:
        sf_cur.execute(f"""
            SELECT {key_col} FROM RENTEASE_RAW.MYSQL.{table_upper}
            WHERE is_deleted = FALSE OR is_deleted IS NULL
        """)
        sf_ids = {row[0] for row in sf_cur.fetchall()}

        orphaned = sf_ids - mysql_ids
        if not orphaned:
            print(
                f"[OK] {table}: no orphaned rows — {
                    len(sf_ids)} rows match MySQL")
            return 0

        print(
            f"[WARNING] {table}: {
                len(orphaned)} row(s) no longer exist in MySQL")

        if auto_mark:
            ids_list = ",".join(str(i) for i in orphaned)
            sf_cur.execute(f"""
                UPDATE RENTEASE_RAW.MYSQL.{table_upper}
                SET is_deleted = TRUE, deleted_at = CURRENT_TIMESTAMP()
                WHERE {key_col} IN ({ids_list})
            """)
            sf_conn.commit()
            print(
                f"[MARKED] {table}: {
                    len(orphaned)} row(s) marked is_deleted=TRUE")
        else:
            print(f"  Orphaned {key_col}s: {sorted(orphaned)[:20]}")

        return len(orphaned)
    finally:
        sf_cur.close()
        sf_conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python -m snowflake_ops.reconcile <table>")
        sys.exit(1)
    reconcile(sys.argv[1])
