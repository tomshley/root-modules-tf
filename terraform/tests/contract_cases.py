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

"""Run resource-free contract validation and deliberate negative cases."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from adapter_contract_check import live_hcl

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
    "gcp-gke-ci-oidc-access",
    "gcp-karpenter-prereqs",
    "gcp-gke-cluster",
    "gcp-gke-nodepool",
    "aws-eks-cluster",
    "aws-eks-nodegroup",
    "aws-eks-aurora-cluster",
    "gcp-cloudsql-postgres",
    "gcp-karpenter-crds",
    "gcp-karpenter-controller-release",
    "gcp-karpenter-controller",
    "gcp-gke-karpenter-controller",
    "aws-eks-karpenter-controller",
    "karpenter-controller-contract",
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
    "gke-ci-oidc-rbac-admin-off": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "../../../modules/gcp-gke-ci-oidc-access"

  project_id          = "contract-test-project"
  pool_id             = "contract-ci"
  provider_id         = "contract-oidc"
  oidc_issuer_url     = "https://gitlab.com"
  attribute_mapping   = { "google.subject" = "assertion.sub" }
  attribute_condition = "assertion.ref_protected == 'true'"
  service_account_id  = "contract-ci-deploy"
  project_roles       = ["roles/container.developer"]
}
""",
    "gke-ci-oidc-rbac-admin-enabled": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "../../../modules/gcp-gke-ci-oidc-access"

  project_id            = "contract-test-project"
  pool_id               = "contract-ci"
  provider_id           = "contract-oidc"
  oidc_issuer_url       = "https://gitlab.com"
  attribute_mapping     = { "google.subject" = "assertion.sub" }
  attribute_condition   = "assertion.ref_protected == 'true'"
  service_account_id    = "contract-ci-deploy"
  project_roles         = ["roles/container.developer"]
  kubernetes_rbac_admin = true
}
""",
    "gke-ci-oidc-rbac-admin-role-id-invalid": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "../../../modules/gcp-gke-ci-oidc-access"

  project_id                    = "contract-test-project"
  pool_id                       = "contract-ci"
  provider_id                   = "contract-oidc"
  oidc_issuer_url               = "https://gitlab.com"
  attribute_mapping             = { "google.subject" = "assertion.sub" }
  attribute_condition           = "assertion.ref_protected == 'true'"
  service_account_id            = "contract-ci-deploy"
  project_roles                 = ["roles/container.developer"]
  kubernetes_rbac_admin         = true
  kubernetes_rbac_admin_role_id = "bad-role-id"
}
""",
    "gke-ci-oidc-rbac-admin-role-id-too-long": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "ci" {
  source = "../../../modules/gcp-gke-ci-oidc-access"

  project_id                    = "contract-test-project"
  pool_id                       = "contract-ci"
  provider_id                   = "contract-oidc"
  oidc_issuer_url               = "https://gitlab.com"
  attribute_mapping             = { "google.subject" = "assertion.sub" }
  attribute_condition           = "assertion.ref_protected == 'true'"
  service_account_id            = "contract-ci-deploy"
  project_roles                 = ["roles/container.developer"]
  kubernetes_rbac_admin         = true
  kubernetes_rbac_admin_role_id = "TOOLONGROLEID"
}
""".replace("TOOLONGROLEID", "a" * 65),
    "karpenter-prereqs-canonical-role": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "prereqs" {
  source = "./modules/gcp-karpenter-prereqs"

  project_id                 = "contract-test-project"
  project_name_prefix        = "my-project"
  node_service_account_email = "contract-node@contract-test-project.iam.gserviceaccount.com"
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
    "gke-cluster-location-regional-default": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
}
""",
    "gke-cluster-managed-prometheus-default": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
}
""",
    "gke-cluster-managed-prometheus-off": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  managed_prometheus            = false
}
""",
    "gke-cluster-managed-prometheus-on": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  managed_prometheus            = true
}
""",
    "gke-cluster-monitoring-components-with-prometheus": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  managed_prometheus            = true
  monitoring_components         = ["KUBELET", "POD"]
}
""",
    "gke-cluster-monitoring-components-alone": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  monitoring_components         = ["SYSTEM_COMPONENTS", "KUBELET"]
}
""",
    "gke-cluster-monitoring-packages-without-prometheus": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  managed_prometheus            = false
  monitoring_components         = ["KUBELET"]
}
""",
    "gke-cluster-monitoring-components-invalid": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  monitoring_components         = ["NOT_A_COMPONENT"]
}
""",
    "gke-cluster-monitoring-components-empty": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  managed_prometheus            = true
  monitoring_components         = []
}
""",
    "gke-cluster-location-zonal": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  location_mode                 = "zonal"
}
""",
    "gke-cluster-location-mode-invalid": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "gke" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id        = "org"
  google_region                 = "us-east4"
  google_region_zone            = "us-east4-a"
  google_project_id             = "contract-test-project"
  project_name_prefix           = "contract"
  google_compute_network_id     = "contract-network"
  google_compute_subnetwork_id  = "contract-subnetwork"
  services_secondary_range_name = "services-range"
  pods_secondary_range_name     = "pods-range"
  location_mode                 = "multi-zonal"
}
""",
    "gke-nodepool-location-regional-default": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4/clusters/contract-standard-cluster"
}
""",
    "gke-nodepool-location-zonal": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
}
""",
    "gke-nodepool-location-mismatch": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
}
""",
    "gke-nodepool-location-unknown-self-link": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

resource "terraform_data" "cluster" {
  input = "contract-zonal-cluster"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/${terraform_data.cluster.output}"
}
""",
    "gke-nodepool-size-autoscaled-default": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
}
""",
    "karpenter-crds-alone": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "crds" {
  source = "../../../modules/gcp-karpenter-crds"
}
""",
    "karpenter-controller-release-alone": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
}
""",
    "karpenter-controller-composes-both": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

# gcp-karpenter-controller composes its sibling modules, so it sources
# through the work dir's modules symlink like gcp-ci-oidc-role.
module "karpenter" {
  source = "./modules/gcp-karpenter-controller"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  bootstrap_node_pool_name                = "contract-baseline"
  use_patched_dual_stack_image            = true
  image_pull_secrets                      = ["contract-registry"]
}
""",
    "karpenter-controller-release-image-conflict": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  use_patched_dual_stack_image            = true
  controller_image = {
    repository = "registry.example.com/karpenter"
    tag        = "v0.6.0"
  }
}
""",
    "karpenter-controller-contract-valid": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = 1
    keep_off_karpenter_nodes = true
    preference_policy        = "Ignore"
    priority_class_name      = null
  }
}
""",
    "karpenter-controller-contract-replicas-invalid": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = 0
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = null
  }
}
""",
    "karpenter-controller-contract-replicas-fractional": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = 1.5
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = null
  }
}
""",
    "karpenter-controller-contract-policy-empty": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = ""
    priority_class_name      = null
  }
}
""",
    "karpenter-controller-contract-policy-unsupported": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = "ignore"
    priority_class_name      = null
  }
}
""",
    "karpenter-controller-contract-priority-class-blank": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = " "
  }
}
""",
    "karpenter-controller-contract-priority-class-invalid": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "gmp critical"
  }
}
""",
    "karpenter-controller-contract-priority-class-uppercase": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "GMP-Critical"
  }
}
""",
    "karpenter-controller-contract-priority-class-edge-hyphen": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "-gmp-critical"
  }
}
""",
    "karpenter-controller-contract-priority-class-empty-label": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "gmp..critical"
  }
}
""",
    "karpenter-controller-contract-priority-class-edge-trailing-hyphen": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "gmp-critical-"
  }
}
""",
    "karpenter-controller-contract-priority-class-edge-dot": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "gmp."
  }
}
""",
    "karpenter-controller-contract-priority-class-label-hyphen": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "a.-b"
  }
}
""",
    "karpenter-controller-contract-priority-class-too-long": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  }
}
""",
    "karpenter-controller-contract-priority-class-longest": """
