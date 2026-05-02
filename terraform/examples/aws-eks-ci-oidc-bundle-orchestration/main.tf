# Example: CI-rendered credential bundle orchestration
#
# Pattern: an infrastructure repository's CI provisions resources via
# `tofu apply`, then in a follow-on `bundle` stage renders credential
# bundles (env files, ConfigMaps) from the just-created Secrets Manager
# secrets and Terraform outputs, and uploads them to consumer projects'
# secure file stores. No human operator AWS credentials needed; bundle
# generation runs entirely under CI's OIDC-federated short-lived session.
#
# This example shows the IAM-side composition: a CI deploy role granted
# read access to a curated list of Secrets Manager secret ARNs via the
# `aws-eks-ci-oidc-access` module's `policy_arns` input. The CI pipeline
# itself (the bundle stage, matrix jobs, upload script) is consumer-side
# and lives in the consumer infrastructure repo's CI configuration.
#
# Scenario:
#   - Two downstream services consume credentials provisioned by this
#     infra repo: `service-a` and `service-b`.
#   - Each service has an Aurora tenant secret + a Redis AUTH secret.
#   - The infra repo's CI assumes a GitLab OIDC role to run `tofu apply`.
#   - The same role is then used in a `bundle` stage to read the secret
#     values, render env files, and upload to the consumer projects'
#     GitLab Secure Files via the GitLab API.
#
# The resulting role is least-privilege:
#   - Trust policy: only the infra repo's CI on the deploy branch.
#   - Permissions: EKS describe + (for example) S3 deploy artifacts +
#     Secrets Manager read on the explicit list of bundle-relevant ARNs.
#
# Pair this Terraform with a `.gitlab-ci.yml` bundle stage:
#
#   stages: [build, plan, deploy, bundle]
#
#   bundle:staging:
#     extends: .ci-deploy-runtime
#     stage: bundle
#     needs: [apply:staging:data, apply:staging:identity]
#     parallel:
#       matrix:
#         - SERVICE: [service-a, service-b]
#     script:
#       - ./scripts/bundle-orchestrator.sh
#     rules:
#       - if: '$CI_COMMIT_BRANCH == "develop"'
#         when: manual
#         allow_failure: false
#
# Where `bundle-orchestrator.sh` calls render-bundle.sh subcommands for
# each service's required bundles (aurora-config, aurora-tenant, redis-
# config, redis-auth, etc.) and then `sync-secure-files.sh` to upload
# them to the consumer project's secure file store.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ─────────────────────────────────────────────────────────────────────────
# Inputs: secret ARNs the bundle stage must read.
#
# In a real composition these come from outputs of upstream stacks
# (Aurora cluster module's tenant secret outputs, ElastiCache Redis
# module's auth_secret_arn output, etc.) — typically wired via remote
# state or direct module references. Hard-coded here for example
# clarity.
# ─────────────────────────────────────────────────────────────────────────

locals {
  bundle_readable_secret_arns = [
    "arn:aws:secretsmanager:us-east-1:111111111111:secret:product-db/staging/service-a-tenant-AbCdEf",
    "arn:aws:secretsmanager:us-east-1:111111111111:secret:product-db/staging/service-b-tenant-XyZ123",
    "arn:aws:secretsmanager:us-east-1:111111111111:secret:elasticache/staging/service-a-auth-Aa11Bb",
    "arn:aws:secretsmanager:us-east-1:111111111111:secret:elasticache/staging/service-b-auth-Cc22Dd",
  ]
}

# ─────────────────────────────────────────────────────────────────────────
# Bundle-read IAM policy.
#
# Grants only what `render-bundle.sh` needs to read a secret value:
# GetSecretValue (the value itself) + DescribeSecret (metadata for the
# helper to resolve the latest version stage). Resources are scoped to
# the explicit ARN list — no wildcards, no account-wide read.
#
# Composed at the consumer (this example) level rather than inside the
# `aws-eks-ci-oidc-access` module so the module stays domain-neutral.
# ─────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "bundle_read" {
  statement {
    sid       = "ReadBundleSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = local.bundle_readable_secret_arns
  }
}

resource "aws_iam_policy" "bundle_read" {
  name        = "example-staging-ci-bundle-read"
  description = "Allows the CI deploy role to read the curated list of Secrets Manager secrets that downstream credential bundles render. Scoped via explicit ARNs; no wildcards."
  policy      = data.aws_iam_policy_document.bundle_read.json
}

# ─────────────────────────────────────────────────────────────────────────
# CI OIDC role.
#
# The `policy_arns` input takes the bundle-read policy alongside any
# other deploy-time policies the role needs. Domain-specific policy
# composition stays at the consumer layer; the module remains a generic
# "CI OIDC role + EKS access entry" primitive.
# ─────────────────────────────────────────────────────────────────────────

module "ci_deploy" {
  source = "../../modules/aws-eks-ci-oidc-access"

  project_name_prefix = "example-staging"
  role_name_suffix    = "gitlab-deploy"
  eks_cluster_name    = "example-staging-eks-cluster"

  oidc_issuer_url  = "https://gitlab.com"
  oidc_audiences   = ["https://gitlab.com"]
  oidc_thumbprints = []

  trust_conditions = [
    {
      test   = "StringEquals"
      claim  = "aud"
      values = ["https://gitlab.com"]
    },
    {
      test  = "StringLike"
      claim = "sub"
      values = [
        "project_path:my-group/my-infra-repo:ref_type:branch:ref:develop",
        "project_path:my-group/my-infra-repo:ref_type:branch:ref:main",
      ]
    },
  ]

  # Compose deploy-time policies (existing) with the bundle-read policy
  # (this example's contribution). Add other policy ARNs (ECR pull,
  # CloudWatch log write, S3 deploy artifact write, etc.) to the same
  # list as your deploy needs grow.
  policy_arns = [
    aws_iam_policy.bundle_read.arn,
    # "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    # "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ]

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Purpose     = "ci-deploy-and-bundle-orchestration"
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Outputs: feed downstream consumers (project access tokens, CI
# variables, etc.).
# ─────────────────────────────────────────────────────────────────────────

output "ci_deploy_role_arn" {
  description = "ARN of the CI deploy + bundle-orchestration role. Set as the AWS_ROLE_ARN CI variable in the infra repo so the OIDC adapter assumes it."
  value       = module.ci_deploy.role_arn
}

output "bundle_read_policy_arn" {
  description = "ARN of the composed bundle-read policy. Useful for auditing or attaching to additional roles."
  value       = aws_iam_policy.bundle_read.arn
}
