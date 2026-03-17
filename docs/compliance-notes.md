# Compliance Notes

This document outlines how these modules support compliance readiness for frameworks including HIPAA, SOC 2, and GDPR.

---

## Scope

These modules provision **infrastructure only**. Application-level compliance (data handling, consent management, audit logging within applications) is the consumer's responsibility.

---

## Encryption at Rest

| Resource | Encryption | Key Management | Toggle |
|---|---|---|---|
| EKS Kubernetes Secrets | KMS envelope encryption | Dedicated KMS key, auto-rotation | **None — always on** |
| EBS Volumes (node disks) | AES-256 via EBS encryption | AWS-managed or KMS | **None — always on** |
| SQS (Karpenter interruption) | SSE-SQS | AWS-managed | **None — always on** |
| GKE etcd | Google default encryption | Google-managed | Always on (GCP default) |

---

## Encryption in Transit

- EKS API server uses TLS (managed by AWS).
- GKE API server uses TLS (managed by Google).
- Intra-cluster communication encryption depends on CNI and service mesh configuration (consumer responsibility).

---

## Logging

### AWS EKS

Control plane logging is enabled by default for:
- `api` — Kubernetes API server
- `audit` — Kubernetes audit log
- `authenticator` — IAM authenticator
- `controllerManager` — Kubernetes controller manager
- `scheduler` — Kubernetes scheduler

Logs are sent to CloudWatch Logs. **Log retention policy is the consumer's responsibility** — configure retention on the CloudWatch Log Group in the consumer root module.

### GCP GKE

GKE sends logs to Cloud Logging by default. Log retention and export configuration are the consumer's responsibility.

---

## Access Control

- All IAM roles follow least-privilege principles (see `docs/security-model.md`).
- No wildcard (`*`) resource ARNs except where required by AWS API design (EC2 Describe actions, Pricing API).
- IRSA roles are scoped to specific namespace + service account combinations.

---

## Data Residency

**Data residency is consumer-defined.**

- AWS: Consumer selects the region via provider configuration and availability zones via module inputs.
- GCP: Consumer selects the region and zone via module inputs.
- These modules do not replicate data across regions or create cross-region resources.

---

## Tagging / Labeling

Modules support compliance tagging where the target resource/provider supports it:
- **AWS**: `tags` variable (`map(string)`) merged into all resources.
- **GCP**: `labels` variable (`map(string)`) applied as `resource_labels` where supported.

Consumers should use these for cost allocation, environment identification, and compliance tracking.

---

## Audit Trail

- Terraform state files contain a full record of infrastructure configuration.
- CloudTrail (AWS) and Cloud Audit Logs (GCP) provide API-level audit trails.
- These modules do not configure CloudTrail or Cloud Audit Logs — that is a foundational account-level concern.
