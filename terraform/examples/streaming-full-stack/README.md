# Streaming Full Stack — Consumer Implementation Example

This example demonstrates the complete consumer pattern for deploying Confluent Cloud streaming infrastructure using `root-modules-tf` modules. It mirrors the production layout used by real consumer repos.

## Structure

```text
streaming-full-stack/
├── catalogs/streaming/
│   ├── services/              # YAML topic definitions per service
│   │   ├── service-a/core.yaml
│   │   ├── service-b/
│   │   │   ├── core.yaml
│   │   │   └── dlq.yaml
│   │   └── service-c/core.yaml
│   ├── connectors/            # Connector configuration scaffolds
│   │   └── postgres-sinks/README.md
│   └── deployments/           # Overlay filters per environment/profile
│       ├── staging/
│       │   ├── commercial/base.yaml
│       │   └── gov/base.yaml
│       └── prod/
│           ├── commercial/base.yaml
│           └── gov/base.yaml
├── stacks/streaming/          # Shared infrastructure composition
│   ├── main.tf                # Stack description and profile docs
│   ├── locals.tf              # Derived values, credential reconstruction, SR split
│   ├── topics.tf              # Catalog discovery, overlay filtering, topic module
│   ├── access.tf              # Workload service accounts and ACLs
│   ├── connectors.tf          # Connector scaffold (future)
│   ├── secrets.tf             # Secrets management scaffold (future)
│   ├── variables.tf           # Stack input variables
│   ├── outputs.tf             # Topic summaries, workload credentials
│   └── versions.tf            # Terraform + provider version constraints
├── environments/              # Thin state-isolated wrappers
│   └── staging/us-east-1/streaming/
│       ├── main.tf            # Provider config + module call
│       ├── variables.tf       # Wrapper variables with defaults
│       ├── terraform.tfvars   # Committed non-sensitive inputs
│       ├── backend.tf         # HTTP backend for GitLab state
│       └── Makefile           # init/plan/apply/destroy automation
├── .secure_files/             # Example credential files (not committed)
│   ├── .env.example           # Shared backend settings
│   ├── staging-us-east-1-cloud.env.example
│   └── staging-us-east-1-streaming.env.example
├── scripts/
│   └── README.md              # Operator tool usage reference
└── README.md                  # This file
```

## Key Patterns

### Catalog-Driven Topics

Topics are defined in YAML files under `catalogs/streaming/services/<service>/<role>.yaml`. Each file contains a `topics` list with `name`, `partitions`, `retention_ms`, and `cleanup_policy`. The stack discovers all YAML files, annotates each topic with its `service` and `role` from the path, and passes them to the `confluent-streaming-topics` module.

### Deployment Overlays

Deployment overlays in `catalogs/streaming/deployments/<environment>/<profile>/base.yaml` select which service/role combinations are materialized. Topics not matched by any `include` rule remain catalog-only. Topics matched by `include` but listed in `exclude_topics` are skipped. Optional region-specific exclusion files can be placed in the `exclusions/` subdirectory.

### Stack + Environment Separation

- `stacks/streaming/` holds the real composition logic — all `.tf` files that define how modules are called, how catalogs are parsed, and how outputs are wired.
- `environments/<env>/<region>/streaming/` holds thin wrappers that own backend configuration, provider setup, committed variable defaults, and the Makefile.

### Module Sourcing

In this example, modules are sourced via local relative paths for development:

```hcl
source = "../../../../modules/confluent-streaming-topics"
```

For release, swap to pinned Git refs:

```hcl
source = "github.com/tomshley/root-modules-tf//terraform/modules/confluent-streaming-topics?ref=v1.3.0"
```

### Config and Credentials Separation

**Committed** (version-controlled, PR-reviewed):
- `terraform.tfvars` — all non-sensitive configuration (`confluent_config`, `workloads`, project/env/region)

**Secure files** (not committed, uploaded to GitLab Secure Files):
- `.secure_files/.env` — shared backend settings (GitLab project ID, TF state credentials)
- `.secure_files/<env>-<region>-<area>.env` — Confluent/AWS provider credentials + `TF_VAR_*` secrets

Secrets are injected as flat `TF_VAR_*` environment variables (e.g. `TF_VAR_kafka_admin_api_key`),
automatically consumed by OpenTofu/Terraform. No `.tfvars` files are used for secrets.

Example files with the `.example` suffix show the expected format.

### Operator Tools

Session setup and credential bundle rendering use the shared scripts in `toolbox/operator-tools/`. See `scripts/README.md` for usage.

## Quick Start

```bash
# 1. Copy example secure files
cp .secure_files/.env.example .secure_files/.env
cp .secure_files/staging-us-east-1-streaming.env.example .secure_files/staging-us-east-1-streaming.env

# 2. Fill in real credentials in the .env files
#    - .env: TF_PASSWORD, TOMSHLEY_CICD_FLOW_PUSH_TOKEN, etc.
#    - streaming.env: CONFLUENT_CLOUD_API_KEY/SECRET, TF_VAR_kafka_admin_api_key/secret

# 3. Edit terraform.tfvars with your Confluent config (non-sensitive)

# 4. Plan
cd environments/staging/us-east-1/streaming
make plan

# 5. Apply
make apply

# 6. Render credential bundles for workloads
../../../../toolbox/operator-tools/render-streaming-bundle.sh .
```

## Adapting for Your Project

1. Copy this entire `streaming-full-stack/` directory into your infrastructure repo
2. Replace `myproject` with your project name in `terraform.tfvars`, `Makefile`, and `variables.tf`
3. Replace the example service catalogs with your actual topic definitions
4. Adjust deployment overlays for your environments and profiles
5. Create real `.secure_files/` from the examples (secrets in `.env` files only)
6. Swap module `source` paths from local to pinned Git refs