module "contract" {
  source = "../../../modules/karpenter-controller-contract"
  contract = {
    replicas                 = null
    keep_off_karpenter_nodes = null
    preference_policy        = null
    priority_class_name      = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  }
}
""",
    "karpenter-controller-release-keep-false": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  keep_controller_off_karpenter_nodes     = false
}
""",
    "karpenter-controller-release-replicas-only": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_replicas                     = 3
}
""",
    "karpenter-controller-release-preference-respect": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  preference_policy                       = "Respect"
}
""",
    "karpenter-controller-release-replicas-invalid": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_replicas                     = 0
}
""",
    "karpenter-controller-release-priority-class": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_priority_class_name          = "karpenter-controller"
}
""",
    "karpenter-controller-release-contract-set": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/gcp-karpenter-controller-release"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_replicas                     = 1
  keep_controller_off_karpenter_nodes     = true
  preference_policy                       = "Ignore"
}
""",
    "karpenter-controller-composes-contract-set": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "karpenter" {
  source = "./modules/gcp-karpenter-controller"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_replicas                     = 1
  keep_controller_off_karpenter_nodes     = true
  preference_policy                       = "Ignore"
  controller_priority_class_name          = "karpenter-controller"
}
""",
    "karpenter-shim-contract-set": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "shim" {
  source = "./modules/gcp-gke-karpenter-controller"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
  controller_replicas                     = 1
  keep_controller_off_karpenter_nodes     = true
  preference_policy                       = "Ignore"
  controller_priority_class_name          = "karpenter-controller"
}
""",
    "karpenter-shim-defaults": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "shim" {
  source = "./modules/gcp-gke-karpenter-controller"

  project_id                              = "contract-test-project"
  cluster_name                            = "contract-zonal-cluster"
  cluster_location                        = "us-east4-a"
  controller_google_service_account_email = "karpenter@contract-test-project.iam.gserviceaccount.com"
  node_service_account_email              = "nodes@contract-test-project.iam.gserviceaccount.com"
}
""",
    "aws-karpenter-controller-defaults": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
}
""",
    "aws-karpenter-controller-replicas-invalid": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  controller_replicas               = 0
}
""",
    "aws-karpenter-controller-version-null": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = null
}
""",
    "aws-karpenter-controller-keep-true": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                        = "contract-eks-cluster"
  cluster_endpoint                    = "https://contract-eks.example.com"
  karpenter_controller_role_arn       = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name   = "contract-karpenter-interruption"
  keep_controller_off_karpenter_nodes = true
}
""",
    "aws-karpenter-controller-priority-class": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  controller_priority_class_name    = "system-node-critical"
}
""",
    "aws-karpenter-controller-contract-set": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                        = "contract-eks-cluster"
  cluster_endpoint                    = "https://contract-eks.example.com"
  karpenter_controller_role_arn       = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name   = "contract-karpenter-interruption"
  karpenter_version                   = "1.4.0"
  controller_replicas                 = 3
  keep_controller_off_karpenter_nodes = false
  preference_policy                   = "Ignore"
}
""",
    "aws-karpenter-controller-version-forms": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "double_digit_minor" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "1.10.0"
  preference_policy                 = "Ignore"
}

module "v_prefixed" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "v1.4.0"
  preference_policy                 = "Ignore"
}

