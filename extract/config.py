TABLES = {
    "categories": {"cursor": "updated_at", "lookback_days": None},
    "branches": {"cursor": "updated_at", "lookback_days": None},
    "users": {"cursor": "updated_at", "lookback_days": None},
    "item_catalog": {"cursor": "updated_at", "lookback_days": None},
    # append-only, no updates possible
    "item_photos": {"cursor": "created_at", "lookback_days": None},
    "items": {"cursor": "updated_at", "lookback_days": None},
    "bookings": {"cursor": "updated_at", "lookback_days": None},
    # append-only
    "booking_status_history": {"cursor": "changed_at", "lookback_days": None},
    # no updated_at — mutates in place, use lookback
    "payments": {"cursor": "created_at", "lookback_days": 30},
    # append-only
    "audit_logs": {"cursor": "created_at", "lookback_days": None},
}

PRIMARY_KEYS = {t: "id" for t in TABLES}
