# Operational Controls

This document describes operational requirements for safe use of these modules.

---

## Terraform State Security

Terraform state **contains sensitive data** including:
- Cluster CA certificates
- KMS key ARNs
- IAM role ARNs
- Service account emails
- Network topology details

### Requirements

1. **Remote state backend**: Never use local state in production. Use S3 + DynamoDB (AWS) or GCS (GCP) backends with state locking.
2. **Encryption at rest**: Enable server-side encryption on the state bucket (SSE-S3, SSE-KMS, or GCS default encryption).
3. **Restricted access**: Limit state bucket access to CI/CD service accounts and authorized operators only. No broad read access.
4. **State locking**: Enable state locking to prevent concurrent modifications (DynamoDB for S3, built-in for GCS).
5. **No secrets in state**: These modules minimize sensitive outputs (only `ca_certificate` is marked `sensitive`). However, state files should still be treated as confidential.

### Example: AWS S3 Backend

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}
```

### Example: GCP GCS Backend

```hcl
terraform {
  backend "gcs" {
    bucket = "my-terraform-state"
    prefix = "gke/terraform.tfstate"
  }
}
```

---

## Secrets Management

**Never store secrets in Terraform variables, `.tfvars` files, or state.**

### AWS

- Use **AWS Systems Manager Parameter Store** for configuration values.
- Use **AWS Secrets Manager** for credentials, API keys, database passwords.
- Reference in consumer root modules via `data "aws_ssm_parameter"` or `data "aws_secretsmanager_secret_version"`.

### GCP

- Use **Google Cloud Secret Manager** for all secrets.
- Reference in consumer root modules via `data "google_secret_manager_secret_version"`.

### Kubernetes

- Use **external-secrets-operator** to sync cloud secrets into Kubernetes.
- Do not use `kubernetes_secret` Terraform resources for sensitive data — they store plaintext in state.

---

## Logging and Monitoring

### EKS Control Plane Logging

Enabled by default: `api`, `audit`, `authenticator`.

**Consumer responsibilities:**
- Set CloudWatch Log Group retention policy (default is indefinite).
- Export logs to centralized SIEM if required by compliance.
- Configure CloudWatch alarms for API server errors and authentication failures.

### GKE Logging

GKE sends system and workload logs to Cloud Logging by default.

**Consumer responsibilities:**
- Configure log sinks for long-term retention or export.
- Set up log-based alerts for security events.

### General

- Enable CloudTrail (AWS) or Cloud Audit Logs (GCP) at the account/project level for API-level audit trails.
- These modules do not configure account-level logging — that is a foundational concern.

---

## Change Management

- All infrastructure changes should go through version-controlled Terraform code.
- Use `terraform plan` review before `terraform apply`.
- CI/CD pipelines should enforce plan review gates.
- Tag all releases with semantic versions for auditability.
