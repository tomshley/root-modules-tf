#!/usr/bin/env python3
"""Check the operator bundle catalog and prove a catalog mutation is detected."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLBOX = ROOT / "toolbox" / "operator-tools"
RENDERER = "render-bundle.sh"


def listing(toolbox: Path) -> str:
    result = subprocess.run(
        ["bash", str(toolbox / RENDERER), "--list"],
        cwd=toolbox,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="root-modules-renderer-") as temporary:
        work = Path(temporary)
        baseline = work / "baseline"
        candidate = work / "candidate"
        shutil.copytree(TOOLBOX, baseline)
        shutil.copytree(TOOLBOX, candidate)
        for toolbox in (baseline, candidate):
            syntax = subprocess.run(["bash", "-n", str(toolbox / RENDERER)], text=True, capture_output=True, check=False)
            if syntax.returncode != 0:
                raise SystemExit(syntax.stdout + syntax.stderr)
        expected = listing(baseline)
        if listing(candidate) != expected:
            raise SystemExit("unchanged operator bundles differ")
        comparator = Path(__file__).with_name("renderer_compare.py")
        unchanged = subprocess.run(
            ["python3", str(comparator), "--baseline", str(baseline), "--candidate", str(candidate)],
            text=True,
            capture_output=True,
            check=False,
        )
        if unchanged.returncode != 0:
            raise SystemExit(unchanged.stdout + unchanged.stderr)
        candidate_script = candidate / RENDERER
        candidate_script.write_text(candidate_script.read_text().replace('"keycloak:aws-eks-keycloak:', '"keycloak-mutated:aws-eks-keycloak:', 1))
        mutated = subprocess.run(
            ["python3", str(comparator), "--baseline", str(baseline), "--candidate", str(candidate)],
            text=True,
            capture_output=True,
            check=False,
        )
        if mutated.returncode == 0 or "bytes differ" not in (mutated.stdout + mutated.stderr):
            raise SystemExit("operator renderer mutation was not rejected by the independent comparator")
        print("PASS renderer-cases independent-baseline-candidate")
        print("PASS renderer-negative catalog-mutation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
