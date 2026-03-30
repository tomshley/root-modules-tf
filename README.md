<p>
  <img src="assets/brand/logo.svg" alt="Tomshley Logo" width="200"/>
</p>

# Tomshley Root Modules TF

Terraform/OpenTofu root modules for Tomshley infrastructure provisioning.

This repository is part of the **Tomshley – OSS IP Division** and is maintained by **Tomshley LLC**.

---

## Overview

Composable Terraform modules for multi-cloud Kubernetes provisioning and Cloudflare edge/DNS composition. Modules are organized under `terraform/modules/` and designed to be composed via explicit output wiring — no data source lookups for intra-module dependencies, no flag-driven branching, no timing hacks.

### Design Principles

- **Modules behave like functions** — explicit inputs, explicit outputs, no hidden side effects
- **No data-source lookups** for intra-module dependencies — wire via outputs
- **No flag-driven branching** — no `create_vpc`, no `enable_karpenter`, no conditional fallbacks
- **Availability zones are required inputs** (AWS) — deterministic and composable, no auto-detection via data sources

### Module Inventory

| Module | Cloud | Description | Status |
|---|---|---|---|
| `gcp-project-with-api` | GCP | Project factory with API enablement | Stable |
| `gcp-gke-cluster` | GCP | GKE cluster with parameterized networking | Stable |
| `gcp-gke-nodepool` | GCP | Generic single-pool nodepool (instantiate N times) | Stable |
| `gcp-gke-external-nat` | GCP | Cloud NAT for private GKE clusters | Stable |
| `aws-eks-vpc` | AWS | Dedicated VPC with public/private subnets, NAT per AZ | **New** |
| `aws-eks-cluster` | AWS | EKS control plane with KMS, OIDC, CloudWatch | **New** |
| `aws-eks-nodegroup` | AWS | Generic managed node group (instantiate N times) | **New** |
| `aws-eks-karpenter-prereqs` | AWS | IAM + SQS + EventBridge for Karpenter (no Helm) | **New** |
| `aws-eks-karpenter-controller` | AWS | Karpenter controller deployment on EKS with service account and configuration | **New** |
| `aws-eks-metrics-server` | AWS | Metrics Server deployment on EKS for HPA and autoscaling metrics | **New** |
| `aws-eks-irsa` | AWS | Generic IRSA role factory | **New** |
| `aws-eks-event-journal-db` | AWS | Aurora PostgreSQL Serverless v2 module for EKS-hosted event journal workloads | **New** |
| `aws-eks-secure-s3` | AWS | Hardened S3 bucket with TLS-only policy and IRSA-ready IAM policies | **New** |
| `cloudflare-domain-baseline` | Cloudflare | Baseline SSL/TLS posture, curated DNS, optional Origin CA | **New** |
| `cloudflare-website-acceleration` | Cloudflare | Public website HTTPS, redirects, cache rules, edge settings | **New** |
| `cloudflare-preview-website` | Cloudflare | Tunnel-backed preview publication for an existing zone | **New** |
| `cloudflare-access-guard` | Cloudflare | Access protection for an existing hostname with email/email-domain allow rules | **New** |
| `cloudflare-redirect-domain` | Cloudflare | Standalone redirect domain with owned zone lifecycle | **New** |
| `cloudflare-mail-foundation` | Cloudflare | Mail DNS publication for an existing zone | **New** |
| `confluent-streaming-topics` | Confluent | Overlay-driven Kafka topic provisioning with deployment filtering | **New** |
| `confluent-streaming-workload-access` | Confluent | Service account, API keys, Kafka ACLs, optional Schema Registry RBAC | **New** |
| `aws-eks-ci-oidc-access` | AWS | CI platform OIDC federation to EKS (IAM role, access entry) | **New** |
| `gcp-gke-ci-oidc-access` | GCP | CI platform OIDC federation to GKE (Workload Identity, service account) | **New** |

### Examples

