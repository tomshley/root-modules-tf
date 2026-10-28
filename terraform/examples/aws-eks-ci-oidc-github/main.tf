# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Example: GitHub Actions → AWS → EKS deploy access
#
# GitHub Actions OIDC issuer: https://token.actions.githubusercontent.com
# Claims used: sub (repo + ref), aud (sts.amazonaws.com)

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

module "github_deploy" {
  source = "../../modules/aws-eks-ci-oidc-access"

  project_name_prefix = "my-project-staging"
  role_name_suffix    = "github-deploy"
  eks_cluster_name    = "my-project-staging-eks-cluster"

  # GitHub Actions OIDC
  oidc_issuer_url  = "https://token.actions.githubusercontent.com"
  oidc_audiences   = ["sts.amazonaws.com"]
  oidc_thumbprints = [] # GitHub uses a trusted CA

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

  # Cluster-admin access (default)
  eks_access_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  eks_access_scope_type = "cluster"

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
