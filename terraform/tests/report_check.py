#!/usr/bin/env python3
# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