- `terraform/examples/gcp-gke-full-stack/` — GKE cluster + system/workload pools + NAT
- `terraform/examples/aws-eks-full-stack/` — EKS cluster + system/workload nodes + Karpenter prereqs + IRSA
- `terraform/examples/cloudflare-domain-baseline-minimal/` — baseline Cloudflare zone posture with curated DNS
- `terraform/examples/cloudflare-domain-baseline-with-mail/` — baseline posture composed with mail DNS publication
- `terraform/examples/cloudflare-public-website-standard/` — public website acceleration with the standard profile
- `terraform/examples/cloudflare-public-website-aggressive/` — public website acceleration with the aggressive profile
- `terraform/examples/cloudflare-preview-website-tunnel/` — tunnel-backed preview hostname publication
- `terraform/examples/cloudflare-access-guard-standalone/` — standalone Access protection for an existing hostname
- `terraform/examples/cloudflare-redirect-domain/` — redirect-only domain publication
- `terraform/examples/cloudflare-mail-foundation/` — standalone mail DNS publication
- `terraform/examples/streaming-full-stack/` — **Complete consumer implementation**: catalogs, stacks, environments, Makefiles, secure files, operator tools reference
- `terraform/examples/streaming-topics-overlay/` — Overlay-driven topic provisioning with inclusion/exclusion filtering
- `terraform/examples/streaming-workload-access-commercial/` — Confluent workload with Schema Registry access
- `terraform/examples/streaming-workload-access-external-sr/` — Kafka-only workload (external SR)
- `terraform/examples/aws-eks-ci-oidc-github/` — GitHub Actions → AWS → EKS deploy access
- `terraform/examples/aws-eks-ci-oidc-github-reuse/` — GitHub Actions with existing OIDC provider
- `terraform/examples/aws-eks-ci-oidc-gitlab/` — GitLab CI → AWS → EKS deploy access
- `terraform/examples/aws-eks-ci-oidc-bitbucket/` — Bitbucket Pipelines → AWS → EKS deploy access
- `terraform/examples/gcp-gke-ci-oidc-github/` — GitHub Actions → GCP → GKE deploy access
- `terraform/examples/gcp-gke-ci-oidc-gitlab/` — GitLab CI → GCP → GKE deploy access
- `terraform/examples/gcp-gke-ci-oidc-bitbucket/` — Bitbucket Pipelines → GCP → GKE deploy access

### Toolbox

- `toolbox/operator-tools/` — Reusable operator session scripts (AWS, Confluent, K8s, streaming bundle rendering). See [toolbox/operator-tools/README.md](toolbox/operator-tools/README.md).

### Utilities

- `tools/cloudflare-import/` — runnable read-only Cloudflare inventory, classification, scaffold, and review utility

### Security Posture Highlights

- `aws-eks-cluster` requires explicit `public_access_cidrs`
- `gcp-gke-cluster` requires explicit `master_authorized_networks_cidr_blocks`
- **EKS API access** is restricted via required `public_access_cidrs`
- **GKE control plane access** is restricted via required `master_authorized_networks_cidr_blocks`
- **Outbound security group egress is open by default** for the EKS control plane; consumer root modules must further restrict it if required
- **Public subnet IP assignment** in `aws-eks-vpc` is intentional for the public subnet/NAT topology
- **Logging is enabled by default** for EKS control plane logs and GKE platform logging
- **Remote encrypted state is required** for production use
- **Secrets must not be stored in `.tfvars` files**
- **AWS Systems Manager / Secrets Manager** and **GCP Secret Manager** should be used in consumer root modules
- **Data residency is consumer-defined** via region, zone, and backend selection

---

## Usage

```bash
cd terraform/<module>
terraform init
terraform plan
terraform apply
```

---

## Contributing

See CONTRIBUTING.md.

---

## Security

See SECURITY.md.

---

## License

Apache License 2.0. See LICENSE and NOTICE.md.

---

## Credits

Maintained by Tomshley LLC.
Tomshley and the Tomshley logo are trademarks of Tomshley LLC.
