from extract.config import TABLES
from snowflake_ops.reconcile import reconcile


def main():
    total_marked = 0
    for table in TABLES:
        try:
            marked = reconcile(table)
            total_marked += marked
        except Exception as e:
            print(f"[FAILED] {table}: {e}")

    print(
        f"\n--- Reconcile summary: {total_marked} row(s) newly marked deleted across all tables ---")


if __name__ == "__main__":
    main()
