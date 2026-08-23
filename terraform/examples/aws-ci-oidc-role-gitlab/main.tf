# Example: GitLab CI → AWS federated role for an infrastructure pipeline
#
# The cluster-less counterpart of the aws-eks-ci-oidc-gitlab example: the
# pipeline this role serves is the one that provisions infrastructure —
# including any cluster — so the role must exist without one. No EKS access
# entry is created and no Kubernetes permissions are granted; everything the
# role can do arrives through policy_arns.
#
# GitLab.com OIDC issuer: https://gitlab.com
# Self-managed GitLab: use your GitLab instance URL

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

# Least-privilege example policy: scope to the services the pipeline
# actually manages. Shown inline so the example is self-contained.
resource "aws_iam_policy" "infrastructure_deploy" {
  name = "my-project-production-ci-infrastructure-deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "eks:Describe*",
          "eks:List*",
        ]
        Resource = "*"
      }
    ]
  })
}

module "infrastructure_deploy" {
  source = "../../modules/aws-ci-oidc-role"

  project_name_prefix = "my-project-production"
  role_name_suffix    = "infrastructure-deploy"

  # GitLab CI OIDC (gitlab.com — use your instance URL for self-managed).
  # Where another module already registered the gitlab.com provider in this
  # account, pass oidc_provider_arn instead — AWS allows one provider per
  # issuer URL per account.
  issuer_url = "https://gitlab.com"
  audiences  = ["https://gitlab.com"]

  # Trust: tag pipelines of one project, on protected refs only —
  # the posture for environments that deploy exclusively from tags.
  # GitLab sub format: project_path:{group}/{project}:ref_type:{type}:ref:{ref}
  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
    { claim = "sub", match = "wildcard", values = ["project_path:my-group/my-infrastructure:ref_type:tag:ref:*"] },
    { claim = "ref_protected", match = "exact", values = ["true"] },
  ]

  policy_arns = [aws_iam_policy.infrastructure_deploy.arn]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

output "role_arn" {
  value = module.infrastructure_deploy.role_arn
}
