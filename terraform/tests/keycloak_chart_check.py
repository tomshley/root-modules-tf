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

"""Render the pinned chart with planned values using the Helm provider."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


def resources(module: dict) -> list[dict]:
    return module.get("resources", []) + [
        resource for child in module.get("child_modules", []) for resource in resources(child)
    ]


def database_user_problems(manifest: str, user_key: str) -> list[str]:
    names = re.findall(r'(?m)^\s*- name: "?KEYCLOAK_DATABASE_USER"?\s*$', manifest)
    reference = (
        r'(?m)^\s*- name: "?KEYCLOAK_DATABASE_USER"?\s*\n'
        r'\s*valueFrom:\s*\n\s*secretKeyRef:\s*\n'
        r'\s*name: "?db-existing"?\s*\n'
        r'\s*key: "?' + re.escape(user_key) + r'"?\s*$'
    )
    if len(names) != 1 or len(re.findall(reference, manifest)) != 1:
        return [f"StatefulSet must contain exactly one KEYCLOAK_DATABASE_USER from db-existing/{user_key}"]
    return []


def chart_problems(
    tofu: str, work: Path, planned: dict, run, *,
    case: str, hostname: str | None, db_user_key: str | None = None,
) -> list[str]:
    release = next(resource["values"] for resource in resources(planned["root_module"]) if resource["type"] == "helm_release")
    if (release["repository"], release["chart"], release["version"]) != ("oci://registry-1.docker.io/bitnamicharts", "keycloak", "24.4.2"):
        return ["chart proof must use the pinned official Keycloak chart"]
    attributes = {key: release[key] for key in ["repository", "chart", "version", "name", "namespace", "values"]}
    attributes.update({"validate": False, "kube_version": "1.30.0", "show_only": ["templates/statefulset.yaml"]})
    fixture = 'data "helm_template" "hostname_proof" {\n'
    fixture += "\n".join(f"  {key} = {json.dumps(value)}" for key, value in attributes.items()) + "\n}\n"
    fixture += 'output "hostname_proof" { value = data.helm_template.hostname_proof.manifest }\n'
    (work / "chart-proof.tf").write_text(fixture)
    rendered = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=chart-proof.plan"], work)
    if rendered.returncode:
        return ["pinned chart rendering failed: " + rendered.stdout + rendered.stderr]
    shown = run([tofu, "show", "-json", "chart-proof.plan"], work)
    if shown.returncode:
        return ["could not inspect pinned chart rendering: " + shown.stderr]
    proof = json.loads(shown.stdout)["planned_values"]
    manifest = proof.get("outputs", {}).get("hostname_proof", {}).get("value")
    if manifest is None:
        return ["pinned chart must produce a known manifest at plan time"]
    if not re.search(r"(?m)^kind: StatefulSet$", manifest):
        return ["pinned chart did not render a StatefulSet"]
    if hostname is not None:
        if len(re.findall(r'(?m)^\s*- name: "?KC_HOSTNAME"?\s*\n\s*value: "?' + re.escape(hostname) + r'"?\s*$', manifest)) != 1:
            return [f"StatefulSet must contain exactly one KC_HOSTNAME={hostname}"]
    elif re.search(r'(?m)^\s*- name: "?KC_HOSTNAME"?\s*$', manifest):
        return ["StatefulSet must not contain KC_HOSTNAME without public_hostname"]
    if db_user_key is not None:
        problems = database_user_problems(manifest, db_user_key)
        if problems:
            return problems
    if os.environ.get("KEYCLOAK_RENDER_OUTPUT"):
        destination = Path(os.environ["KEYCLOAK_RENDER_OUTPUT"]) / case
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "values.json").write_text(json.dumps(release["values"]))
        (destination / "statefulset.yaml").write_text(manifest)
    if hostname is not None:
        print(f"PASS keycloak-chart-proof chart=24.4.2 StatefulSet KC_HOSTNAME={hostname}")
    if db_user_key is not None:
        print(f"PASS keycloak-chart-proof chart=24.4.2 StatefulSet KEYCLOAK_DATABASE_USER secretKeyRef=db-existing/{db_user_key}")
    return []
