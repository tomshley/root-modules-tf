<p>
  <img src="assets/brand/logo.svg" alt="Tomshley Logo" width="200"/>
</p>

# Tomshley Root Modules TF

Terraform/OpenTofu root modules for Tomshley infrastructure provisioning.

This repository is part of the **Tomshley – OSS IP Division** and is maintained by **Tomshley LLC**.

---

## Overview

Composable Terraform modules for multi-cloud Kubernetes provisioning (GCP GKE + AWS EKS). Modules are organized under `terraform/modules/` and designed to be composed via explicit output wiring — no data source lookups for intra-module dependencies, no flag-driven branching, no timing hacks.

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
| `aws-eks-irsa` | AWS | Generic IRSA role factory | **New** |

### Examples

- `terraform/examples/gcp-gke-full-stack/` — GKE cluster + system/workload pools + NAT
- `terraform/examples/aws-eks-full-stack/` — EKS cluster + system/workload nodes + Karpenter prereqs + IRSA

- `aws-eks-cluster` requires explicit `public_access_cidrs`
- `gcp-gke-cluster` requires explicit `master_authorized_networks_cidr_blocks`

### Security Posture Highlights

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
