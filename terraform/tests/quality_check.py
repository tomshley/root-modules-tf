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

"""Reject private or planning-only material in public contract sources."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN_ROOTS = [
    ROOT / "terraform" / "contracts",
    ROOT / "terraform" / "tests" / "compatibility",
    ROOT / "terraform" / "tests" / "adapter_contract_check.py",
    ROOT / "tools" / "module-package",
    *(ROOT / "terraform" / "modules" / name for name in [
        "postgres-workload-contract",
        "postgres-tenancy-contract",
        "redis-service-contract",
        "node-provisioning-contract",
        "karpenter-controller-contract",
        "postgres-binding",
    ]),
]
FORBIDDEN = [
    re.compile(r"/Users/|/home/"),
    re.compile(r"(?i)customer|private[-_ ]ticket|internal[-_ ]project"),
    re.compile(r"\b(?:phase|step|part)(?:\s|-)(?:[0-9]+|[A-Z])\b"),
]


def main() -> int:
    failures: list[str] = []
    for root in SCAN_ROOTS:
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix not in {".tf", ".json", ".py", ".yaml", ".yml", ".md"}:
                continue
            text = path.read_text(errors="replace")
            for pattern in FORBIDDEN:
                if pattern.search(text):
                    failures.append(f"{path.relative_to(ROOT)} matches {pattern.pattern}")
    if failures:
        print("\n".join(failures))
        return 1
    print("PASS public-source-boundary")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