module "next_major" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "2.0.0"
  preference_policy                 = "Ignore"
}
""",
    "aws-karpenter-controller-preference-old-chart": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  preference_policy                 = "Ignore"
}
""",
    "aws-karpenter-controller-preference-before-1-4": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "1.3.3"
  preference_policy                 = "Ignore"
}
""",
    "aws-karpenter-controller-preference-major-zero": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "0.37.0"
  preference_policy                 = "Ignore"
}
""",
    "aws-karpenter-controller-preference-unreadable-version": """provider "helm" {
  kubernetes {
    host  = "https://127.0.0.1:1"
    token = "invalid-token-for-plan-only"
  }
}

module "controller" {
  source = "./modules/aws-eks-karpenter-controller"

  cluster_name                      = "contract-eks-cluster"
  cluster_endpoint                  = "https://contract-eks.example.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/contract-karpenter"
  karpenter_interruption_queue_name = "contract-karpenter-interruption"
  karpenter_version                 = "latest"
  preference_policy                 = "Ignore"
}
""",
    "gke-nodepool-size-fixed-zero": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
  node_count                         = 0
}
""",
    "gke-nodepool-size-negative": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
  node_count                         = -1
}
""",
    "gke-nodepool-size-fractional": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
  node_count                         = 1.5
}
""",
    "gke-nodepool-size-fixed-three": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "nodepool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = "contract"
  google_region                      = "us-east4"
  google_container_cluster_location  = "us-east4-a"
  pool_name_suffix                   = "standard"
  google_container_cluster_self_link = "projects/contract-test-project/locations/us-east4-a/clusters/contract-zonal-cluster"
  node_count                         = 3
}
""",
    "eks-nodegroup-size-default": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "nodegroup" {
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = "contract"
  cluster_name        = "contract-eks-cluster"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  node_group_name     = "baseline"
}
""",
    "eks-nodegroup-size-fixed-zero": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "nodegroup" {
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = "contract"
  cluster_name        = "contract-eks-cluster"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  node_group_name     = "baseline"
  node_count          = 0
}
""",
    "eks-nodegroup-size-fixed-three": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "nodegroup" {
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = "contract"
  cluster_name        = "contract-eks-cluster"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  node_group_name     = "baseline"
  node_count          = 3
}
""",
    "eks-nodegroup-size-fractional": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "nodegroup" {
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = "contract"
  cluster_name        = "contract-eks-cluster"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  node_group_name     = "baseline"
  node_count          = 1.5
}
""",
    "eks-nodegroup-size-negative": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "nodegroup" {
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = "contract"
  cluster_name        = "contract-eks-cluster"
  subnet_ids          = ["subnet-00000000000000000", "subnet-11111111111111111"]
  node_group_name     = "baseline"
  node_count          = -1
}
""",
    "aurora-activation-policy-default": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "db" {
  source = "./modules/aws-eks-aurora-cluster"

  project_name_prefix        = "contract"
  workload_name              = "application"
  vpc_id                     = "vpc-00000000000000000"
  subnet_ids                 = ["subnet-00000000000000000", "subnet-11111111111111111"]
  allowed_security_group_ids = ["sg-00000000000000000"]
  database_name              = "application"
  reader_instance_count      = 1
}
""",
    "aurora-activation-policy-never": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "db" {
  source = "./modules/aws-eks-aurora-cluster"

  project_name_prefix        = "contract"
  workload_name              = "application"
  vpc_id                     = "vpc-00000000000000000"
  subnet_ids                 = ["subnet-00000000000000000", "subnet-11111111111111111"]
  allowed_security_group_ids = ["sg-00000000000000000"]
  database_name              = "application"
  reader_instance_count      = 1
  activation_policy          = "NEVER"
}
""",
    "aurora-activation-policy-always": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "db" {
  source = "./modules/aws-eks-aurora-cluster"

  project_name_prefix        = "contract"
  workload_name              = "application"
  vpc_id                     = "vpc-00000000000000000"
  subnet_ids                 = ["subnet-00000000000000000", "subnet-11111111111111111"]
  allowed_security_group_ids = ["sg-00000000000000000"]
  database_name              = "application"
  reader_instance_count      = 1
  activation_policy          = "ALWAYS"
}
""",
    "aurora-activation-policy-invalid": """provider "aws" {
  region                      = "us-east-1"
  access_key                  = "invalid-key-for-plan-only"
  secret_key                  = "invalid-secret-for-plan-only"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "db" {
  source = "./modules/aws-eks-aurora-cluster"

  project_name_prefix        = "contract"
  workload_name              = "application"
  vpc_id                     = "vpc-00000000000000000"
  subnet_ids                 = ["subnet-00000000000000000", "subnet-11111111111111111"]
  allowed_security_group_ids = ["sg-00000000000000000"]
  database_name              = "application"
  reader_instance_count      = 1
  activation_policy          = "ON_DEMAND"
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
    # The gcp-cloudsql-postgres cases also source through ./modules because the
    # module's ../postgres-workload-contract submodule must stay inside the
    # package boundary, same as gcp-ci-oidc-role above.
    "cloudsql-edition-plus-custom-tier": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE_PLUS"
  tier                           = "db-custom-2-7680"
}
""",
    "cloudsql-edition-plus-perf-tier": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE_PLUS"
  tier                           = "db-perf-optimized-N-2"
}
""",
    "cloudsql-edition-enterprise-custom-tier": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
}
""",
    "cloudsql-edition-enterprise-perf-tier": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-perf-optimized-N-2"
}
""",
    "cloudsql-edition-unset": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  tier                           = "db-custom-2-7680"
}
""",
    "cloudsql-activation-policy-default": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
}
""",
    "cloudsql-activation-policy-never": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
  activation_policy              = "NEVER"
}
""",
    "cloudsql-activation-policy-always": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
  activation_policy              = "ALWAYS"
}
""",
    "cloudsql-activation-policy-on-demand": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
  activation_policy              = "ON_DEMAND"
}
""",
    "cloudsql-activation-policy-never-with-readers": """provider "google" {
  project      = "contract-test-project"
  access_token = "invalid-token-for-plan-only"
}

module "db" {
  source = "./modules/gcp-cloudsql-postgres"

  project_id                     = "contract-test-project"
  project_name_prefix            = "contract"
  workload_name                  = "contract-db"
  region                         = "us-east4"
  private_network_id             = "projects/contract-test-project/global/networks/contract-network"
  private_services_connection_id = "contract-connection"
  database_name                  = "contract"
  edition                        = "ENTERPRISE"
  tier                           = "db-custom-2-7680"
  activation_policy              = "NEVER"
  reader_instance_count          = 1
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
    # The opt-in RBAC grant must add exactly one custom role when enabled
    # and none when left at its default — the back-compat contract.
    "gke-ci-oidc-rbac-admin-off": {
        "google_project_iam_custom_role": 0,
    },
    "gke-ci-oidc-rbac-admin-enabled": {
        "google_project_iam_custom_role": 1,
    },
    # The planned_resources walk reaches the prereqs module's own resources;
    # the single service-account member binding there is the controller's
    # actAs grant scoped to the node service account (the workload-identity
    # submodule's binding sits a level deeper).
    "karpenter-prereqs-canonical-role": {
        "google_project_iam_custom_role": 1,
        "google_service_account_iam_member": 1,
    },
}

# Managed Prometheus and monitoring components as planned: with both unset,
# no monitoring_config renders, so the cluster's current settings stand; a
# set input renders exactly — enabled is the managed_prometheus block's setting,
# components the enable_components list — and nothing else in
# monitoring_config is set either way.
EXPECTED_GKE_MONITORING_CONFIG = {
    "gke-cluster-managed-prometheus-default": None,
    "gke-cluster-managed-prometheus-off": {"enabled": False, "components": ["SYSTEM_COMPONENTS"]},
    "gke-cluster-managed-prometheus-on": {"enabled": True, "components": None},
    "gke-cluster-monitoring-components-with-prometheus": {"enabled": True, "components": ["KUBELET", "POD"]},
    "gke-cluster-monitoring-components-alone": {"enabled": None, "components": ["KUBELET", "SYSTEM_COMPONENTS"]},
}

EXPECTED_GKE_CLUSTER_LOCATIONS = {
    "gke-cluster-location-regional-default": {
        "location": "us-east4",
        "node_locations": ["us-east4-a"],
    },
    "gke-cluster-location-zonal": {
        "location": "us-east4-a",
        "node_locations": None,
    },
}

EXPECTED_GKE_NODEPOOL_LOCATIONS = {
    "gke-nodepool-location-regional-default": "us-east4",
    "gke-nodepool-location-zonal": "us-east4-a",
    "gke-nodepool-location-unknown-self-link": "us-east4-a",
}

# The pool's size has one owner: the autoscaler by default, or a fixed
# node_count with no autoscaling block. Each case states which.
EXPECTED_GKE_NODEPOOL_SIZING = {
    "gke-nodepool-size-autoscaled-default": {
        "autoscaling": [{"min_node_count": 1, "max_node_count": 5, "location_policy": "ANY"}],
        "node_count": None,
    },
    "gke-nodepool-size-fixed-zero": {"autoscaling": [], "node_count": 0},
    "gke-nodepool-size-fixed-three": {"autoscaling": [], "node_count": 3},
}

# The EKS node group's scaling for each node_count, the counterpart of
# EXPECTED_GKE_NODEPOOL_SIZING: unset keeps min_size, max_size, and
# desired_size; a fixed count pins all three, with a maximum of at least 1.
EXPECTED_EKS_NODEGROUP_SIZING = {
    "eks-nodegroup-size-default": {"desired_size": 2, "max_size": 5, "min_size": 1},
    "eks-nodegroup-size-fixed-zero": {"desired_size": 0, "max_size": 1, "min_size": 0},
    "eks-nodegroup-size-fixed-three": {"desired_size": 3, "max_size": 3, "min_size": 3},
}

# The Aurora instances each activation policy plans, the counterpart of
# EXPECTED_CLOUDSQL_ACTIVATION_POLICIES: NEVER keeps the cluster and plans no
# instance at all.
EXPECTED_AURORA_INSTANCES = {
    "aurora-activation-policy-default": [
        "module.db.aws_rds_cluster_instance.reader[0]",
        "module.db.aws_rds_cluster_instance.writer[0]",
    ],
    "aurora-activation-policy-never": [],
    "aurora-activation-policy-always": [
        "module.db.aws_rds_cluster_instance.reader[0]",
        "module.db.aws_rds_cluster_instance.writer[0]",
    ],
}

# An unset activation policy plans as ALWAYS, the provider's own value for an
# instance created without one — the back-compat contract — and NEVER reaches
# the primary instance's settings.
EXPECTED_CLOUDSQL_ACTIVATION_POLICIES = {
    "cloudsql-activation-policy-default": "ALWAYS",
    "cloudsql-activation-policy-never": "NEVER",
    "cloudsql-activation-policy-always": "ALWAYS",
}

# Permissions a case's custom role must carry — the escalate/bind pair
# exists because Kubernetes' privilege-escalation prevention refuses
# Role/RoleBinding creation without them, which is not obvious from the
# CRUD verbs alone.
EXPECTED_REQUIRED_ROLE_PERMISSIONS = {
    "gke-ci-oidc-rbac-admin-enabled": {
        "container.roles.bind",
        "container.roles.create",
        "container.roles.delete",
        "container.roles.escalate",
        "container.roles.get",
        "container.roles.list",
        "container.roles.update",
        "container.roleBindings.create",
        "container.roleBindings.delete",
        "container.roleBindings.get",
        "container.roleBindings.list",
        "container.roleBindings.update",
    },
}

# Permissions GCP refuses to grant in a custom project role, plus
# iam.serviceAccounts.actAs, which the module deliberately binds on the node
# service account instead. Any of these in the planned role fails the case.
EXPECTED_FORBIDDEN_ROLE_PERMISSIONS = {
    # The RBAC grant is deliberately namespaced — cluster-scoped RBAC writes
    # would let a deploy identity grant permissions across every namespace.
    "gke-ci-oidc-rbac-admin-enabled": {
        "container.clusterRoles.create",
        "container.clusterRoles.delete",
        "container.clusterRoles.escalate",
        "container.clusterRoles.bind",
        "container.clusterRoles.get",
        "container.clusterRoles.list",
        "container.clusterRoles.update",
        "container.clusterRoleBindings.create",
        "container.clusterRoleBindings.delete",
        "container.clusterRoleBindings.get",
        "container.clusterRoleBindings.list",
        "container.clusterRoleBindings.update",
    },
    "karpenter-prereqs-canonical-role": {
        "container.nodePools.create",
        "container.nodePools.get",
        "container.nodePools.list",
        "container.nodePools.update",
        "container.nodePools.delete",
        "compute.regionInstanceTemplates.get",
        "compute.regionInstanceTemplates.list",
        "iam.serviceAccounts.actAs",
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

# Every Helm release the case plans, at any module depth, with its chart,
# chart version, and skip_crds. The split modules must each plan only their
# own release at the same chart version, and the composing module must keep
# planning both, so the CRDs survive a consumer that leaves the controller
# out. The controller release skips its chart's crds/ copies so the CRD
# release stays their only owner.
EXPECTED_HELM_RELEASES = {
    "karpenter-crds-alone": [
        ("module.crds.helm_release.crds", "karpenter-crd", "0.6.0", False),
    ],
    "karpenter-controller-release-alone": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-composes-both": [
        ("module.karpenter.module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
        ("module.karpenter.module.crds.helm_release.crds", "karpenter-crd", "0.6.0", False),
    ],
    "karpenter-controller-release-keep-false": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-release-replicas-only": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-release-preference-respect": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-release-priority-class": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-release-contract-set": [
        ("module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
    ],
    "karpenter-controller-composes-contract-set": [
        ("module.karpenter.module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
        ("module.karpenter.module.crds.helm_release.crds", "karpenter-crd", "0.6.0", False),
    ],
    "karpenter-shim-contract-set": [
        ("module.shim.module.karpenter.module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
        ("module.shim.module.karpenter.module.crds.helm_release.crds", "karpenter-crd", "0.6.0", False),
    ],
    "karpenter-shim-defaults": [
        ("module.shim.module.karpenter.module.controller.helm_release.karpenter", "karpenter", "0.6.0", True),
        ("module.shim.module.karpenter.module.crds.helm_release.crds", "karpenter-crd", "0.6.0", False),
    ],
    "aws-karpenter-controller-defaults": [
        ("module.controller.helm_release.karpenter", "karpenter", "1.1.0", False),
    ],
    "aws-karpenter-controller-keep-true": [
        ("module.controller.helm_release.karpenter", "karpenter", "1.1.0", False),
    ],
    "aws-karpenter-controller-priority-class": [
        ("module.controller.helm_release.karpenter", "karpenter", "1.1.0", False),
    ],
    "aws-karpenter-controller-contract-set": [
        ("module.controller.helm_release.karpenter", "karpenter", "1.4.0", False),
    ],
    "aws-karpenter-controller-version-forms": [
        ("module.double_digit_minor.helm_release.karpenter", "karpenter", "1.10.0", False),
        ("module.next_major.helm_release.karpenter", "karpenter", "2.0.0", False),
        ("module.v_prefixed.helm_release.karpenter", "karpenter", "v1.4.0", False),
    ],
}

# Rendered Helm values, verbatim. The composed case's controller values were
# captured from gcp-karpenter-controller before the split, with the same
# inputs, so a change in what the split release renders fails here rather
# than reaching an existing install as an in-place upgrade.
# The remaining Karpenter controller cases pin what each cloud renders for
# karpenter-controller-contract inputs, one input or combination per case,
# and the AWS defaults case pins the values the EKS release rendered before
# the contract existed.
EXPECTED_HELM_VALUES = {
    "karpenter-controller-composes-both": {
        "module.karpenter.module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  \"image\":\n    \"repository\": \"registry.gitlab.com/tomshley/brands/global/tware/tech/products/provisioning/vendored/karpenter-provider-gcp/karpenter\"\n    \"tag\": \"v0.6.0-dualstack\"\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"defaultNodePoolTemplateName\": \"contract-baseline\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"imagePullSecrets\":\n- \"name\": \"contract-registry\"\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-release-keep-false": {
        "module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-release-replicas-only": {
        "module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"replicaCount\": 3\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"podDisruptionBudget\":\n  \"maxUnavailable\": 1\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-release-preference-respect": {
        "module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  - \"name\": \"PREFERENCE_POLICY\"\n    \"value\": \"Respect\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-release-priority-class": {
        "module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"priorityClassName\": \"karpenter-controller\"\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-release-contract-set": {
        "module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"affinity\":\n    \"nodeAffinity\":\n      \"requiredDuringSchedulingIgnoredDuringExecution\":\n        \"nodeSelectorTerms\":\n        - \"matchExpressions\":\n          - \"key\": \"karpenter.sh/nodepool\"\n            \"operator\": \"DoesNotExist\"\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  - \"name\": \"PREFERENCE_POLICY\"\n    \"value\": \"Ignore\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"replicaCount\": 1\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"podDisruptionBudget\":\n  \"maxUnavailable\": 1\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-controller-composes-contract-set": {
        "module.karpenter.module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"affinity\":\n    \"nodeAffinity\":\n      \"requiredDuringSchedulingIgnoredDuringExecution\":\n        \"nodeSelectorTerms\":\n        - \"matchExpressions\":\n          - \"key\": \"karpenter.sh/nodepool\"\n            \"operator\": \"DoesNotExist\"\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  - \"name\": \"PREFERENCE_POLICY\"\n    \"value\": \"Ignore\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"priorityClassName\": \"karpenter-controller\"\n  \"replicaCount\": 1\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"podDisruptionBudget\":\n  \"maxUnavailable\": 1\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-shim-contract-set": {
        "module.shim.module.karpenter.module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"affinity\":\n    \"nodeAffinity\":\n      \"requiredDuringSchedulingIgnoredDuringExecution\":\n        \"nodeSelectorTerms\":\n        - \"matchExpressions\":\n          - \"key\": \"karpenter.sh/nodepool\"\n            \"operator\": \"DoesNotExist\"\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  - \"name\": \"PREFERENCE_POLICY\"\n    \"value\": \"Ignore\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"priorityClassName\": \"karpenter-controller\"\n  \"replicaCount\": 1\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"podDisruptionBudget\":\n  \"maxUnavailable\": 1\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "karpenter-shim-defaults": {
        "module.shim.module.karpenter.module.controller.helm_release.karpenter": [
            "\"controller\":\n  \"env\":\n  - \"name\": \"DEFAULT_NODEPOOL_SERVICE_ACCOUNT\"\n    \"value\": \"nodes@contract-test-project.iam.gserviceaccount.com\"\n  \"image\":\n    \"repository\": \"public.ecr.aws/cloudpilotai/gcp/karpenter\"\n    \"tag\": \"v0.6.0\"\n  \"settings\":\n    \"clusterLocation\": \"us-east4-a\"\n    \"clusterName\": \"contract-zonal-cluster\"\n    \"projectID\": \"contract-test-project\"\n\"credentials\":\n  \"enabled\": false\n\"serviceAccount\":\n  \"annotations\":\n    \"iam.gke.io/gcp-service-account\": \"karpenter@contract-test-project.iam.gserviceaccount.com\"\n  \"create\": true\n  \"name\": \"karpenter\"\n",
        ],
    },
    "aws-karpenter-controller-defaults": {
        "module.controller.helm_release.karpenter": [
            "\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n",
        ],
    },
    "aws-karpenter-controller-version-null": {
        "module.controller.helm_release.karpenter": [
            "\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n",
        ],
    },
    "aws-karpenter-controller-keep-true": {
        "module.controller.helm_release.karpenter": [
            "\"affinity\":\n  \"nodeAffinity\":\n    \"requiredDuringSchedulingIgnoredDuringExecution\":\n      \"nodeSelectorTerms\":\n      - \"matchExpressions\":\n        - \"key\": \"karpenter.sh/nodepool\"\n          \"operator\": \"DoesNotExist\"\n\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n",
        ],
    },
    "aws-karpenter-controller-priority-class": {
        "module.controller.helm_release.karpenter": [
            "\"priorityClassName\": \"system-node-critical\"\n\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n",
        ],
    },
    "aws-karpenter-controller-contract-set": {
        "module.controller.helm_release.karpenter": [
            "\"affinity\":\n  \"nodeAffinity\": null\n\"replicas\": 3\n\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n  \"preferencePolicy\": \"Ignore\"\n",
        ],
    },
    "aws-karpenter-controller-version-forms": {
        "module.double_digit_minor.helm_release.karpenter": [
            "\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n  \"preferencePolicy\": \"Ignore\"\n",
        ],
        "module.next_major.helm_release.karpenter": [
            "\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n  \"preferencePolicy\": \"Ignore\"\n",
        ],
        "module.v_prefixed.helm_release.karpenter": [
            "\"serviceAccount\":\n  \"annotations\":\n    \"eks.amazonaws.com/role-arn\": \"arn:aws:iam::123456789012:role/contract-karpenter\"\n  \"name\": \"karpenter\"\n\"settings\":\n  \"clusterEndpoint\": \"https://contract-eks.example.com\"\n  \"clusterName\": \"contract-eks-cluster\"\n  \"interruptionQueue\": \"contract-karpenter-interruption\"\n  \"preferencePolicy\": \"Ignore\"\n",
        ],
    },
}


def helm_release_resources(module: dict) -> list[dict]:
    found = [resource for resource in module.get("resources", []) if resource["type"] == "helm_release"]
    for child in module.get("child_modules", []):
        found.extend(helm_release_resources(child))
    return found


def helm_releases(module: dict) -> list[tuple[str, str, str, bool]]:
    return sorted(
        (
            resource["address"],
            resource["values"].get("chart"),
            resource["values"].get("version"),
            resource["values"].get("skip_crds"),
        )
        for resource in helm_release_resources(module)
    )


# Releases a consumer installed before gcp-karpenter-controller composed the
# split modules, keyed by the address each now plans at, with its old address
# and the attributes it held then that differ from what it plans now. The case
# re-plans against state holding them there: every one must be a move that
# neither creates nor destroys, or an existing install would reinstall, and
# an in-place update may change exactly those attributes and no others.
EXPECTED_PRIOR_STATE_MOVES = {
    "karpenter-controller-composes-both": {
        "module.karpenter.module.crds.helm_release.crds": ("module.karpenter.helm_release.crds", {}),
        "module.karpenter.module.controller.helm_release.karpenter": (
            "module.karpenter.helm_release.karpenter",
            {"skip_crds": False},
        ),
    },
}


def prior_state_moves(tofu: str, work: Path, plan_json: dict, moves: dict[str, tuple[str, dict]]) -> list[str]:
    """Write the planned releases into state at their old addresses and re-plan."""
    schemas = run([tofu, "providers", "schema", "-json"], work)
    if schemas.returncode != 0:
        return ["could not read provider schemas"]
    providers = json.loads(schemas.stdout)["provider_schemas"]
    resources = []
    for change in plan_json["resource_changes"]:
        if change["address"] not in moves:
            continue
        old_address, prior_attributes = moves[change["address"]]
        schema = providers[change["provider_name"]]["resource_schemas"][change["type"]]
        attributes = {name: None for name in schema["block"]["attributes"]}
        attributes.update({
            name: [] if block["nesting_mode"] in ("list", "set") else None
            for name, block in schema["block"].get("block_types", {}).items()
        })
        attributes.update({key: value for key, value in change["change"]["after"].items() if value is not None})
        attributes.update(prior_attributes)
        attributes["id"] = attributes["name"]
        module_address, _, resource_name = old_address.rpartition(".helm_release.")
        resources.append({
            "module": module_address,
            "mode": "managed",
            "type": change["type"],
            "name": resource_name,
            "provider": f'provider["{change["provider_name"]}"]',
            "instances": [{"schema_version": schema["version"], "attributes": attributes, "sensitive_attributes": []}],
        })
    (work / "terraform.tfstate").write_text(json.dumps({
        "version": 4, "terraform_version": "1.9.0", "serial": 1, "lineage": "contract-prior-state",
        "outputs": {}, "resources": resources,
    }))
    replan = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=prior.plan"], work)
    if replan.returncode != 0:
        return ["re-plan against prior state failed: " + (replan.stdout + replan.stderr)[-2000:]]
    shown = json.loads(run([tofu, "show", "-json", "prior.plan"], work).stdout)
    problems = []
    for change in shown["resource_changes"]:
        actions = set(change["change"]["actions"])
        if actions & {"create", "delete"}:
            problems.append(f"{change['address']} plans {sorted(actions)}")
            continue
        if change["address"] not in moves:
            continue
        old_address, prior_attributes = moves[change["address"]]
        if change.get("previous_address") != old_address:
            problems.append(f"{change['address']} was not moved from {old_address}")
        before, after = change["change"]["before"] or {}, change["change"]["after"] or {}
        unknown = change["change"].get("after_unknown") or {}
        updated = {key for key, value in after.items() if unknown.get(key) is not True and before.get(key) != value}
        if updated != set(prior_attributes):
            problems.append(f"{change['address']} updates {sorted(updated)}, expected {sorted(prior_attributes)}")
    return problems


# Example roots that must validate against the modules in this tree.
EXAMPLE_ROOTS = [
    "gcp-gke-environment-pause/cluster",
    "gcp-gke-environment-pause/node-provisioning",
    "aws-eks-environment-pause/cluster",
    "aws-eks-environment-pause/node-provisioning",
]

# moved blocks that keep existing installs from being replaced, by module
# file. The prior-state check above re-plans a whole case and so cannot hold a
# move inside a module whose other resources are absent from that state; these
# are checked as written instead.
REQUIRED_MOVES = [
    ("aws-eks-aurora-cluster/moved.tf", "aws_rds_cluster_instance.writer", "aws_rds_cluster_instance.writer[0]"),
]

# Module files that must stay identical: gcp-karpenter-controller passes
# every input through to gcp-karpenter-controller-release, and HCL cannot
# share variable declarations between modules.
IDENTICAL_MODULE_FILES = [
    ("gcp-karpenter-controller/variables.tf", "gcp-karpenter-controller-release/variables.tf"),
]

# Advisory check warnings a passing case's plan must carry.
EXPECTED_WARNINGS = {
    "cloudsql-edition-unset": "edition is unset while tier 'db-custom-2-7680' is a db-custom tier.",
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
    "gke-ci-oidc-rbac-admin-role-id-invalid": "custom role ID format",
    "gke-ci-oidc-rbac-admin-role-id-too-long": "custom role ID format",
    "gke-cluster-name-too-long": "GKE cluster name",
    "gke-cluster-name-invalid-shape": "GKE cluster name",
    "gke-cluster-location-mode-invalid": 'location_mode must be either "regional" or "zonal".',
    "gke-cluster-monitoring-packages-without-prometheus": "monitoring_components may name only SYSTEM_COMPONENTS",
    "gke-cluster-monitoring-components-invalid": "monitoring_components entries must be GKE monitoring components",
    "gke-cluster-monitoring-components-empty": "empty list is refused because GKE keeps system monitoring on",
    "gke-nodepool-size-negative": "node_count must be null or a whole number of nodes, 0 or more.",
    "gke-nodepool-size-fractional": "node_count must be null or a whole number of nodes, 0 or more.",
    "gke-nodepool-location-mismatch": "The node pool location differs from the cluster location in google_container_cluster_self_link; set google_container_cluster_location from the gcp-gke-cluster output google_container_cluster_gke_cluster_location.",
    "eks-cluster-name-too-long": "at most 100 characters",
    "eks-cluster-name-invalid-shape": "at most 100 characters",
    "eks-role-name-too-long": "EKS cluster role name",
    "cloudsql-edition-plus-custom-tier": "edition 'ENTERPRISE_PLUS' does not accept tier",
    "cloudsql-edition-enterprise-perf-tier": "edition 'ENTERPRISE' does not accept tier",
    "cloudsql-activation-policy-on-demand": "activation_policy must be ALWAYS or NEVER (ON_DEMAND is deprecated by Cloud SQL).",
    "cloudsql-activation-policy-never-with-readers": "activation_policy NEVER requires reader_instance_count = 0",
    "karpenter-controller-release-image-conflict": "use_patched_dual_stack_image and controller_image are mutually exclusive",
    "karpenter-controller-contract-replicas-invalid": "replicas must be null or a whole number of controller replicas, 1 or more.",
    "karpenter-controller-release-replicas-invalid": "replicas must be null or a whole number of controller replicas, 1 or more.",
    "aws-karpenter-controller-replicas-invalid": "replicas must be null or a whole number of controller replicas, 1 or more.",
    "karpenter-controller-contract-replicas-fractional": "replicas must be null or a whole number of controller replicas, 1 or more.",
    "karpenter-controller-contract-policy-empty": 'preference_policy must be null, "Respect", or "Ignore".',
    "karpenter-controller-contract-policy-unsupported": 'preference_policy must be null, "Respect", or "Ignore".',
    "karpenter-controller-contract-priority-class-blank": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-invalid": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-uppercase": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-edge-hyphen": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-empty-label": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-edge-trailing-hyphen": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-edge-dot": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-label-hyphen": "priority_class_name must be null or a PriorityClass name:",
    "karpenter-controller-contract-priority-class-too-long": "priority_class_name must be null or a PriorityClass name:",
    "aws-karpenter-controller-preference-before-1-4": 'preference_policy needs a karpenter_version that reads as 1.4 or later, because earlier Karpenter does not read PREFERENCE_POLICY; got "1.3.3".',
    "aws-karpenter-controller-preference-major-zero": 'preference_policy needs a karpenter_version that reads as 1.4 or later, because earlier Karpenter does not read PREFERENCE_POLICY; got "0.37.0".',
    "aws-karpenter-controller-preference-old-chart": 'preference_policy needs a karpenter_version that reads as 1.4 or later, because earlier Karpenter does not read PREFERENCE_POLICY; got "1.1.0".',
    "aws-karpenter-controller-preference-unreadable-version": 'preference_policy needs a karpenter_version that reads as 1.4 or later, because earlier Karpenter does not read PREFERENCE_POLICY; got "latest".',
    "eks-nodegroup-size-fractional": "node_count must be null or a whole number of nodes, 0 or more.",
    "eks-nodegroup-size-negative": "node_count must be null or a whole number of nodes, 0 or more.",
    "aurora-activation-policy-invalid": "activation_policy must be ALWAYS or NEVER.",
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
    modules_root = ROOT / "terraform" / "modules"
    for path, source, target in REQUIRED_MOVES:
        pattern = rf"moved\s*\{{\s*from\s*=\s*{re.escape(source)}\s+to\s*=\s*{re.escape(target)}\s*\}}"
        if re.search(pattern, live_hcl((modules_root / path).read_text())):
            print(f"PASS required-move {path} {source} -> {target}")
        else:
            failures.append(f"{path} lost the move {source} -> {target}")
    for first, second in IDENTICAL_MODULE_FILES:
        if (modules_root / first).read_text() != (modules_root / second).read_text():
            failures.append(f"{first} and {second} differ")
        else:
            print(f"PASS identical-module-files {first} {second}")
    with tempfile.TemporaryDirectory(prefix="root-modules-contract-") as temp:
        temp_root = Path(temp)
        cache = temp_root / ".plugin-cache"
        cache.mkdir()
        os.environ.setdefault("TF_PLUGIN_CACHE_DIR", str(cache))
        os.environ.setdefault("TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE", "1")
        for example in EXAMPLE_ROOTS:
            example_dir = ROOT / "terraform" / "examples" / example
            with tempfile.TemporaryDirectory(prefix="example-") as scratch:
                work_example = Path(scratch) / "terraform" / "examples" / example
                shutil.copytree(ROOT / "terraform" / "modules", Path(scratch) / "terraform" / "modules")
                shutil.copytree(example_dir, work_example, ignore=shutil.ignore_patterns(".terraform*"))
                init = run([tofu, "init", "-backend=false", "-input=false", "-no-color"], work_example)
                validate = run([tofu, "validate", "-no-color"], work_example) if init.returncode == 0 else init
                if validate.returncode != 0:
                    failures.append(f"example {example} does not validate: {(validate.stdout + validate.stderr)[-1500:]}")
                else:
                    print(f"PASS example-validate {example}")
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
                    expected_warning = EXPECTED_WARNINGS.get(name)
                    if expected_warning and " ".join(expected_warning.split()) not in " ".join(diagnostics.split()):
                        failures.append(f"{name}: plan passed without intended warning: {expected_warning}")
                        continue
                    planned = None
                    if (
                        name in EXPECTED_BINDINGS
                        or name in EXPECTED_INGRESS
                        or name in EXPECTED_RESOURCE_COUNTS
                        or name in EXPECTED_ATTRIBUTE_CONDITIONS
                        or name in EXPECTED_GKE_CLUSTER_LOCATIONS
                        or name in EXPECTED_GKE_MONITORING_CONFIG
                        or name in EXPECTED_GKE_NODEPOOL_LOCATIONS
                        or name in EXPECTED_GKE_NODEPOOL_SIZING
                        or name in EXPECTED_EKS_NODEGROUP_SIZING
                        or name in EXPECTED_CLOUDSQL_ACTIVATION_POLICIES
                        or name in EXPECTED_AURORA_INSTANCES
                        or name in EXPECTED_HELM_RELEASES
                        or name in EXPECTED_HELM_VALUES
                        or name in EXPECTED_PRIOR_STATE_MOVES
                        or name in EXPECTED_FORBIDDEN_ROLE_PERMISSIONS
                        or name in EXPECTED_REQUIRED_ROLE_PERMISSIONS
                    ):
                        shown = run([tofu, "show", "-json", "case.plan"], work)
                        if shown.returncode != 0:
                            failures.append(f"{name}: could not inspect plan")
                            continue
                        plan_json = json.loads(shown.stdout)
                        planned = plan_json["planned_values"]
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
                    if name in EXPECTED_GKE_MONITORING_CONFIG:
                        clusters = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_container_cluster"
                        ]
                        monitoring = (clusters[0]["values"].get("monitoring_config") or []) if len(clusters) == 1 else None
                        expected = EXPECTED_GKE_MONITORING_CONFIG[name]
                        enabled = (monitoring[0].get("managed_prometheus") or [{}])[0].get("enabled") if monitoring else None
                        components = sorted(monitoring[0]["enable_components"]) if monitoring and monitoring[0].get("enable_components") is not None else None
                        expected_components = sorted(expected["components"]) if expected and expected["components"] is not None else None
                        others = sorted(key for key, value in (monitoring[0] if monitoring else {}).items() if key not in ("managed_prometheus", "enable_components") and value not in (None, []))
                        if len(clusters) != 1 or enabled != (expected["enabled"] if expected else None) or components != expected_components or others:
                            failures.append(f"{name}: planned monitoring config changed: {monitoring}")
                            continue
                    if name in EXPECTED_GKE_CLUSTER_LOCATIONS:
                        clusters = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_container_cluster"
                        ]
                        locations = {
                            "location": clusters[0]["values"].get("location"),
                            "node_locations": clusters[0]["values"].get("node_locations"),
                        } if len(clusters) == 1 else None
                        if locations != EXPECTED_GKE_CLUSTER_LOCATIONS[name]:
                            failures.append(f"{name}: planned cluster locations changed: {locations}")
                            continue
                    if name in EXPECTED_GKE_NODEPOOL_LOCATIONS:
                        nodepools = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_container_node_pool"
                        ]
                        location = nodepools[0]["values"].get("location") if len(nodepools) == 1 else None
                        if location != EXPECTED_GKE_NODEPOOL_LOCATIONS[name]:
                            failures.append(f"{name}: planned nodepool location changed: {location}")
                            continue
                        if name == "gke-nodepool-location-unknown-self-link":
                            nodepool_changes = [
                                change
                                for change in plan_json.get("resource_changes", [])
                                if change.get("type") == "google_container_node_pool"
                            ]
                            after_unknown = (
                                nodepool_changes[0]["change"].get("after_unknown", {})
                                if len(nodepool_changes) == 1
                                else {}
                            )
                            if after_unknown.get("cluster") is not True:
                                failures.append(f"{name}: planned nodepool cluster link is not unknown")
                                continue
                    if name in EXPECTED_EKS_NODEGROUP_SIZING:
                        groups = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "aws_eks_node_group"
                        ]
                        sizing = (groups[0]["values"].get("scaling_config") or [None])[0] if len(groups) == 1 else None
                        if sizing != EXPECTED_EKS_NODEGROUP_SIZING[name]:
                            failures.append(f"{name}: planned node group sizing changed: {sizing}")
                            continue
                    if name in EXPECTED_AURORA_INSTANCES:
                        resources = planned_resources(planned["root_module"])
                        instances = sorted(
                            resource["address"] for resource in resources if resource["type"] == "aws_rds_cluster_instance"
                        )
                        clusters = [resource for resource in resources if resource["type"] == "aws_rds_cluster"]
                        if instances != EXPECTED_AURORA_INSTANCES[name] or len(clusters) != 1:
                            failures.append(f"{name}: planned Aurora cluster or instances changed: {len(clusters)} cluster(s), {instances}")
                            continue
                    if name in EXPECTED_GKE_NODEPOOL_SIZING:
                        nodepools = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_container_node_pool"
                        ]
                        sizing = {
                            "autoscaling": [
                                {key: block.get(key) for key in ("min_node_count", "max_node_count", "location_policy")}
                                for block in nodepools[0]["values"].get("autoscaling") or []
                            ],
                            "node_count": nodepools[0]["values"].get("node_count"),
                        } if len(nodepools) == 1 else None
                        if sizing != EXPECTED_GKE_NODEPOOL_SIZING[name]:
                            failures.append(f"{name}: planned nodepool sizing changed: {sizing}")
                            continue
                    if name in EXPECTED_CLOUDSQL_ACTIVATION_POLICIES:
                        primaries = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_sql_database_instance" and resource["name"] == "primary"
                        ]
                        policy = primaries[0]["values"]["settings"][0].get("activation_policy") if len(primaries) == 1 else None
                        if policy != EXPECTED_CLOUDSQL_ACTIVATION_POLICIES[name]:
                            failures.append(f"{name}: planned activation policy changed: {policy}")
                            continue
                    if name in EXPECTED_HELM_RELEASES:
                        releases = helm_releases(planned["root_module"])
                        if releases != EXPECTED_HELM_RELEASES[name]:
                            failures.append(f"{name}: planned Helm releases changed: {releases}")
                            continue
                    if name in EXPECTED_HELM_VALUES:
                        rendered = {
                            resource["address"]: resource["values"].get("values")
                            for resource in helm_release_resources(planned["root_module"])
                        }
                        changed = sorted(
                            address for address, values in EXPECTED_HELM_VALUES[name].items() if rendered.get(address) != values
                        )
                        if changed:
                            failures.append(f"{name}: rendered Helm values changed: {changed}")
                            continue
                    if name in EXPECTED_PRIOR_STATE_MOVES:
                        problems = prior_state_moves(tofu, work, plan_json, EXPECTED_PRIOR_STATE_MOVES[name])
                        if problems:
                            failures.append(f"{name}: existing installs would not carry over: {problems}")
                            continue
                    if name in EXPECTED_FORBIDDEN_ROLE_PERMISSIONS or name in EXPECTED_REQUIRED_ROLE_PERMISSIONS:
                        roles = [
                            resource
                            for resource in planned_resources(planned["root_module"])
                            if resource["type"] == "google_project_iam_custom_role"
                        ]
                        granted = {
                            permission
                            for role in roles
                            for permission in role["values"].get("permissions", [])
                        }
                        if name in EXPECTED_FORBIDDEN_ROLE_PERMISSIONS:
                            leaked = granted & EXPECTED_FORBIDDEN_ROLE_PERMISSIONS[name]
                            if leaked:
                                failures.append(f"{name}: custom role grants non-grantable or out-of-scope permissions: {sorted(leaked)}")
                                continue
                        if name in EXPECTED_REQUIRED_ROLE_PERMISSIONS:
                            missing = EXPECTED_REQUIRED_ROLE_PERMISSIONS[name] - granted
                            if missing:
                                failures.append(f"{name}: custom role is missing required permissions: {sorted(missing)}")
                                continue
                    print(f"PASS {name} (pass)")
                continue
            expected_diagnostic = EXPECTED_DIAGNOSTICS.get(name)
            if plan.returncode == 0:
                failures.append(f"{name}: invalid case unexpectedly passed")
                continue
            expected_diagnostic = " ".join(expected_diagnostic.split())
            diagnostics = " ".join(diagnostics.split())
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
