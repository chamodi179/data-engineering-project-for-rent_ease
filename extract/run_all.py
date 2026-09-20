# extract/run_all.py — pass lookback_days through
from extract.config import TABLES
from extract.common import extract_table
from extract.state import load_watermarks, save_watermarks


def main():
    state = load_watermarks()
    results = {}

    for table, cfg in TABLES.items():
        cursor_col = cfg["cursor"]
        lookback = cfg["lookback_days"]
        watermark = state.get(table)
        try:
            n, new_watermark = extract_table(
                table, cursor_col, watermark, lookback)
            results[table] = ("OK", n)
            print(f"[OK] {table}: {n} rows")
            if not lookback and new_watermark != watermark:
                state[table] = new_watermark
                save_watermarks(state)
        except Exception as e:
            results[table] = ("FAILED", str(e))
            print(f"[FAILED] {table}: {e}")

    print("\n--- Summary ---")
    for table, (status, detail) in results.items():
        print(f"{status:8} {table:28} {detail}")


if __name__ == "__main__":
    main()
