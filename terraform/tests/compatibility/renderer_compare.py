#!/usr/bin/env python3
"""Compare independent baseline and candidate operator toolboxes."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file() and (path.name == "render-bundle.sh" or "lib" in path.relative_to(root).parts):
            digest.update(str(path.relative_to(root)).encode())
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def run_list(toolbox: Path) -> str:
    result = subprocess.run(["bash", str(toolbox / "render-bundle.sh"), "--list"], cwd=toolbox, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def syntax_check(toolbox: Path) -> None:
    for script in toolbox.rglob("*.sh"):
        result = subprocess.run(["bash", "-n", str(script)], text=True, capture_output=True, check=False)
        if result.returncode != 0:
            raise SystemExit(result.stdout + result.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    baseline = args.baseline.resolve()
    candidate = args.candidate.resolve()
    if baseline == candidate:
        raise SystemExit("baseline and candidate toolboxes must be independent paths")
    for toolbox in (baseline, candidate):
        if not (toolbox / "render-bundle.sh").is_file():
            raise SystemExit(f"render-bundle.sh is missing: {toolbox}")
        syntax_check(toolbox)
    baseline_hash = tree_hash(baseline)
    candidate_hash = tree_hash(candidate)
    baseline_list = run_list(baseline)
    candidate_list = run_list(candidate)
    if baseline_hash != candidate_hash:
        raise SystemExit("renderer implementation or helper bytes differ; focused synthetic output evidence is required before acceptance")
    if baseline_list != candidate_list:
        raise SystemExit("renderer catalog differs between baseline and candidate")
    print(f"PASS renderer-compare tree_sha256={candidate_hash}")
    print("PASS renderer-compare catalog")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
