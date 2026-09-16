#!/usr/bin/env python3
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
