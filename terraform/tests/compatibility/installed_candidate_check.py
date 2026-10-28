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

"""Verify candidate module contents after a consumer stack Makefile initialized them."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import url2pathname

from candidate_copy import sha256, source_inventory, tree_sha256


def local_source(source: str, stack: Path) -> Path | None:
    if source.startswith("file:"):
        url = urlsplit(source)
        if url.netloc not in {"", "localhost"} or url.query or url.fragment:
            return None
        path = Path(url2pathname(url.path))
        return path.resolve() if path.is_absolute() else None
    if not source.startswith((".", "/")):
        return None
    path = Path(source)
    return (stack / path).resolve() if not path.is_absolute() else path.resolve()


def verify_packages(candidate: Path, payload: dict) -> dict[str, Path]:
    if payload.get("schema_revision") != "candidate-selection-v2":
        raise ValueError("candidate selection requires recorded source digests and an expected module map")
    packages = payload.get("candidate_packages", {})
    if not packages:
        raise ValueError("candidate manifest has no assembled candidate packages")
    roots = {}
    for name, package in packages.items():
        sources = package.get("source_hashes", {})
        if not sources:
            raise ValueError(f"candidate source inventory is missing: {name}")
        for relative, expected in sources.items():
            directory = (candidate / relative).resolve()
            if candidate not in directory.parents or not directory.is_dir():
                raise ValueError(f"candidate source directory is invalid: {name}")
            if source_inventory(directory) != expected:
                raise ValueError(f"candidate source digest mismatch: {name}")
        archive = Path(package["archive"])
        manifest = Path(package["manifest"])
        root = Path(package["root"]).resolve()
        if not archive.is_file() or sha256(archive) != package["archive_sha256"]:
            raise ValueError(f"candidate archive digest mismatch: {name}")
        if not manifest.is_file() or sha256(manifest) != package["manifest_sha256"]:
            raise ValueError(f"candidate package manifest digest mismatch: {name}")
        if not root.is_dir() or tree_sha256(root) != package["tree_sha256"]:
            raise ValueError(f"candidate package tree digest mismatch: {name}")
        assembly = json.loads(manifest.read_text())
        expected_files = {record["path"]: record["sha256"] for record in assembly["files"]}
        if len(expected_files) != len(assembly["files"]):
            raise ValueError(f"candidate package has duplicate file records: {name}")
        for relative, expected in expected_files.items():
            path = (root / relative).resolve()
            if root not in path.parents or not path.is_file() or sha256(path) != expected:
                raise ValueError(f"candidate package file digest mismatch: {name}")
        roots[name] = root
    return roots


def verify_installed(consumer: Path, candidate: Path, payload: dict, init_dirs: list[str]) -> list[dict]:
    roots = verify_packages(candidate, payload)
    expected_stacks = payload.get("expected_modules", {})
    if not expected_stacks:
        raise ValueError("expected per-stack module map is missing")
    for record in payload.get("rewritten_files", []):
        path = (consumer / record["path"]).resolve()
        if consumer not in path.parents or not path.is_file() or sha256(path) != record["candidate_sha256"]:
            raise ValueError("candidate consumer source digest mismatch")
    receipts = []
    for relative in init_dirs:
        expected = expected_stacks.get(relative)
        if not isinstance(expected, dict) or not expected:
            raise ValueError(f"expected module map is missing for stack: {relative}")
        stack = (consumer / relative).resolve()
        if consumer not in stack.parents:
            raise ValueError(f"init directory escapes isolated consumer: {relative}")
        metadata = stack / ".terraform" / "modules" / "modules.json"
        if not metadata.is_file():
            raise ValueError(f"stack Makefile did not leave module metadata: {relative}")
        entries = json.loads(metadata.read_text()).get("Modules", [])
        installed = {}
        for entry in entries:
            key = entry["Key"]
            if key in installed:
                raise ValueError(f"duplicate installed module key: {key}")
            directory = Path(entry["Dir"])
            directory = (stack / directory).resolve() if not directory.is_absolute() else directory.resolve()
            if not directory.is_dir():
                raise ValueError(f"installed module directory is missing: {key}")
            installed[key] = {"source": entry.get("Source", ""), "dir": str(directory), "sha256": tree_sha256(directory)}
        for key, name in expected.items():
            if name not in roots:
                raise ValueError(f"expected module names an unselected candidate package: {key}")
            if key not in installed:
                raise ValueError(f"expected candidate module is missing: {key}")
            root = roots[name]
            item = installed[key]
            source = local_source(item["source"], stack)
            if Path(item["dir"]) != root or source != root or item["sha256"] != payload["candidate_packages"][name]["tree_sha256"]:
                raise ValueError(f"expected candidate module mapping mismatch: {key}")
        for key, item in installed.items():
            directory = Path(item["dir"])
            containing = [root for root in roots.values() if root == directory or root in directory.parents]
            owners = [parent for parent in expected if key == parent or key.startswith(parent + ".")]
            if containing:
                if not owners:
                    raise ValueError(f"candidate module is absent from expected mapping: {key}")
                owner = max(owners, key=len)
                root = roots[expected[owner]]
                if directory != root and root not in directory.parents:
                    raise ValueError(f"candidate child module mapping mismatch: {key}")
            elif owners and item["source"].startswith((".", "/", "file:")):
                raise ValueError(f"candidate child module escaped its package: {key}")
        receipts.append({"stack": relative, "modules_metadata_sha256": sha256(metadata), "expected_modules": expected, "installed_modules": installed})
    return receipts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--init-dir", action="append", required=True)
    args = parser.parse_args()
    payload = json.loads(args.manifest.read_text())
    try:
        receipts = verify_installed(args.consumer.resolve(), args.candidate.resolve(), payload, args.init_dir)
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
    payload["initialized"] = receipts
    args.manifest.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(f"PASS installed-candidate-content stacks={len(receipts)} modules={len(payload['candidate_packages'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
