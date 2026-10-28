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

"""Require every contract case to be executed by the offline runner."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = ROOT / "terraform" / "contracts" / "scenarios" / "contract-cases.json"
RUNNER = ROOT / "terraform" / "tests" / "contract_cases.py"


def main() -> int:
    payload = json.loads(CASES.read_text())
    expected = {case["name"] for case in payload["cases"]}
    result = subprocess.run([sys.executable, str(RUNNER)], cwd=ROOT, text=True, capture_output=True, check=False)
    executed = {
        line.split()[1]
        for line in result.stdout.splitlines()
        if line.startswith("PASS ") and " (" in line and len(line.split()) >= 2
    }
    if result.returncode != 0 or executed != expected:
        print(result.stdout)
        print(result.stderr)
        print(f"expected={sorted(expected)}")
        print(f"executed={sorted(executed)}")
        return 1
    broken_env = os.environ.copy()
    broken_env["TOFU"] = "command-that-does-not-exist"
    broken = subprocess.run([sys.executable, str(RUNNER)], cwd=ROOT, env=broken_env, text=True, capture_output=True, check=False)
    if broken.returncode == 0:
        print("unrelated initialization failure was incorrectly accepted")
        return 1
    print("PASS negative unrelated-initialization-failure")
    print(f"PASS coverage expected={len(expected)} discovered={len(executed)} executed={len(executed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
