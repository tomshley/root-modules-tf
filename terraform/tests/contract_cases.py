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
    "cloudflare-preview-website",
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
    "preview-tunnel-single": """module "preview" {
  source           = "../../../modules/cloudflare-preview-website"
  zone_id          = "00000000000000000000000000000001"
  account_id       = "00000000000000000000000000000002"
  tunnel_name      = "preview-tunnel"
  tunnel_secret    = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  preview_hostname = "preview.example.com"
  origin_url       = "http://localhost:8080"
}
""",
    "preview-tunnel-multi-zone": """module "preview" {
  source        = "../../../modules/cloudflare-preview-website"
  account_id    = "00000000000000000000000000000002"
  tunnel_name   = "preview-tunnel"
  tunnel_secret = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  origin_url    = "http://localhost:8080"
  hostnames = [
    {
      hostname = "zeta.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
    {
      hostname   = "alpha.example.org"
      zone_id    = "00000000000000000000000000000002"
      origin_url = "https://alpha.internal.example.com:8443"
    },
    {
      hostname = "mid.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
  ]
}
""",
    "preview-tunnel-combined": """module "preview" {
  source           = "../../../modules/cloudflare-preview-website"
  zone_id          = "00000000000000000000000000000001"
  account_id       = "00000000000000000000000000000002"
  tunnel_name      = "preview-tunnel"
  tunnel_secret    = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  preview_hostname = "preview.example.com"
  origin_url       = "http://localhost:8080"
  hostnames = [
    {
      hostname = "zzz.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
    {
      hostname = "aaa.example.com"
      zone_id  = "00000000000000000000000000000003"
    },
  ]
}
""",
    "preview-tunnel-duplicate-hostname": """module "preview" {
  source           = "../../../modules/cloudflare-preview-website"
  zone_id          = "00000000000000000000000000000001"
  account_id       = "00000000000000000000000000000002"
  tunnel_name      = "preview-tunnel"
  tunnel_secret    = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  preview_hostname = "Same.Example.com"
  origin_url       = "http://localhost:8080"
  hostnames = [
    {
      hostname = " same.example.com "
      zone_id  = "00000000000000000000000000000001"
    },
  ]
}
""",
    "preview-tunnel-missing-origin": """module "preview" {
  source        = "../../../modules/cloudflare-preview-website"
  account_id    = "00000000000000000000000000000002"
  tunnel_name   = "preview-tunnel"
  tunnel_secret = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  hostnames = [
    {
      hostname = "beta.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
  ]
}
""",
    "preview-tunnel-no-hostname": """module "preview" {
  source        = "../../../modules/cloudflare-preview-website"
  account_id    = "00000000000000000000000000000002"
  tunnel_name   = "preview-tunnel"
  tunnel_secret = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
}
""",
    "preview-tunnel-entry-origin-invalid": """module "preview" {
  source        = "../../../modules/cloudflare-preview-website"
  account_id    = "00000000000000000000000000000002"
  tunnel_name   = "preview-tunnel"
  tunnel_secret = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  hostnames = [
    {
      hostname   = "beta.example.com"
      zone_id    = "00000000000000000000000000000001"
      origin_url = "not-a-url"
    },
  ]
}
""",
    "preview-tunnel-dns-unmanaged": """module "preview" {
  source             = "../../../modules/cloudflare-preview-website"
  account_id         = "00000000000000000000000000000002"
  tunnel_name        = "preview-tunnel"
  tunnel_secret      = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  origin_url         = "http://localhost:8080"
  manage_dns_records = false
  hostnames = [
    {
      hostname = "beta.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
    {
      hostname = "alpha.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
  ]
}
""",
    "preview-tunnel-empty-origin": """module "preview" {
  source        = "../../../modules/cloudflare-preview-website"
  account_id    = "00000000000000000000000000000002"
  tunnel_name   = "preview-tunnel"
  tunnel_secret = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
  hostnames = [
    {
      hostname   = "beta.example.com"
      zone_id    = "00000000000000000000000000000001"
      origin_url = "   "
    },
  ]
}
""",
}


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


def planned_resources(root: dict) -> list[dict]:
    return [
        resource
        for module in [root, *root.get("child_modules", [])]
        for resource in module.get("resources", [])
    ]


