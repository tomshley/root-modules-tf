# Changelog

All notable changes to this project are documented in this file.

This project follows Semantic Versioning.

---

## [1.3.0] — 2026-03-27

### Features

- **confluent-streaming-topics**: Add overlay-driven Kafka topic provisioning module. Receives pre-parsed catalog entries and deployment overlays, filters by service/role inclusion and exclusion rules, and creates `confluent_kafka_topic` resources for the active set. Includes `prevent_destroy = true` lifecycle policy for production safety.

### Fixes

- **confluent-streaming-workload-access**: Strip inherited sensitivity from `schema_registry` using `nonsensitive()` so non-secret identifiers (cluster ID, CRN) can be used in `for_each` expressions without inheriting sensitivity from the parent variable.
- **confluent-streaming-workload-access**: Add validation rule for `service_account_display_name` requiring alphanumeric start/end and restricting allowed characters.

### Examples

- **streaming-full-stack**: Add complete consumer implementation example with YAML service catalogs, deployment overlays, region exclusions, stack composition, environment wrappers, Makefile automation, secure file examples, and operator tools reference.
- **streaming-topics-overlay**: Add reference example demonstrating 2 services, 2 roles, one excluded topic, and empty region exclusions.

### Toolbox

- **operator-tools**: Add reusable operator session scripts — `aws-session.sh`, `confluent-session.sh`, `k8s-session.sh` for credential loading and environment setup, and `render-streaming-bundle.sh` for rendering per-workload `.env` credential bundles from Terraform outputs.
- **confluent-bootstrap.sh**: Add idempotent Confluent Cloud bootstrap script for environment, cluster, Schema Registry, admin service account, API keys, and ACL provisioning.

### Documentation

- **README.md**: Add `confluent-streaming-topics` to module inventory and examples list. Add `streaming-full-stack` and operator tools to examples and toolbox sections.
- **Module README**: Document overlay filtering pipeline, topic lifecycle policy, inputs, outputs, usage, and known limitations.
- **operator-tools README**: Document script usage, sourcing patterns, and credential bundle rendering.

---

## [1.2.1] — 2026-03-27

### Infrastructure

- Version bump patch release.

---

## [1.2.0] — 2026-03-26

### Features

- **aws-eks-ci-oidc-access**: Add CI platform OIDC federation to EKS (IAM role, access entry)
- **gcp-gke-ci-oidc-access**: Add CI platform OIDC federation to GKE (Workload Identity, service account)
- **confluent-streaming-workload-access**: Add Confluent workload access module with service accounts, API keys, Kafka ACLs, and optional Schema Registry RBAC

### Examples

- **CI OIDC examples**: Add 6 examples covering GitHub Actions, GitLab CI, and Bitbucket Pipelines for both AWS/EKS and GCP/GKE
- **Confluent examples**: Add examples for commercial Confluent Cloud and external Schema Registry scenarios

### Security Fixes

- **aws-eks-ci-oidc-access**: Fix critical issue where module always created new OIDC provider. Add support for reusing existing providers via `oidc_provider_arn` input. Only one provider per issuer URL is allowed per AWS account.
- **gcp-gke-ci-oidc-access**: Fix Workload Identity IAM binding to use pool-scoped `principalSet` (the only valid GCP format). Provider-level restriction is handled by `attribute_condition` on the provider resource.
- **gcp-gke-ci-oidc-access**: Remove dead `project_name_prefix` input that was unused in resources.
- **aws-eks-ci-oidc-access**: Add validation to require `eks_access_scope_namespaces` when using namespace-scoped access.
- **aws-eks-ci-oidc-access**: Add validation on `oidc_provider_arn` format to fail early on malformed ARNs.
- **aws-eks-ci-oidc-access**: Add validation rejecting duplicate `test`+`claim` combinations in `trust_conditions` to prevent silent value loss from `merge()`.
- **aws-eks-ci-oidc-access**: Guard `oidc_provider_host` local against null `oidc_issuer_url` to surface clear precondition error instead of confusing type error.
- **confluent-streaming-workload-access**: Move `schema_subject_permissions` precondition to always-evaluated resource so permissions passed with `schema_registry = null` are rejected instead of silently ignored.
- **gcp-gke-ci-oidc-access**: Fix `pool_id` and `provider_id` validation to reject trailing hyphens (GCP API requirement).

### Infrastructure

- Replace LICENSE.md with full Apache 2.0 LICENSE file for OSS compliance.

### Documentation

- **README.md**: Update module inventory and examples list with new CI OIDC modules
- **Module READMEs**: Document security improvements and usage patterns for existing vs new providers

---

## [1.1.3] — 2026-03-24

### Infrastructure

- Update base containers reference to `0.4.3` in CI configuration.

---

## [1.1.2] — 2026-03-24

### Fixes

- **aws-eks-event-journal-db**: Set `apply_method = "pending-reboot"` on static parameters (`max_connections`, `wal_buffers`) to prevent `InvalidParameterCombination` errors during apply.

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

- **Cloudflare module suite**: Add `cloudflare-domain-baseline`, `cloudflare-website-acceleration`, `cloudflare-preview-website`, `cloudflare-access-guard`, `cloudflare-redirect-domain`, and `cloudflare-mail-foundation` for zone posture, public websites, preview publication, Access protection, redirect domains, and mail DNS.
- **Cloudflare examples**: Add reference examples for baseline-only zones, baseline-plus-mail composition, public websites, preview publication, Access protection, redirect domains, and standalone mail DNS publication.

### Fixes

- **cloudflare-domain-baseline**: Split DNS handling so proxyable `A`/`AAAA`/`CNAME` records and non-proxyable `TXT` records are managed separately, and include TXT record IDs in module outputs.
- **cloudflare-domain-baseline**: Tighten IPv4 validation for `A` record values.
- **cloudflare-redirect-domain**: Use a deterministic redirect rule reference derived from `sha256(zone_name)`.

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
- Add per-module system detection via naming convention (gcp-*, aws-*/eks-*, cloudflare-*)
