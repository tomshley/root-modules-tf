#!/usr/bin/env python3
"""Upload an already-assembled Terraform module archive to GitLab."""

from __future__ import annotations

import argparse
import os
import urllib.request
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--url", required=True)
    args = parser.parse_args()
    token = os.environ.get("CI_JOB_TOKEN")
    if not token:
        raise SystemExit("CI_JOB_TOKEN is required")
    request = urllib.request.Request(
        args.url,
        data=args.archive.read_bytes(),
        headers={"JOB-TOKEN": token, "Content-Type": "application/gzip"},
        method="PUT",
    )
    with urllib.request.urlopen(request) as response:
        if response.status < 200 or response.status >= 300:
            raise SystemExit(f"module upload returned HTTP {response.status}")
    print(f"PASS module-upload archive={args.archive.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
