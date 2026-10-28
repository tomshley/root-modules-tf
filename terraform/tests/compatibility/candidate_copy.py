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

"""Create an isolated consumer copy resolved to dependency-closed candidate packages."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import shutil
import subprocess
import tarfile
from pathlib import Path

SOURCE_RE = re.compile(
    r'(?m)^(?P<prefix>\s*source\s*=\s*")'
    r'(?P<address>git::https://github\.com/tomshley/root-modules-tf\.git//terraform/modules/'
    r'(?P<module>[a-z0-9-]+))(?P<query>\?ref=[^"\n]+)?(?P<suffix>")'
)
IGNORED_NAMES = {".git", ".terraform", ".terraform.lock.hcl", ".secure_files", ".tomshley-cicd-tmp", ".DS_Store"}
PACKAGE_TOOL = Path(__file__).resolve().parents[3] / "tools" / "module-package" / "package_module.py"


def ignored_name(name: str) -> bool:
    if name == "terraform.tfvars":
        return False
    return name in IGNORED_NAMES or any(
        fnmatch.fnmatch(name, pattern)
        for pattern in ("*.tfstate", "*.tfstate.*", ".tfstate.plan*", "*.tfplan", "*.tfplan.*", "*.tfvars", ".env", ".env.*")
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(ignored_name(part) for part in path.relative_to(root).parts):
            continue
        digest.update(str(path.relative_to(root)).encode())
        digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def copy_filter(directory: str, names: list[str]) -> set[str]:
    return {name for name in names if ignored_name(name) or (Path(directory) / name).is_symlink()}


def source_inventory(root: Path) -> dict[str, str]:
    inventory = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and not any(ignored_name(part) for part in path.relative_to(root).parts):
            inventory[str(path.relative_to(root))] = sha256(path)
    return inventory


def extract_safe(archive: Path, destination: Path) -> None:
    destination = destination.resolve()
    with tarfile.open(archive, "r:gz") as stream:
        files = []
        for member in stream.getmembers():
            path = Path(member.name)
            target = (destination / path).resolve()
            if path.is_absolute() or ".." in path.parts or destination not in target.parents:
                raise ValueError(f"candidate package path escapes extraction root: {member.name}")
            if not member.isfile():
                raise ValueError(f"unsupported candidate package member: {member.name}")
            files.append((member, target))
        for member, target in files:
            target.parent.mkdir(parents=True, exist_ok=True)
            with stream.extractfile(member) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(member.mode & 0o777)


def build_candidate_package(candidate: Path, module: str, package_root: Path) -> dict[str, object]:
    package_root.mkdir(parents=True, exist_ok=True)
    archive = package_root / f"{module}.tgz"
    manifest = package_root / f"{module}.json"
    extracted = package_root / module
    result = subprocess.run(
        [
            "python3",
            str(PACKAGE_TOOL),
            "--root",
            str(candidate),
            "--module",
            f"terraform/modules/{module}",
            "--output",
            str(archive),
            "--manifest",
            str(manifest),
        ],
        cwd=candidate,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(result.stdout + result.stderr)
    extract_safe(archive, extracted)
    package_manifest = json.loads(manifest.read_text())
    return {
        "module": module,
        "root": str(extracted),
        "archive": str(archive),
        "archive_sha256": package_manifest["archive_sha256"],
        "tree_sha256": tree_sha256(extracted),
        "manifest": str(manifest),
        "manifest_sha256": sha256(manifest),
        "source_hashes": {
            entry["source"]: source_inventory(candidate / entry["source"])
            for entry in package_manifest["modules"]
        },
    }


def assert_outside_protected(path: Path, protected: Path, label: str) -> None:
    if path == protected or protected in path.parents:
        raise ValueError(f"{label} would mutate the protected consumer: {path}")


def initialize(stack: Path, tofu: str) -> None:
    result = subprocess.run(
        [tofu, "init", "-backend=false", "-input=false", "-no-color"],
        cwd=stack,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"candidate initialization failed in {stack}:\n{result.stdout}\n{result.stderr}")


def rewrite_consumer(consumer: Path, candidate: Path, output: Path, init_dirs: list[str], tofu: str, manifest: Path, expected_modules: dict[str, dict[str, str]]) -> dict[str, object]:
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    assert_outside_protected(output, consumer, "output")
    assert_outside_protected(manifest, consumer, "manifest")
    shutil.copytree(consumer, output, ignore=copy_filter)
    changed: list[dict[str, str]] = []
    packages: dict[str, dict[str, object]] = {}
    package_root = output / ".compat_candidate_packages"
    for path in sorted(output.rglob("*.tf")):
        original = path.read_text()
        original_hash = hashlib.sha256(original.encode()).hexdigest()

        def replacement(match: re.Match[str]) -> str:
            module = match.group("module")
            if module not in packages:
                packages[module] = build_candidate_package(candidate, module, package_root)
            return f'{match.group("prefix")}{Path(packages[module]["root"]).resolve()}{match.group("suffix")}'

        rewritten = SOURCE_RE.sub(replacement, original)
        if rewritten != original:
            path.write_text(rewritten)
            changed.append({"path": str(path.relative_to(output)), "original_sha256": original_hash, "candidate_sha256": sha256(path)})
    if not changed:
        raise ValueError("no root-modules-tf source pins were resolved to the candidate")
    if not expected_modules or any(not mapping for mapping in expected_modules.values()):
        raise ValueError("expected per-stack module map must be nonempty")
    if {name for mapping in expected_modules.values() for name in mapping.values()} != set(packages):
        raise ValueError("expected module map and selected candidate packages differ")
    payload = {
        "schema_revision": "candidate-selection-v2",
        "candidate_modules": sorted(packages),
        "candidate_packages": packages,
        "expected_modules": expected_modules,
        "rewritten_files": changed,
        "initialized": [],
        "protected_source_hashes": source_inventory(consumer),
    }
    for init_dir in init_dirs:
        stack = (output / init_dir).resolve()
        if output.resolve() not in stack.parents:
            raise ValueError(f"init directory escapes isolated output: {init_dir}")
        if init_dir not in expected_modules:
            raise ValueError(f"expected module map is missing for stack: {init_dir}")
        initialize(stack, tofu)
    if init_dirs:
        from installed_candidate_check import verify_installed

        payload["initialized"] = verify_installed(output, candidate, payload, init_dirs)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--module-map", type=Path, required=True)
    parser.add_argument("--init-dir", action="append", default=[])
    parser.add_argument("--tofu", default="tofu")
    args = parser.parse_args()
    expected_modules = json.loads(args.module_map.read_text())
    result = rewrite_consumer(args.consumer.resolve(), args.candidate.resolve(), args.output.resolve(), args.init_dir, args.tofu, args.manifest.resolve(), expected_modules)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"PASS candidate-copy modules={len(result['candidate_modules'])} files={len(result['rewritten_files'])} initialized={len(result['initialized'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
