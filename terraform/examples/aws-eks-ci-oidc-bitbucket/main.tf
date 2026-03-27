# Example: Bitbucket Pipelines → AWS → EKS deploy access
#
# Bitbucket OIDC issuer: https://api.bitbucket.org/2.0/workspaces/{WORKSPACE}/pipelines-config/identity/oidc
# Claims used: sub ({REPOSITORY_UUID}:{ENVIRONMENT_UUID}), aud (ari:cloud:bitbucket::workspace/{WORKSPACE_UUID})

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

# Replace these with your actual Bitbucket identifiers
locals {
  bitbucket_workspace      = "my-workspace"
  bitbucket_workspace_uuid = "{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
  bitbucket_repo_uuid      = "{11111111-2222-3333-4444-555555555555}"
  bitbucket_env_uuid       = "{66666666-7777-8888-9999-000000000000}"
}

module "bitbucket_deploy" {
  source = "../../modules/aws-eks-ci-oidc-access"

  project_name_prefix = "my-project-staging"
  role_name_suffix    = "bitbucket-deploy"
  eks_cluster_name    = "my-project-staging-eks-cluster"

  # Bitbucket Pipelines OIDC
  oidc_issuer_url  = "https://api.bitbucket.org/2.0/workspaces/${local.bitbucket_workspace}/pipelines-config/identity/oidc"
  oidc_audiences   = ["ari:cloud:bitbucket::workspace/${local.bitbucket_workspace_uuid}"]
  oidc_thumbprints = [] # Bitbucket uses a trusted CA

  # Trust: only this repo + environment can assume the role
  # Bitbucket sub format: {REPOSITORY_UUID}:{ENVIRONMENT_UUID}
  trust_conditions = [
    {
      test   = "StringEquals"
      claim  = "aud"
      values = ["ari:cloud:bitbucket::workspace/${local.bitbucket_workspace_uuid}"]
    },
    {
      test   = "StringEquals"
      claim  = "sub"
      values = ["${local.bitbucket_repo_uuid}:${local.bitbucket_env_uuid}"]
    }
  ]

  # Cluster-admin access (default)
  eks_access_scope_type = "cluster"

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
