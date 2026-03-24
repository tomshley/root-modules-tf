# Changelog

All notable changes to this project are documented in this file.

This project follows Semantic Versioning.

---

## [1.1.1] — 2026-03-24

### Fixes

- **aws-eks-event-journal-db**: Remove `checkpoint_timeout` from cluster parameter group — Aurora Serverless v2 manages this parameter internally and rejects modifications via the ModifyDBClusterParameterGroup API.

## [1.1.0] — 2026-03-24

### Features

- **aws-eks-event-journal-db**: Add Aurora PostgreSQL Serverless v2 module for event journal workloads running on EKS, including subnet group, security group wiring, parameter group tuning, and Secrets Manager credential publication.
- **aws-eks-secure-s3**: Add hardened S3 module with public-access blocking, encryption, optional lifecycle rules, TLS-only bucket policy, and pre-built readwrite/readonly IAM policies for IRSA consumers.

### Documentation

- **Module inventory**: Document the new AWS data plane modules in `README.md`.

## [1.0.4] — 2026-03-23

### Features

- **Cloudflare module suite**: Add `cf-domain-baseline`, `cf-website-acceleration`, `cf-preview-website`, `cf-access-guard`, `cf-redirect-domain`, and `cf-mail-foundation` for zone posture, public websites, preview publication, Access protection, redirect domains, and mail DNS.
- **Cloudflare examples**: Add reference examples for baseline-only zones, baseline-plus-mail composition, public websites, preview publication, Access protection, redirect domains, and standalone mail DNS publication.

### Fixes

- **cf-domain-baseline**: Split DNS handling so proxyable `A`/`AAAA`/`CNAME` records and non-proxyable `TXT` records are managed separately, and include TXT record IDs in module outputs.
- **cf-domain-baseline**: Tighten IPv4 validation for `A` record values.
- **cf-redirect-domain**: Use a deterministic redirect rule reference derived from `sha256(zone_name)`.

### Documentation

- **Cloudflare module docs**: Clarify baseline-versus-mail composition boundaries, Cloudflare plan requirements for website acceleration, and redirect phase ownership expectations.

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
