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
    "gcp-ci-oidc-role",
    "gcp-gke-cluster",
    "aws-eks-cluster",
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
    # The gcp-ci-oidc-role cases source the module through the ./modules
    # symlink the runner creates in every work dir, because its
    # ../ci-oidc-trust reference must resolve inside the same package — an
    # absolute local source would make the submodule escape the package
    # boundary and fail to install.
    "gcp-ci-oidc-exact-only": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
    { claim = "ref_protected", match = "exact", values = ["true"] },
  ]
}
""",
    "gcp-ci-oidc-wildcard-only": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "sub", match = "wildcard", values = ["project_path:my-group/*:ref_type:branch:ref:*"] },
  ]
}
""",
    "gcp-ci-oidc-combined": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
    { claim = "sub", match = "wildcard", values = ["project_path:my-group/my-repo:ref_type:branch:ref:*"] },
    { claim = "ref_protected", match = "exact", values = ["true"] },
  ]
}
""",
    "gcp-ci-oidc-multi-value-or": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com", "custom-audience"] },
    { claim = "ref_protected", match = "exact", values = ["true"] },
  ]
}
""",
    "gcp-ci-oidc-re2-escaping": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "sub", match = "wildcard", values = ["refs/(heads|tags)/v1.2+build-*", "env?[a-b]{2}^$\\\\x-*"] },
  ]
}
""",
    "gcp-ci-oidc-name-too-long": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "a-very-long-project-prefix"
  role_name_suffix    = "infrastructure-deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
  ]
}
""",
    "gcp-ci-oidc-pool-id-too-long": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "POOLPREFIX"
  role_name_suffix    = "x"
  issuer_url          = "https://gitlab.com"
  provider_id         = "ci-oidc"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
  ]
}
""".replace("POOLPREFIX", "a" * 25),
    "gcp-ci-oidc-reserved-prefix": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"
  pool_id             = "gcp-ci-pool"

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
  ]
}
""",
    "gcp-ci-oidc-unsupported-match": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "sub", match = "regex", values = ["^project_path:.*$"] },
  ]
}
""",
    "gcp-ci-oidc-claim-not-identifier": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "contract-test-project"
  project_name_prefix = "my-project"
  role_name_suffix    = "deploy"
  issuer_url          = "https://gitlab.com"

  conditions = [
    { claim = "ci-runner", match = "exact", values = ["shared"] },
  ]
}
""",
    "gke-cluster-name-at-limit": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id       = "org"
  google_region                = "us-east4"
  google_region_zone           = "us-east4-a"
  google_project_id            = "contract-test-project"
  project_name_prefix          = "ATLIMITPREFIX"
  google_compute_network_id    = "contract-network"
  google_compute_subnetwork_id = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name    = "pods-range"
  master_ipv4_cidr_block       = "172.16.0.0/28"
}
""".replace("ATLIMITPREFIX", "a" * 23),
    "gke-cluster-name-too-long": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id       = "org"
  google_region                = "us-east4"
  google_region_zone           = "us-east4-a"
  google_project_id            = "contract-test-project"
  project_name_prefix          = "TOOLONGPREFIX"
  google_compute_network_id    = "contract-network"
  google_compute_subnetwork_id = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name    = "pods-range"
  master_ipv4_cidr_block       = "172.16.0.0/28"
}
""".replace("TOOLONGPREFIX", "a" * 24),
    "gke-cluster-name-invalid-shape": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id       = "org"
  google_region                = "us-east4"
  google_region_zone           = "us-east4-a"
  google_project_id            = "contract-test-project"
  project_name_prefix          = "Bad-Name"
  google_compute_network_id    = "contract-network"
  google_compute_subnetwork_id = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name    = "pods-range"
  master_ipv4_cidr_block       = "172.16.0.0/28"
}
""",
    "eks-cluster-name-at-limit": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = "contract"
  cluster_name        = "CLUSTERNAME"
  vpc_id              = "vpc-00000000000000000"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  public_access_cidrs = ["10.0.0.0/8"]
}
""".replace("CLUSTERNAME", "a" * 100),
    "eks-cluster-name-too-long": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = "contract"
  cluster_name        = "CLUSTERNAME"
  vpc_id              = "vpc-00000000000000000"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  public_access_cidrs = ["10.0.0.0/8"]
}
""".replace("CLUSTERNAME", "a" * 101),
    "eks-cluster-name-invalid-shape": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = "contract"
  cluster_name        = "cluster.name.with.dots"
  vpc_id              = "vpc-00000000000000000"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  public_access_cidrs = ["10.0.0.0/8"]
}
""",
    "eks-role-name-at-limit": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = "ATLIMITPREFIX"
  cluster_name        = "contract-cluster"
  vpc_id              = "vpc-00000000000000000"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  public_access_cidrs = ["10.0.0.0/8"]
}
""".replace("ATLIMITPREFIX", "a" * 47),
    "eks-role-name-too-long": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = "TOOLONGPREFIX"
  cluster_name        = "contract-cluster"
  vpc_id              = "vpc-00000000000000000"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  public_access_cidrs = ["10.0.0.0/8"]
}
""".replace("TOOLONGPREFIX", "a" * 48),
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

