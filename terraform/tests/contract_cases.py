#!/usr/bin/env python3
"""Run resource-free contract validation and deliberate negative cases."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES_PATH = ROOT / "terraform" / "contracts" / "scenarios" / "contract-cases.json"
MODULES = {
    "postgres-workload-contract",
    "postgres-tenancy-contract",
    "redis-service-contract",
    "node-provisioning-contract",
    "postgres-binding",
}

CASE_CONFIGS = {
    "postgres-event-store-valid": """
module "contract" {
  source = "../../../modules/postgres-workload-contract"
  contract = {
    purpose = "event-store"
    reader_required = false
    tls_required = true
    retention_days = 7
    authoritative = true
    projection_rebuildable = false
  }
}
""",
    "postgres-purpose-invalid": """
module "contract" {
  source = "../../../modules/postgres-workload-contract"
  contract = {
    purpose = "unknown"
    reader_required = false
    tls_required = true
    retention_days = 7
    authoritative = true
    projection_rebuildable = false
  }
}
""",
    "postgres-authority-mismatch": """
module "contract" {
  source = "../../../modules/postgres-workload-contract"
  contract = {
    purpose = "event-store"
    reader_required = false
    tls_required = true
    retention_days = 7
    authoritative = false
    projection_rebuildable = false
  }
}
""",
    "tenancy-valid": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    alpha = { database_name = "alpha_db" }
    beta = { database_name = "beta_db", db_role_name = "beta_role" }
  }
}
""",
    "tenancy-duplicate-database": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    alpha = { database_name = "shared_db" }
    beta = { database_name = "shared_db" }
  }
}
""",
    "tenancy-long-key-explicit-role": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    TENANT_KEY = { database_name = "alpha_db", db_role_name = "alpha_role" }
  }
}
output "bindings" {
  value = module.contract.tenant_bindings
}
""".replace("TENANT_KEY", "a" * 64),
    "tenancy-derived-role-valid": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    alpha-beta = { database_name = "alpha_db" }
  }
}
output "bindings" {
  value = module.contract.tenant_bindings
}
""",
    "tenancy-derived-role-too-long": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    TENANT_KEY = { database_name = "alpha_db" }
  }
}
""".replace("TENANT_KEY", "a" * 64),
    "tenancy-explicit-role-too-long": """
module "contract" {
  source = "../../../modules/postgres-tenancy-contract"
  tenants = {
    alpha = { database_name = "alpha_db", db_role_name = "ROLE_NAME" }
  }
}
""".replace("ROLE_NAME", "a" * 64),
    "redis-cache-valid": """
module "contract" {
  source = "../../../modules/redis-service-contract"
  contract = {
    mode = "cache"
    auth_required = true
    tls_required = true
    reader_required = true
    persistence_required = false
    availability = "multi-zone"
  }
}
""",
    "redis-retained-state-without-persistence": """
module "contract" {
  source = "../../../modules/redis-service-contract"
  contract = {
    mode = "retained-state"
    auth_required = true
    tls_required = true
    reader_required = false
    persistence_required = false
    availability = "multi-zone"
  }
}
""",
    "redis-reader-single-zone": """
module "contract" {
  source = "../../../modules/redis-service-contract"
  contract = {
    mode = "cache"
    auth_required = true
    tls_required = true
    reader_required = true
    persistence_required = false
    availability = "single-zone"
  }
}
""",
    "node-contract-valid": """
module "contract" {
  source = "../../../modules/node-provisioning-contract"
  contract = {
    capacity_types = ["on-demand", "spot"]
    labels = { role = "workload" }
    taints = [{ key = "workload", value = "reference", effect = "NoSchedule" }]
    max_cpu = "8"
    max_memory = "32Gi"
    disruption_policy = "when-empty-or-underutilized"
    controller_required = true
  }
}
""",
    "node-capacity-invalid": """
module "contract" {
  source = "../../../modules/node-provisioning-contract"
  contract = {
    capacity_types = ["unsupported"]
    labels = {}
    taints = []
    max_cpu = "8"
    max_memory = "32Gi"
    disruption_policy = "disabled"
    controller_required = false
  }
}
""",
    "postgres-binding-valid": """
module "contract" {
  source = "../../../modules/postgres-binding"
  binding = {
    host = "db.internal"
    port = 5432
    database_name = "alpha"
    tls_required = true
    ca_secret_name = "db-ca"
    username_secret_name = "db-user"
    password_secret_name = "db-password"
    reader_host = "reader.internal"
    reader_capable = true
  }
}
""",
    "postgres-binding-reader-mismatch": """
module "contract" {
  source = "../../../modules/postgres-binding"
  binding = {
    host = "db.internal"
    port = 5432
    database_name = "alpha"
    tls_required = true
    ca_secret_name = "db-ca"
    username_secret_name = "db-user"
    password_secret_name = "db-password"
    reader_capable = true
  }
}
""",
}


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