EXPECTED_BINDINGS = {
    "tenancy-long-key-explicit-role": {
        "a" * 64: {"tenant_key": "a" * 64, "database_name": "alpha_db", "db_role_name": "alpha_role"},
    },
    "tenancy-derived-role-valid": {
        "alpha-beta": {"tenant_key": "alpha-beta", "database_name": "alpha_db", "db_role_name": "alpha_beta"},
    },
}

EXPECTED_INGRESS = {
    "preview-tunnel-single": [
        {"hostname": "preview.example.com", "service": "http://localhost:8080"},
        {"service": "http_status:404"},
    ],
    "preview-tunnel-multi-zone": [
        {"hostname": "alpha.example.org", "service": "https://alpha.internal.example.com:8443"},
        {"hostname": "mid.example.com", "service": "http://localhost:8080"},
        {"hostname": "zeta.example.com", "service": "http://localhost:8080"},
        {"service": "http_status:404"},
    ],
    "preview-tunnel-combined": [
        {"hostname": "aaa.example.com", "service": "http://localhost:8080"},
        {"hostname": "preview.example.com", "service": "http://localhost:8080"},
        {"hostname": "zzz.example.com", "service": "http://localhost:8080"},
        {"service": "http_status:404"},
    ],
    "preview-tunnel-dns-unmanaged": [
        {"hostname": "alpha.example.com", "service": "http://localhost:8080"},
        {"hostname": "beta.example.com", "service": "http://localhost:8080"},
        {"service": "http_status:404"},
    ],
}

EXPECTED_RESOURCE_COUNTS = {
    "preview-tunnel-dns-unmanaged": {
        "cloudflare_dns_record": 0,
        "cloudflare_zero_trust_tunnel_cloudflared": 1,
        "cloudflare_zero_trust_tunnel_cloudflared_config": 1,
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
    "preview-tunnel-duplicate-hostname": "must be unique across preview_hostname and hostnames",
    "preview-tunnel-missing-origin": "requires origin_url to be set",
    "preview-tunnel-no-hostname": "At least one of preview_hostname or hostnames",
    "preview-tunnel-entry-origin-invalid": "entry origin_url must start with http:// or https://",
    "preview-tunnel-empty-origin": "entry origin_url must be non-empty",
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
    # Plans run with -refresh=false against empty state and never reach the
    # Cloudflare API, but the provider must still configure itself. The plugin
    # cache created inside the temporary directory lets provider-backed cases
    # share one provider download per run; because each case directory has no
    # dependency lock file, the cache is only consulted when the lock-file
    # override is set, and these throwaway directories never keep a lock file.
    os.environ.setdefault("CLOUDFLARE_API_TOKEN", "0" * 40)
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="root-modules-contract-") as temp:
        temp_root = Path(temp)
        cache = temp_root / ".plugin-cache"
        cache.mkdir()
        os.environ.setdefault("TF_PLUGIN_CACHE_DIR", str(cache))
        os.environ.setdefault("TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE", "1")
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
                    planned = None
                    if name in EXPECTED_BINDINGS or name in EXPECTED_INGRESS or name in EXPECTED_RESOURCE_COUNTS:
                        shown = run([tofu, "show", "-json", "case.plan"], work)
                        if shown.returncode != 0:
                            failures.append(f"{name}: could not inspect plan")
                            continue
                        planned = json.loads(shown.stdout)["planned_values"]
                    if name in EXPECTED_BINDINGS:
                        values = planned["outputs"]["bindings"]["value"]
                        if values != EXPECTED_BINDINGS[name]:
                            failures.append(f"{name}: planned bindings changed")
                            continue
                    if name in EXPECTED_INGRESS:
                        configs = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "cloudflare_zero_trust_tunnel_cloudflared_config"
                        ]
                        ingress = [
                            {key: rule[key] for key in ("hostname", "service") if rule.get(key) is not None}
                            for rule in configs[0]["values"]["config"]["ingress"]
                        ] if len(configs) == 1 else []
                        if ingress != EXPECTED_INGRESS[name]:
                            failures.append(f"{name}: planned ingress changed")
                            continue
                    if name in EXPECTED_RESOURCE_COUNTS:
                        counts: dict[str, int] = {}
                        for resource in planned_resources(planned["root_module"]):
                            counts[resource["type"]] = counts.get(resource["type"], 0) + 1
                        if any(counts.get(t, 0) != n for t, n in EXPECTED_RESOURCE_COUNTS[name].items()):
                            failures.append(f"{name}: planned resource counts changed")
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
