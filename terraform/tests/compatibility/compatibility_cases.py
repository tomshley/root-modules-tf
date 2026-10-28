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

"""Test candidate source resolution without touching a real consumer checkout."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("candidate_copy.py")


def invoke(command: list[str], diagnostic: str | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if diagnostic is None:
        if result.returncode != 0:
            raise SystemExit(result.stdout + result.stderr)
    elif result.returncode == 0 or diagnostic not in result.stdout + result.stderr:
        raise SystemExit(f"expected rejection {diagnostic}:\n{result.stdout}\n{result.stderr}")
    return result


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="root-modules-compatibility-") as temporary:
        work = Path(temporary)
        consumer = work / "consumer"
        candidate = work / "candidate"
        output = work / "isolated copy"
        consumer.mkdir()
        for name in ("aws-example", "aws-other", "aws-independent"):
            module = candidate / "terraform" / "modules" / name
            module.mkdir(parents=True)
            (module / "provider.tf").write_text('terraform { required_version = ">= 1.9" }\n')
            (module / "outputs.tf").write_text(f'output "identity" {{ value = "{name}" }}\n')
        expected_modules = {
            "environments/test": {"example": "aws-example", "other": "aws-other"},
            "environments/independent": {"independent": "aws-independent"},
        }
        module_map = work / "module-map.json"
        module_map.write_text(json.dumps(expected_modules))
        for relative, mapping in expected_modules.items():
            stack = consumer / relative
            stack.mkdir(parents=True)
            (stack / "main.tf").write_text("\n".join(
                f'module "{key}" {{\n  source = "git::https://github.com/tomshley/root-modules-tf.git//terraform/modules/{name}?ref=v0.0.0"\n}}\n'
                for key, name in mapping.items()
            ))
        stack = consumer / "environments/test"
        original_config = (stack / "main.tf").read_bytes()
        untouched = consumer / "README.md"
        untouched.write_text("unchanged\n")
        (stack / ".tfstate.plan").write_text("private plan\n")
        (stack / ".tfstate.plan.json").write_text("private plan json\n")
        secure = consumer / ".secure_files"
        secure.mkdir()
        (secure / "secret.env").write_text("SYNTHETIC\n")
        manifest = work / "manifest.json"
        invoke([
            sys.executable, str(SCRIPT), "--consumer", str(consumer), "--candidate", str(candidate),
            "--output", str(output), "--manifest", str(manifest), "--module-map", str(module_map),
            "--init-dir", "environments/test", "--init-dir", "environments/independent",
        ])
        payload = json.loads(manifest.read_text())
        if payload["expected_modules"] != expected_modules or len(payload["initialized"]) != 2:
            raise SystemExit("candidate manifest does not preserve the independently supplied stack mapping")
        if untouched.read_text() != "unchanged\n" or (stack / "main.tf").read_bytes() != original_config:
            raise SystemExit("candidate-copy mutated the original consumer")
        if (output / "environments/test/.tfstate.plan").exists() or (output / "environments/test/.tfstate.plan.json").exists() or (output / ".secure_files").exists():
            raise SystemExit("private state or secure material was copied")
        command = [
            sys.executable, str(SCRIPT.with_name("installed_candidate_check.py")),
            "--consumer", str(output), "--candidate", str(candidate), "--manifest", str(manifest),
            "--init-dir", "environments/test",
        ]
        invoke(command)
        print("PASS compatibility-cases per-stack-selection")
        metadata = output / "environments/test/.terraform/modules/modules.json"
        original_metadata = metadata.read_bytes()
        entries = json.loads(original_metadata)
        package = payload["candidate_packages"]["aws-example"]
        other = payload["candidate_packages"]["aws-other"]
        for label, source in [
            ("encoded-file-url", Path(package["root"]).as_uri()),
            ("localhost-file-url", Path(package["root"]).as_uri().replace("file://", "file://localhost", 1)),
            ("absolute-local-path", package["root"]),
        ]:
            selected = copy.deepcopy(entries)
            for item in selected["Modules"]:
                if item["Key"] == "example":
                    item["Source"] = source
            metadata.write_text(json.dumps(selected))
            invoke(command)
            metadata.write_bytes(original_metadata)
            print(f"PASS compatibility-cases {label}")
        baseline = work / "baseline"
        baseline.mkdir()
        (baseline / "outputs.tf").write_text('output "identity" { value = "baseline" }\n')
        for label, diagnostic in [
            ("wrong-candidate-module", "expected candidate module mapping mismatch: example"),
            ("partial-baseline", "expected candidate module mapping mismatch: other"),
            ("missing-module", "expected candidate module is missing: other"),
            ("unexpected-candidate", "candidate module is absent from expected mapping: unexpected"),
            ("escaped-child", "candidate child module escaped its package: example.child"),
            ("escaped-file-child", "candidate child module escaped its package: example.child"),
            ("remote-file-host", "expected candidate module mapping mismatch: example"),
            ("file-url-query", "expected candidate module mapping mismatch: example"),
        ]:
            mutated = copy.deepcopy(entries)
            if label == "missing-module":
                mutated["Modules"] = [item for item in mutated["Modules"] if item["Key"] != "other"]
            elif label in {"unexpected-candidate", "escaped-child", "escaped-file-child"}:
                directory = package["root"] if label == "unexpected-candidate" else str(baseline)
                key = "unexpected" if label == "unexpected-candidate" else "example.child"
                source = Path(directory).as_uri() if label == "escaped-file-child" else directory
                mutated["Modules"].append({"Key": key, "Dir": directory, "Source": source})
            elif label in {"remote-file-host", "file-url-query"}:
                source = Path(package["root"]).as_uri()
                source = source.replace("file://", "file://remote.invalid", 1) if label == "remote-file-host" else source + "?ref=unexpected"
                for item in mutated["Modules"]:
                    if item["Key"] == "example":
                        item["Source"] = source
            else:
                key = "example" if label == "wrong-candidate-module" else "other"
                directory = other["root"] if label == "wrong-candidate-module" else str(baseline)
                for item in mutated["Modules"]:
                    if item["Key"] == key:
                        item["Dir"] = directory
                        item["Source"] = directory
            metadata.write_text(json.dumps(mutated))
            invoke(command, diagnostic)
            metadata.write_bytes(original_metadata)
            print(f"PASS compatibility-negative {label}")
        for label, path, diagnostic in [
            ("changed-package", Path(package["root"]) / "provider.tf", "candidate package tree digest mismatch"),
            ("changed-archive", Path(package["archive"]), "candidate archive digest mismatch"),
            ("changed-assembly-manifest", Path(package["manifest"]), "candidate package manifest digest mismatch"),
            ("changed-selected-source", candidate / "terraform/modules/aws-example/provider.tf", "candidate source digest mismatch"),
            ("changed-caller", output / "environments/test/main.tf", "candidate consumer source digest mismatch"),
        ]:
            original = path.read_bytes()
            path.write_bytes(original + b"\n")
            invoke(command, diagnostic)
            path.write_bytes(original)
            print(f"PASS compatibility-negative {label}")
        wrong_candidate = work / "wrong-candidate"
        wrong_candidate.mkdir()
        for name in payload["candidate_packages"]:
            directory = wrong_candidate / "terraform/modules" / name
            directory.mkdir(parents=True)
            (directory / "provider.tf").write_text('terraform { required_version = ">= 1.9" }\n')
        wrong_command = command.copy()
        wrong_command[wrong_command.index("--candidate") + 1] = str(wrong_candidate)
        invoke(wrong_command, "candidate source digest mismatch")
        print("PASS compatibility-negative wrong-selected-source")
        saved_manifest = manifest.read_bytes()
        missing_map = json.loads(saved_manifest)
        missing_map.pop("expected_modules")
        manifest.write_text(json.dumps(missing_map))
        invoke(command, "expected per-stack module map is missing")
        manifest.write_bytes(saved_manifest)
        print("PASS compatibility-negative missing-expected-map")
        invoke(command)
        invoke(command[:-2] + ["--init-dir", "environments/independent"])
        print("PASS compatibility-cases restored-installed-content")
        forbidden_output = consumer / "forbidden-output"
        invoke([
            sys.executable, str(SCRIPT), "--consumer", str(consumer), "--candidate", str(candidate),
            "--output", str(forbidden_output), "--manifest", str(consumer / "forbidden.json"),
            "--module-map", str(module_map),
        ], "protected consumer")
        print("PASS compatibility-cases isolated-source-rewrite")
        print("PASS compatibility-negative protected-destination")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
