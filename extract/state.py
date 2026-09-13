import json
import os

STATE_FILE = os.path.join(os.path.dirname(__file__), "..", "watermarks.json")


def load_watermarks() -> dict:
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def save_watermarks(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2, default=str)
