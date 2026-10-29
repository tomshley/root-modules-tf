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

"""Exercise the dependency packager in clean temporary directories."""

from __future__ import annotations

import io
import json
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

from compatibility.candidate_copy import extract_safe

ROOT = Path(__file__).resolve().parents[2]
PACKAGER = ROOT / "tools" / "module-package" / "package_module.py"
SOURCE_RE = re.compile(r'(?m)^\s*source\s*=\s*"([^"]+)"')
SHIM_CLOSURES = {
    "aws-eks-metrics-server": {"k8s-metrics-server"},
    "aws-eks-grafana-alloy": {"k8s-grafana-alloy"},
    "gcp-gke-metrics-server": {"k8s-metrics-server"},
    "gcp-gke-grafana-alloy": {"k8s-grafana-alloy"},
    "gcp-gke-keycloak": {"gcp-keycloak", "k8s-keycloak"},
    "gcp-gke-secure-gcs": {"gcp-secure-gcs"},
    "gcp-gke-karpenter-controller": {"gcp-karpenter-controller", "gcp-karpenter-crds", "gcp-karpenter-controller-release"},
    "gcp-karpenter-controller": {"gcp-karpenter-crds", "gcp-karpenter-controller-release"},
}


def build(module: str, output: Path, manifest: Path) -> None:
    result = subprocess.run(
        ["python3", str(PACKAGER), "--root", str(ROOT), "--module", module, "--output", str(output), "--manifest", str(manifest)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())


def expect_packaging_failure(root: Path, module: str, work: Path, reason: str, diagnostic: str) -> None:
    result = subprocess.run(
        ["python3", str(PACKAGER), "--root", str(root), "--module", module, "--output", str(work / "bad.tgz"), "--manifest", str(work / "bad.json")],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    actual = result.stdout + result.stderr
    if result.returncode == 0:
        raise SystemExit(f"packager accepted {reason}")
    if diagnostic not in actual:
        raise SystemExit(f"packager failed for the wrong reason: {reason}: expected {diagnostic}\n{actual}")
    print(f"PASS package-negative {reason}: {diagnostic}")


def check_archive_safety(work: Path) -> None:
    content = b"package fixture\x00\n"
    for label, member_name, member_type, expected in [
        ("parent-path", "../escape", tarfile.REGTYPE, "candidate package path escapes extraction root"),
        ("absolute-path", str(work / "escape"), tarfile.REGTYPE, "candidate package path escapes extraction root"),
        ("symbolic-link", "alias", tarfile.SYMTYPE, "unsupported candidate package member"),
        ("hard-link", "alias", tarfile.LNKTYPE, "unsupported candidate package member"),
        ("special-member", "pipe", tarfile.FIFOTYPE, "unsupported candidate package member"),
    ]:
        archive_path = work / f"{label}.tgz"
        destination = work / f"{label}-extracted"
        with tarfile.open(archive_path, "w:gz") as archive:
            regular = tarfile.TarInfo("target")
            regular.size = len(content)
            archive.addfile(regular, io.BytesIO(content))
            member = tarfile.TarInfo(member_name)
            member.type = member_type
            member.linkname = "target" if member_type in {tarfile.SYMTYPE, tarfile.LNKTYPE} else ""
            member.size = len(content) if member_type == tarfile.REGTYPE else 0
            archive.addfile(member, io.BytesIO(content) if member.isfile() else None)
        try:
            extract_safe(archive_path, destination)
        except ValueError as error:
            if expected not in str(error) or destination.exists():
                raise SystemExit(f"archive rejected for the wrong reason or wrote before refusal: {label}: {error}")
        else:
            raise SystemExit(f"package extractor accepted {label}")
        print(f"PASS archive-negative {label}: {expected}")
    valid_archive = work / "regular-files.tgz"
    with tarfile.open(valid_archive, "w:gz") as archive:
        member = tarfile.TarInfo("nested/tool")
        member.mode = 0o755
        member.size = len(content)
        archive.addfile(member, io.BytesIO(content))
    destination = work / "regular-files"
    extract_safe(valid_archive, destination)
    result = destination / "nested/tool"
    if result.read_bytes() != content or result.stat().st_mode & 0o777 != 0o755:
        raise SystemExit("regular package content or executable mode changed")
    print("PASS archive-regular-files")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="root-modules-package-check-") as temporary:
        work = Path(temporary)
        check_archive_safety(work)
        pure_archive = work / "postgres-binding.tgz"
        pure_manifest = work / "postgres-binding.json"
        build("terraform/modules/postgres-binding", pure_archive, pure_manifest)
        with tarfile.open(pure_archive, "r:gz") as archive:
            names = archive.getnames()
            if not names or any(name.startswith("../") for name in names):
                raise SystemExit("package contains an escaping archive path")
        extract_safe(pure_archive, work / "pure")
        pure_init = subprocess.run(
            ["tofu", "init", "-backend=false", "-input=false", "-no-color"],
            cwd=work / "pure",
            text=True,
            capture_output=True,
            check=False,
        )
        if pure_init.returncode != 0:
            raise SystemExit(pure_init.stdout + pure_init.stderr)

        nested_archive = work / "aws-keycloak.tgz"
        nested_manifest = work / "aws-keycloak.json"
        build("terraform/modules/aws-keycloak", nested_archive, nested_manifest)
        manifest = json.loads(nested_manifest.read_text())
        if len(manifest["modules"]) < 2:
            raise SystemExit("dependency closure did not include the local Kubernetes module")
        nested_root = work / "nested"
        extract_safe(nested_archive, nested_root)
        nested_init = subprocess.run(
            ["tofu", "init", "-backend=false", "-input=false", "-no-color"],
            cwd=nested_root,
            text=True,
            capture_output=True,
            check=False,
        )
        if nested_init.returncode != 0:
            raise SystemExit(nested_init.stdout + nested_init.stderr)
        for path in nested_root.rglob("*.tf"):
            for source in SOURCE_RE.findall(path.read_text()):
                if source.startswith("."):
                    if not source.startswith("./") and not source.startswith("../"):
                        raise SystemExit(f"packaged local source is not explicit: {path}: {source}")
                    resolved = (path.parent / source).resolve()
                    if nested_root.resolve() not in resolved.parents:
                        raise SystemExit(f"packaged local source escapes archive: {path}: {source}")

        aurora_archive = work / "aurora.tgz"
        aurora_manifest = work / "aurora.json"
        build("terraform/modules/aws-eks-aurora-cluster", aurora_archive, aurora_manifest)
        aurora = json.loads(aurora_manifest.read_text())
        if not any(item["source"].endswith("terraform/modules/postgres-workload-contract") for item in aurora["modules"]):
            raise SystemExit("dependency closure did not include the PostgreSQL workload contract")
        print(f"PASS package-build aurora-modules={len(aurora['modules'])}")

        aurora_root = work / "aurora"
        extract_safe(aurora_archive, aurora_root)
        transitive_archive = work / "aws-eks-keycloak.tgz"
        transitive_manifest = work / "aws-eks-keycloak.json"
        build("terraform/modules/aws-eks-keycloak", transitive_archive, transitive_manifest)
        transitive = json.loads(transitive_manifest.read_text())
        expected_sources = {
            "terraform/modules/aws-eks-keycloak",
            "terraform/modules/aws-keycloak",
            "terraform/modules/k8s-keycloak",
        }
        if {item["source"] for item in transitive["modules"]} != expected_sources:
            raise SystemExit("transitive package dependency closure differs")
        transitive_root = work / "transitive"
        extract_safe(transitive_archive, transitive_root)
        for label, directory in [("aurora", aurora_root), ("transitive-keycloak", transitive_root)]:
            initialized = subprocess.run(
                ["tofu", "init", "-backend=false", "-input=false", "-no-color"],
                cwd=directory,
                text=True,
                capture_output=True,
                check=False,
            )
            if initialized.returncode != 0:
                raise SystemExit(initialized.stdout + initialized.stderr)
            print(f"PASS package-install {label}")

        for shim, closure in SHIM_CLOSURES.items():
            shim_archive = work / f"{shim}.tgz"
            shim_manifest = work / f"{shim}.json"
            build(f"terraform/modules/{shim}", shim_archive, shim_manifest)
            shim_payload = json.loads(shim_manifest.read_text())
            expected = {f"terraform/modules/{name}" for name in {shim} | closure}
            if {item["source"] for item in shim_payload["modules"]} != expected:
                raise SystemExit(f"shim package dependency closure differs: {shim}")
            shim_root = work / shim
            extract_safe(shim_archive, shim_root)
            for command in (
                ["tofu", "init", "-backend=false", "-input=false", "-no-color"],
                ["tofu", "validate", "-no-color"],
            ):
                result = subprocess.run(command, cwd=shim_root, text=True, capture_output=True, check=False)
                if result.returncode != 0:
                    raise SystemExit(result.stdout + result.stderr)
            print(f"PASS package-install {shim}")

        negative_root = work / "negative-root"
        missing_entry = negative_root / "modules" / "entry"
        missing_entry.mkdir(parents=True)
        (missing_entry / "main.tf").write_text('module "missing" {\n  source = "../missing"\n}\n')
        expect_packaging_failure(negative_root, "modules/entry", work, "missing dependency", "local module directory does not exist")
        (missing_entry / "main.tf").write_text('module "outside" {\n  source = "../../../outside"\n}\n')
        expect_packaging_failure(negative_root, "modules/entry", work, "escaping dependency", "local source escapes repository")
        print(f"PASS package-check modules={len(manifest['modules'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
