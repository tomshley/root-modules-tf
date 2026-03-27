# Example: GitLab CI → AWS → EKS deploy access
#
# GitLab.com OIDC issuer: https://gitlab.com
# Self-managed GitLab: use your GitLab instance URL
# Claims used: sub (project_path + ref), aud (configurable)

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

module "gitlab_deploy" {
  source = "../../modules/aws-eks-ci-oidc-access"

  project_name_prefix = "my-project-staging"
  role_name_suffix    = "gitlab-deploy"
  eks_cluster_name    = "my-project-staging-eks-cluster"

  # GitLab CI OIDC (gitlab.com — use your instance URL for self-managed)
  oidc_issuer_url  = "https://gitlab.com"
  oidc_audiences   = ["https://gitlab.com"]
  oidc_thumbprints = [] # GitLab.com uses a trusted CA

  # Trust: only this project's main branch can assume the role
  # GitLab sub format: project_path:{group}/{project}:ref_type:branch:ref:{branch}
  trust_conditions = [
    {
      test   = "StringEquals"
      claim  = "aud"
      values = ["https://gitlab.com"]
    },
    {
      test   = "StringLike"
      claim  = "sub"
      values = ["project_path:my-group/my-app:ref_type:branch:ref:main"]
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
