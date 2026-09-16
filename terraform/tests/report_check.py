#!/usr/bin/env python3
"""Validate the optional local report without accepting an empty receipt."""

from __future__ import annotations

import json
import os
from pathlib import Path

report = os.environ.get("REPORT_JSON")
if not report:
    print("PASS report-check no report requested")
    raise SystemExit(0)

path = Path(report)
payload = json.loads(path.read_text())
required = {"schema_revision", "run_id", "scope", "sources", "coverage", "conclusion"}
missing = sorted(required - payload.keys())
if missing:
    raise SystemExit(f"report missing fields: {', '.join(missing)}")
if payload["conclusion"] not in {"pass", "fail", "blocked"}:
    raise SystemExit("report conclusion is invalid")
print(f"PASS report-check run_id={payload['run_id']} conclusion={payload['conclusion']}")
