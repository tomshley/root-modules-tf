# Example: GitHub Actions → AWS → EKS deploy access (reusing existing OIDC provider)
#
# This example shows how to use an existing OIDC provider that was created
# by another module (e.g., aws-eks-cluster) or by a different CI setup.

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

# Assume the OIDC provider already exists (e.g., from EKS cluster module)
# In practice, you would pass this as a variable or data source
locals {
  existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

module "github_deploy" {
  source = "../../modules/aws-eks-ci-oidc-access"

  project_name_prefix = "my-project-staging"
  role_name_suffix    = "github-deploy"
  eks_cluster_name    = "my-project-staging-eks-cluster"

  # Use existing OIDC provider
  oidc_provider_arn = local.existing_oidc_provider_arn
  oidc_issuer_url   = null # Not needed when using existing provider

  # Trust: only this repo's main branch can assume the role
  trust_conditions = [
    {
      test   = "StringEquals"
      claim  = "aud"
      values = ["sts.amazonaws.com"]
    },
    {
      test   = "StringLike"
      claim  = "sub"
      values = ["repo:my-org/my-app:ref:refs/heads/main"]
    }
  ]

  # Namespace-scoped access example
  eks_access_policy_arn       = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
  eks_access_scope_type       = "namespace"
  eks_access_scope_namespaces = ["my-app-staging"]

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
