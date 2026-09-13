# RentEase Analytics Warehouse — Architecture

Source system: MySQL 8 (RDS), 10 OLTP tables — `categories`, `branches`,
`users`, `item_catalog`, `item_photos`, `items`, `bookings`,
`booking_status_history`, `payments`, `audit_logs`.
Target: Snowflake, built medallion-style (Bronze → Silver → Gold).

## 1. Snowflake object layout

```
RENTEASE_RAW                    (database — Bronze)
  └── MYSQL                     (schema — one per source system)
        categories, branches, users, item_catalog, item_photos,
        items, bookings, booking_status_history, payments, audit_logs
        + one STAGE, PIPE, FILE FORMAT per table

RENTEASE_ANALYTICS              (database — Silver + Gold)
  ├── STAGING                   (Silver — 1:1 cleaned dbt models)
  │     stg_mysql__<table>      (one per Bronze table, all views)
  ├── INTERMEDIATE              (dbt int_ models, not exposed to BI)
  └── MARTS                     (Gold — star schema + reports)
        dim_date, dim_users, dim_branches, dim_items
        fct_bookings, fct_payments, fct_booking_status_events, fct_audit_events
        rpt_customer_rfm, rpt_customer_cohort_retention
```

## 2. Warehouses (compute)

| Warehouse | Size | Auto-suspend | Used by |
|---|---|---|---|
| `LOAD_WH` | XSmall | 60s | Snowpipe / stage loading |
| `TRANSFORM_WH` | Small | 60s | dbt (staging + marts builds) |
| `BI_WH` | XSmall | 300s | Analysts / BI queries |

Separated so a long-running dbt build never stalls ingestion or a
dashboard query, and vice versa.

## 3. Roles (RBAC)

| Role | Access | Used by |
|---|---|---|
| `LOADER` | Owns stages/pipes, writes to Bronze | Snowpipe |
| `TRANSFORMER` | Reads Bronze, writes Silver + Gold | dbt service user (`dbt_transformer`) |
| `ANALYST` | Read-only on Gold, PII masked | Analysts, BI tools |
| `PII_ANALYST` | Read-only on Gold, PII unmasked | Granted sparingly |

## 4. Ingestion: RDS → S3 → Snowpipe

RDS has no direct connection to Snowflake — everything lands in S3
first. This is permanent, not a bootstrap step: even a future CDC
upgrade would still write to S3, just via a different upstream writer.

```
RDS (queried via scheduled batch SELECT)
    → Python extractor writes CSV to S3, one file per table per run
        → S3 (s3://rentease-raw/mysql/<table>/)
            → S3 event notification → SQS → Snowpipe auto-ingests
                → RENTEASE_RAW.MYSQL.<TABLE>
```

**Extraction strategy per table**, defined in `extract/config.py`:

| Table | Cursor column | Notes |
|---|---|---|
| categories, branches, users, item_catalog, items | `updated_at` | Standard incremental — `WHERE updated_at > watermark` |
| item_photos, booking_status_history, audit_logs | `created_at` / `changed_at` | Append-only, no updates possible |
| bookings | `updated_at` | Incremental |
| **payments** | `created_at`, 30-day lookback | **No `updated_at` column exists** — status mutates (`pending → success/failed`) in place with no timestamp signal. Mitigated by always re-pulling the trailing 30 days and deduping by `_loaded_at` in Snowflake. This is a known, accepted gap: a payment resolving after 30 days would be missed. |

**Deletes — handled via reconciliation, not real-time capture.** Batch
`SELECT`-based extraction can only see rows that still exist; a hard
delete in MySQL is invisible to a `WHERE updated_at > ?` query. Closed
with a reconcile-and-soft-delete step rather than left as an open gap:

