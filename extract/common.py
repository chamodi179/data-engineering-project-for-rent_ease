import os
import boto3
import pymysql
import csv
import io
from dotenv import load_dotenv
import datetime

load_dotenv()

DB_NAME = "rentease"


def get_mysql_conn():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_READONLY_USER"],
        password=os.environ["DB_READONLY_PASSWORD"],
        database=DB_NAME,
        ssl={"ssl": {}},
        cursorclass=pymysql.cursors.Cursor,
    )


def get_s3_bucket():
    return os.environ["S3_RAW_BUCKET"]


def get_s3_client():
    return boto3.client("s3")


def extract_table(table: str, cursor_col: str, watermark: str |
                  None, lookback_days: int | None) -> tuple[int, str | None]:
    conn = get_mysql_conn()
    try:
        with conn.cursor() as cur:
            if lookback_days:
                # bounded re-read: always pull the trailing window, regardless of watermark.
                # catches in-place updates on tables with no updated_at column.
                cutoff = (datetime.datetime.now(datetime.UTC)
                          - datetime.timedelta(days=lookback_days)).strftime("%Y-%m-%d %H:%M:%S")
                cur.execute(
                    f"SELECT * FROM {table} WHERE {cursor_col} > %s", (cutoff,))
            elif watermark:
                cur.execute(
                    f"SELECT * FROM {table} WHERE {cursor_col} > %s", (watermark,))
            else:
                # first run: full extract
                cur.execute(f"SELECT * FROM {table}")
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description]
    finally:
        conn.close()

    if not rows:
        return 0, watermark

    new_watermark = watermark
    if not lookback_days:  # lookback tables don't advance a watermark — they always re-read the window
        col_idx = cols.index(cursor_col)
        new_watermark = str(max(row[col_idx] for row in rows))

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(cols)
    writer.writerows(rows)

    ts = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d%H%M%S")
    key = f"mysql/{table}/{table}_{ts}.csv"
    get_s3_client().put_object(Bucket=get_s3_bucket(), Key=key, Body=buf.getvalue())

    return len(rows), new_watermark
    """Extracts one table (full extract) and uploads it to S3. Returns row count."""
    conn = get_mysql_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT * FROM {table}")
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description]
    finally:
        conn.close()

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(cols)
    writer.writerows(rows)

    ts = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d%H%M%S")
    key = f"mysql/{table}/{table}_{ts}.csv"

    s3 = get_s3_client()
    s3.put_object(Bucket=get_s3_bucket(), Key=key, Body=buf.getvalue())
    return len(rows)
