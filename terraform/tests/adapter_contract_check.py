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

"""Check that adapters consume shared decisions and the future publisher uses closure assembly."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def require(text: str, pattern: str, label: str) -> None:
    if not re.search(pattern, text, re.MULTILINE):
        raise SystemExit(f"missing {label}: {pattern}")


def reject_mutation(text: str, pattern: str, label: str) -> None:
    mutated = re.sub(pattern, "", text, count=1, flags=re.MULTILINE)
    try:
        require(mutated, pattern, label)
    except SystemExit:
        print(f"PASS adapter-negative {label}")
        return
    raise SystemExit(f"adapter guard failed to detect mutation: {label}")


def main() -> int:
    publisher = (ROOT / ".gitlab-ci.yml").read_text()
    require(publisher, r"CICD_PIPELINES_PYTHON_IMAGE", "pinned Python publication image")
    require(publisher, r"tools/module-package/package_module\.py", "dependency-closed publication assembly")
    require(publisher, r"tools/module-package/publish_module\.py", "verified module uploader")
    if "tar -vczf" in publisher:
        raise SystemExit("old module-only tar publication path remains")
    print("PASS publisher-uses-closure-assembly")

    aurora_locals = (ROOT / "terraform/modules/aws-eks-aurora-cluster/locals.tf").read_text()
    aurora_resources = (ROOT / "terraform/modules/aws-eks-aurora-cluster/resources.tf").read_text()
    require(aurora_locals, r"module\.tenancy_contract\.tenant_bindings", "shared tenant role derivation")
    require(aurora_resources, r"module \"tenancy_contract\"", "AWS tenancy contract consumer")
    require(aurora_locals, r"resolved_backup_retention_period", "AWS retention derivation")
    reject_mutation(aurora_locals, r"module\.tenancy_contract\.tenant_bindings", "tenant derivation ownership")
    keycloak_wrapper = (ROOT / "terraform/modules/aws-eks-keycloak/resources.tf").read_text()
    metrics_variables = (ROOT / "terraform/modules/aws-eks-metrics-server/variables.tf").read_text()
    metrics_resources = (ROOT / "terraform/modules/aws-eks-metrics-server/resources.tf").read_text()
    require(keycloak_wrapper, r"app\.kubernetes\.io/managed-by", "legacy Keycloak managed label")
    require(keycloak_wrapper, r"secrets-manager/arn", "legacy Keycloak secret annotations")
    keycloak_adapter = (ROOT / "terraform/modules/aws-keycloak/resources.tf").read_text()
    keycloak_outputs = (ROOT / "terraform/modules/aws-keycloak/outputs.tf").read_text()
    admin_credential_condition = r"var\.admin_password != null \|\| var\.admin_secret_arn != null"
    admin_credential_message = "Either admin_password or admin_secret_arn must be provided. Without both, Keycloak would start with no usable admin credentials."
    require(keycloak_adapter, r'check "admin_credentials_provided"', "legacy Keycloak credential check")
    require(keycloak_adapter, admin_credential_condition, "legacy Keycloak credential check condition")
    require(keycloak_adapter, re.escape(admin_credential_message), "legacy Keycloak credential warning message")
    require(keycloak_outputs, admin_credential_condition, "legacy Keycloak credential hard gate")
    require(keycloak_outputs, re.escape(admin_credential_message), "legacy Keycloak credential hard-gate message")
    reject_mutation(keycloak_adapter, re.escape(admin_credential_message), "Keycloak credential warning message")
    reject_mutation(keycloak_outputs, re.escape(admin_credential_message), "Keycloak credential hard-gate message")
    require(metrics_variables, r'variable "metrics_server_version"', "legacy Metrics Server version input")
    require(metrics_variables, r'variable "metrics_server_namespace"', "legacy Metrics Server namespace input")
    require(metrics_resources, r"var\.metrics_server_version", "legacy Metrics Server version wiring")
    require(metrics_resources, r"var\.metrics_server_namespace", "legacy Metrics Server namespace wiring")
    reject_mutation(keycloak_wrapper, r"app\.kubernetes\.io/managed-by", "Keycloak managed label")
    reject_mutation(metrics_variables, r'variable "metrics_server_version"', "Metrics Server version input")
    for moved_file, marker in {
        "aws-eks-keycloak/moved.tf": "module.keycloak.module.keycloak",
        "aws-eks-grafana-alloy/moved.tf": "module.alloy.helm_release.k8s_monitoring",
        "aws-eks-metrics-server/moved.tf": "module.metrics_server.helm_release.metrics_server",
    }.items():
        require((ROOT / "terraform/modules" / moved_file).read_text(), re.escape(marker), f"reviewed state move {moved_file}")
    print("PASS aws-legacy-interface-and-state-map")

    gcp_resources = (ROOT / "terraform/modules/gcp-cloudsql-postgres/resources.tf").read_text()
    gcp_variables = (ROOT / "terraform/modules/gcp-cloudsql-postgres/variables.tf").read_text()
    require(gcp_resources, r"transaction_log_retention_days\s*=\s*module\.workload_contract\.contract\.retention_days", "GCP elapsed retention mapping")
    require(gcp_resources, r"retention_days\s*<=\s*7", "GCP unsupported-retention refusal")
    require(gcp_variables, r"retention_days\s*<=\s*7", "GCP retention input validation")
    reject_mutation(gcp_resources, r"transaction_log_retention_days\s*=\s*module\.workload_contract\.contract\.retention_days", "GCP retention mapping")
    print("PASS gcp-retention-contract")

    print("PASS adapter-source-guard")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
