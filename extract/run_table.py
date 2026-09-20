import sys
from extract.config import TABLES
from extract.common import extract_table


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TABLES:
        print("Usage: python -m extract.run_table <table>")
        print(f"Valid tables: {', '.join(TABLES)}")
        sys.exit(1)

    table = sys.argv[1]
    try:
        n = extract_table(table)
        print(f"[OK] {table}: {n} rows uploaded")
    except Exception as e:
        print(f"[FAILED] {table}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

# run any single table any time.
# python -m extract.run_table bookings
# python -m extract.run_table users
