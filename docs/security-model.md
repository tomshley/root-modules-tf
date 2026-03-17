# Security Model

This document describes the security posture of the Terraform modules in this repository.

---

## Encryption Posture

All encryption is **always-on with no toggles**. There are no variables to disable encryption.

### AWS EKS

- **Secrets**: KMS envelope encryption via dedicated KMS key with automatic key rotation enabled (`aws_kms_key.eks_secrets`). Applied to all Kubernetes secrets at rest.
- **EBS Volumes**: All node group launch templates enforce `encrypted = true` with `gp3` volume type. No variable exists to disable this.
- **SQS**: Karpenter interruption queue uses `sqs_managed_sse_enabled = true`.

### GCP GKE

- GKE encrypts etcd data at rest by default (Google-managed encryption). Customer-managed encryption keys (CMEK) can be layered at the project level outside these modules.
- Boot disks use Google default encryption.

---

## IAM Least Privilege

### AWS

- **EKS Cluster Role**: Only `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController`.
- **Node Roles**: Only `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`.
- **Karpenter Controller**: Scoped to specific EC2, SSM, SQS, EKS, and IAM PassRole actions. `ec2:*` actions are intentionally broad for fleet management — scope `Resource` in the consumer root module if tighter controls are needed.
- **IRSA Roles**: Scoped per namespace and service account via OIDC `StringEquals` conditions. Consumer provides the policy ARNs.

### GCP

- **GKE Service Account**: Dedicated service account per cluster (`${prefix}-${org_id}`). Consumer should grant only necessary IAM roles at the project level.
- **Node OAuth Scopes**: `cloud-platform` scope (required by GKE). Actual permissions are controlled by the node service account's IAM roles, not the OAuth scope.

---

## Network Security

### AWS

- **EKS API Endpoint**: Public endpoint access CIDRs must be explicitly provided via required `public_access_cidrs`. No empty default is allowed.
- **Security Groups**: Dedicated cluster security group with no ingress rules by default. Outbound security group egress is open by default and is the consumer's responsibility to further restrict if required.
- **NAT**: One NAT gateway per AZ for private subnet egress. No shared NAT.
- **Public Subnets**: `map_public_ip_on_launch = true` is intentional for the public subnet/NAT topology.

### GCP

- **GKE**: Private nodes are enabled. Control plane access is restricted via required `master_authorized_networks_cidr_blocks`.
- **Client Certificate Auth**: Explicitly disabled (`issue_client_certificate = false`).
- **Cloud NAT**: Dedicated router and NAT config per cluster for egress from private nodes.

---

## Logging

- **AWS**: EKS control plane logging is enabled by default.
- **GCP**: GKE platform logging is enabled by default.

---

## Secrets Management

**No secrets should be stored in Terraform variables or `.tfvars` files.**

- **AWS**: Use AWS Systems Manager Parameter Store or AWS Secrets Manager. Reference via `aws_ssm_parameter` or `aws_secretsmanager_secret` data sources in the consumer root module.
- **GCP**: Use Google Cloud Secret Manager. Reference via `google_secret_manager_secret_version` data sources in the consumer root module.
- Kubernetes secrets should be managed via external-secrets-operator, sealed-secrets, or similar — not via Terraform `kubernetes_secret` resources.

---

## State Security

Remote encrypted state is required. See `docs/operational-controls.md` for Terraform/OpenTofu state requirements.

---

## Data Residency

Data residency is consumer-defined through region, zone, project, account, and remote state backend selection.
