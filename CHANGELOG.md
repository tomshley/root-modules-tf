# Changelog

All notable changes to this project are documented in this file.

This project follows Semantic Versioning.

---

## [1.0.0] — 2026-03-17

### Breaking Changes

- Legacy specialized GKE nodepool module deleted. Only `gcp-gke-nodepool` remains.
- **gcp-gke-cluster, gcp-gke-external-nat**: Provider constraint widened from `~> 6.0.0` to `~> 6.0`.
- **aws-eks-cluster**: `vpc_id` and `public_access_cidrs` are required inputs. Removed internal `data "aws_subnet"` lookup.
- **gcp-gke-cluster**: `master_authorized_networks_cidr_blocks` is a required input for control plane access.

### Features

- **gcp-gke-cluster**: Parameterized networking — `subnet_cidr`, `services_cidr`, `pods_cidr`, `master_ipv4_cidr_block`, `ipv6_access_type` with backward-compatible defaults.
- **gcp-gke-cluster**: New outputs — `self_link`, `location`, `endpoint`, `ca_certificate` (sensitive), `service_account_email`.
- **gcp-gke-nodepool** (NEW): Generic single-pool module with labels, taints, kubelet_config, service account, validation. Consumers instantiate N times for multi-pool architectures.
- **aws-eks-vpc** (NEW): Dedicated VPC with public/private subnets, IGW, NAT gateway per AZ, EKS subnet tags. AZ/CIDR length validation.
- **aws-eks-cluster** (NEW): EKS control plane with KMS envelope encryption, OIDC provider for IRSA, CloudWatch logging. Private endpoint by default.
- **aws-eks-nodegroup** (NEW): Generic managed node group with launch template, labels, taints. Consumers instantiate N times.
- **aws-eks-karpenter-prereqs** (NEW): IAM roles, SQS interruption queue, EventBridge rules for Karpenter. No Helm.
- **aws-eks-irsa** (NEW): Generic IRSA role factory for any namespace/service account combination.
- **AWS modules**: `tags` variables for compliance tagging.
- **GCP modules**: `labels` variables where resource labeling is supported.
- Reference examples: `gcp-gke-full-stack`, `aws-eks-full-stack`.

### Fixes

- **aws-eks-cluster**: Removed `data "aws_subnet"` lookup — VPC ID now explicit input.
- **aws-eks-cluster**: Removed `data "tls_certificate"` lookup and `tls` provider dependency. OIDC thumbprint set to `[]` (AWS manages thumbprints for EKS OIDC).
- **gcp-gke-cluster**: Disabled legacy client certificate authentication (`issue_client_certificate = false`).

### Compliance

- Encryption always-on: EKS KMS envelope encryption, EBS gp3 encrypted volumes. No toggles.
- GKE client certificate auth disabled by default.
- Compliance documentation: `docs/security-model.md`, `docs/compliance-notes.md`, `docs/operational-controls.md`.

### Infrastructure

- Initial OSS standardization (LICENSE, NOTICE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG, ROADMAP)
- Modernize CI/CD: include cicd-pipelines adapter v0.5.0 (gitflow lifecycle, security scanning, publish policy)
- Replace hardcoded module list with auto-discovery loop over terraform/modules/
- Add per-module system detection via naming convention (gcp-*, aws-*/eks-*, cf-*/cloudflare-*)