1. Every Bronze table carries `is_deleted BOOLEAN` and `deleted_at
   TIMESTAMP_NTZ` columns (added via `ALTER TABLE`, since Bronze schemas
   are ours to extend even though the MySQL source can't be altered).
2. `snowflake_ops/reconcile.py` diffs primary keys between MySQL and the
   corresponding raw table; any key present in Snowflake but absent from
   MySQL is marked `is_deleted = TRUE, deleted_at = now()` — a soft
   delete, so the row's history is preserved rather than physically
   removed.
3. `snowflake_ops/reconcile_all.py` runs this across all 10 tables in
   one call, and is wired into the Airflow DAG (see §8) so it runs on
   every pipeline cycle, not just on demand.
4. Every staging model filters `where is_deleted = false or is_deleted
   is null`, so Silver and Gold only ever see live rows — a deleted
   record disappears from marts the same way it would with true CDC,
   just on the pipeline's cadence rather than instantly.

**Remaining limitation: latency, not accuracy.** A delete is caught the
next time `reconcile_all` runs, not the instant it happens in MySQL —
acceptable for a business without a stakeholder need for sub-cycle
freshness. If that need appears, the complete fix is binlog-based CDC
(AWS DMS) reading deletes as they happen; it would only change what
writes to S3, not anything downstream, and would let `reconcile.py`
be retired.

## 5. Snowflake-side reliability tooling (`snowflake_ops/`)

- **`backfill.py`** — force-reload one table from its S3 stage
  (`TRUNCATE` + `COPY INTO ... FORCE = TRUE`), used to recover from a
  bad initial load.
- **`dedupe.py` / `dedupe_all.py`** — collapses raw tables to the latest
  version per primary key (`ROW_NUMBER() OVER (PARTITION BY id ORDER BY
  _loaded_at DESC)`), needed because updates land as new rows in Bronze,
  not in-place overwrites. Run automatically for `payments` after every
  extraction, since its lookback strategy re-uploads overlapping data
  by design.
- **`reconcile.py` / `reconcile_all.py`** — the delete-detection safety
  net described above (§4). Marks orphaned rows `is_deleted = TRUE`
  rather than deleting them, so Bronze retains full history of
  everything that ever existed in production, while Silver/Gold only
  surface current, live data.

## 6. Transformation (dbt)

Separate project (`dbt_rentease_warehouse/`), connected via the
`TRANSFORMER` role.

- **Staging models** (`stg_mysql__*`) — rename/cast columns, apply the
  same `QUALIFY ROW_NUMBER() ... = 1` dedup logic as `dedupe.py` (at
  query time, not by mutating Bronze), and drop `password_hash`
  entirely — it never leaves this layer.
- **Marts** — dimensions (`dim_date`, `dim_users`, `dim_branches`,
  `dim_items`) and facts (`fct_bookings`, `fct_payments`,
  `fct_booking_status_events`, `fct_audit_events`), plus two persisted
  reports (`rpt_customer_rfm`, `rpt_customer_cohort_retention`) that
  were expensive enough to justify materializing rather than
  recomputing per query.
- Tests: `unique`/`not_null` on primary keys, `not_null` on key foreign
  keys, source freshness checks.

## 7. PII handling

- `password_hash` — dropped at the staging boundary, never reaches
  Silver or Gold.
- `dim_users.email` / `dim_users.phone` — Dynamic Data Masking policies;
  fully visible only to `PII_ANALYST`/`TRANSFORMER`, masked for
  everyone else.

## 8. Orchestration (Airflow)

DAG: `rentease_pipeline`, five tasks in sequence:

```
extract_from_rds → dedupe_payments → reconcile_deletes → wait_for_snowpipe → dbt_build
```

- `extract_from_rds` — runs `extract.run_all` (all 10 tables, incremental)
- `dedupe_payments` — cleans up `payments`' lookback-window duplicates
- `reconcile_deletes` — runs `snowflake_ops.reconcile_all`, soft-deleting
  any row that's disappeared from MySQL since the last cycle
- `wait_for_snowpipe` — polls `SYSTEM$PIPE_STATUS()` on all 10 pipes
  until `pendingFileCount = 0` for every one, so `dbt_build` never runs
  against partially-loaded Bronze tables
- `dbt_build` — rebuilds Silver + Gold and runs all tests

This closes the race condition between an asynchronous Snowpipe load
and a synchronous dbt run — without the wait step, dbt could silently
build that cycle's marts from stale raw data.

## 9. Deployment

Extraction (`extract/`, `snowflake_ops/`) runs on the same EC2 instance
that hosts the RentEase application — this puts it inside the RDS
security group already, avoiding any additional network configuration,
and keeps read-only credentials scoped to a dedicated MySQL user
(`warehouse_reader`) separate from the app's own DB user.