EXPECTED_BINDINGS = {
    "tenancy-long-key-explicit-role": {
        "a" * 64: {"tenant_key": "a" * 64, "database_name": "alpha_db", "db_role_name": "alpha_role"},
    },
    "tenancy-derived-role-valid": {
        "alpha-beta": {"tenant_key": "alpha-beta", "database_name": "alpha_db", "db_role_name": "alpha_beta"},
    },
}

EXPECTED_DIAGNOSTICS = {
    "postgres-purpose-invalid": "contract.purpose must be generic",
    "postgres-authority-mismatch": "An authoritative store is not",
    "tenancy-duplicate-database": "Tenant database names must be unique",
    "redis-retained-state-without-persistence": "retained-state requires persistence_required",
    "redis-reader-single-zone": "reader_required requires a multi-zone",
    "node-capacity-invalid": "capacity_types must contain",
    "postgres-binding-reader-mismatch": "reader_capable must match",
    "tenancy-derived-role-too-long": "Tenant role names after default derivation",
    "tenancy-explicit-role-too-long": "Tenant role names must be valid lowercase PostgreSQL identifiers",
}


def main() -> int:
    payload = json.loads(CASES_PATH.read_text())
    if payload.get("schema_revision") != "contract-cases-v1":
        raise SystemExit("unsupported contract case schema")
    cases = payload.get("cases", [])
    names = {case.get("name") for case in cases}
    if names != set(CASE_CONFIGS):
        raise SystemExit("case manifest and executable cases differ")
    if {case.get("module") for case in cases} != MODULES:
        raise SystemExit("case manifest does not cover every contract module")

    tofu = os.environ.get("TOFU", "tofu")
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="root-modules-contract-") as temp:
        temp_root = Path(temp)
        for case in cases:
            name = case["name"]
            work = temp_root / name
            work.mkdir()
            config = CASE_CONFIGS[name].replace("../../../modules", str(ROOT / "terraform" / "modules"))
            (work / "main.tf").write_text("terraform { required_version = \">= 1.9\" }\n" + config + "\n")
            init = run([tofu, "init", "-backend=false", "-input=false", "-no-color"], work)
            if init.returncode != 0:
                failures.append(f"{name}: initialization failed before the case could run")
                print((init.stdout + init.stderr)[-4000:])
                continue
            plan = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=case.plan"], work)
            diagnostics = plan.stdout + plan.stderr
            expected_pass = case["outcome"] == "pass"
            if expected_pass:
                actual_pass = plan.returncode == 0
                if not actual_pass:
                    failures.append(f"{name}: valid case failed during plan")
                    print(diagnostics[-4000:])
                else:
                    if name in EXPECTED_BINDINGS:
                        shown = run([tofu, "show", "-json", "case.plan"], work)
                        if shown.returncode != 0:
                            failures.append(f"{name}: could not inspect planned bindings")
                            continue
                        values = json.loads(shown.stdout)["planned_values"]["outputs"]["bindings"]["value"]
                        if values != EXPECTED_BINDINGS[name]:
                            failures.append(f"{name}: planned bindings changed")
                            continue
                    print(f"PASS {name} (pass)")
                continue
            expected_diagnostic = EXPECTED_DIAGNOSTICS.get(name)
            if plan.returncode == 0:
                failures.append(f"{name}: invalid case unexpectedly passed")
                continue
            if expected_diagnostic not in diagnostics:
                failures.append(f"{name}: plan failed without intended diagnostic: {expected_diagnostic}")
                print(diagnostics[-4000:])
                continue
            print(f"PASS {name} (fail: {expected_diagnostic})")
    if failures:
        print("\n".join(failures))
        return 1
    print(f"PASS contract cases={len(cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
