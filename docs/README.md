# RentEase Analytics Warehouse

## Vision

To become the single source of truth for rental businesses — replacing
phone-and-WhatsApp booking chaos with a real-time, self-service platform
that makes renting as simple and reliable as buying online.

## Mission

RentEase eliminates double-bookings and manual coordination overhead by
giving customers instant visibility into item availability and a seamless
online booking-and-payment experience, while giving rental staff and
owners a single, centralized dashboard to manage inventory, bookings, and
payments — across branches, in real time.

## What this repo covers

The main RentEase application (API, admin, customer web app) lives in
`docs(Main-project)/`. This `docs/` folder covers the **analytics
warehouse** built on top of that application's production MySQL (RDS)
database — a separate system that lets the business analyze revenue,
demand, booking funnel health, and customer behavior without ever
querying production directly.

## Status: built and operating

The warehouse is fully built, following a medallion architecture
(Bronze → Silver → Gold) on Snowflake:

- **Bronze** (`RENTEASE_RAW`) — 10 tables, mirroring the MySQL schema,
  loaded via Snowpipe auto-ingest from S3
- **Silver** (`RENTEASE_ANALYTICS.STAGING`) — 10 dbt models: renamed,
  typed, deduplicated, with PII (password hashes) dropped
- **Gold** (`RENTEASE_ANALYTICS.MARTS`) — a star schema (4 dimensions,
  4 core facts) plus 2 reporting marts (RFM segmentation, cohort
  retention), with masking policies on customer email/phone

Extraction runs as a standalone Python project (`extract/` +
`snowflake_ops/`), scheduled via Airflow, which pulls incremental
changes from RDS, uploads them to S3, and lets Snowpipe pick them up
automatically.

See `warehouse_architecture.md` for the full technical design and
`rentease_analytics_warehouse.sql` for the analytical queries rewritten
against the finished Gold layer.

## Repo/folder map

| Folder/File | What it is |
|---|---|
| `docs(Main-project)/` | Main RentEase app docs (schema, architecture, CI/CD) — unrelated to the warehouse |
| `docs/warehouse_architecture.md` | Full technical design of the warehouse: layers, RBAC, ingestion, orchestration |
| `docs/rentease_analytics_mysql.sql` | The original analytical queries, as run directly against production MySQL (pre-warehouse) |
| `docs/rentease_analytics_warehouse.sql` | The same queries, rewritten to run against the Gold-layer marts |
| `extract/` | Python extraction pipeline: RDS → S3 (incremental, watermark-based) |
| `snowflake_ops/` | Snowflake-side maintenance tools: backfill, dedupe |
| (separate project) `dbt_rentease_warehouse/` | dbt project building Silver and Gold |