# The generated CEL attribute_condition is asserted verbatim — escaping and
# grouping cases are only meaningful if the emitted text is checked, not
# merely that the plan succeeded.
EXPECTED_ATTRIBUTE_CONDITIONS = {
    "gcp-ci-oidc-exact-only": "assertion.aud == 'https://gitlab.com' && assertion.ref_protected == 'true'",
    "gcp-ci-oidc-wildcard-only": "assertion.sub.matches('^project_path:my-group/.*:ref_type:branch:ref:.*$')",
    "gcp-ci-oidc-combined": "assertion.aud == 'https://gitlab.com' && assertion.sub.matches('^project_path:my-group/my-repo:ref_type:branch:ref:.*$') && assertion.ref_protected == 'true'",
    "gcp-ci-oidc-multi-value-or": "(assertion.aud == 'https://gitlab.com' || assertion.aud == 'custom-audience') && assertion.ref_protected == 'true'",
    "gcp-ci-oidc-re2-escaping": "(assertion.sub.matches('^refs/\\\\(heads\\\\|tags\\\\)/v1\\\\.2\\\\+build-.*$') || assertion.sub.matches('^env.\\\\[a-b\\\\]\\\\{2\\\\}\\\\^\\\\$\\\\\\\\x-.*$'))",
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
    "gcp-ci-oidc-name-too-long": "GCP's 30-character limit",
    "gcp-ci-oidc-pool-id-too-long": "violates GCP's",
    "gcp-ci-oidc-reserved-prefix": "reserved prefix 'gcp-'",
    "gcp-ci-oidc-unsupported-match": 'match must be "exact" or "wildcard"',
    "gcp-ci-oidc-claim-not-identifier": "must be a CEL-safe identifier",
    "gke-cluster-name-too-long": "GKE cluster name",
    "gke-cluster-name-invalid-shape": "GKE cluster name",
    "eks-cluster-name-too-long": "at most 100 characters",
    "eks-cluster-name-invalid-shape": "at most 100 characters",
    "eks-role-name-too-long": "EKS cluster role name",
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
            # Cases whose module references sibling modules (gcp-ci-oidc-role
            # -> ../ci-oidc-trust) source through this symlink so the relative
            # reference stays inside the work dir's package boundary.
            os.symlink(ROOT / "terraform" / "modules", work / "modules")
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
                    if name in EXPECTED_BINDINGS or name in EXPECTED_INGRESS or name in EXPECTED_RESOURCE_COUNTS or name in EXPECTED_ATTRIBUTE_CONDITIONS:
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
                    if name in EXPECTED_ATTRIBUTE_CONDITIONS:
                        wip_providers = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_iam_workload_identity_pool_provider"
                        ]
                        condition = wip_providers[0]["values"]["attribute_condition"] if len(wip_providers) == 1 else None
                        if condition != EXPECTED_ATTRIBUTE_CONDITIONS[name]:
                            failures.append(f"{name}: planned attribute_condition changed")
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
