# AWS implementation of the ci-oidc-trust contract: registers (or reuses)
# the IAM OIDC provider for a CI platform and mints a federated deploy role
# from the normalized trust object. Carries NO Kubernetes coupling — this is
# the role for pipelines that exist before, or independent of, any cluster
# (infrastructure provisioning being the canonical case). Cluster-binding
# compositions layer on top of this module.

locals {
  create_oidc_provider = var.oidc_provider_arn == null

  # When reusing a provider, the issuer is authoritative in its ARN:
  # arn:aws:iam::{account}:oidc-provider/{issuer-host-and-path}. Split on
  # "oidc-provider/" so multi-segment issuer paths survive.
  issuer_host_from_arn = local.create_oidc_provider ? null : element(split(":oidc-provider/", var.oidc_provider_arn), 1)
  effective_issuer_url = var.issuer_url != null ? var.issuer_url : (
    local.issuer_host_from_arn != null ? "https://${local.issuer_host_from_arn}" : null
  )
}

module "trust" {
  source = "../ci-oidc-trust"

  issuer_url = local.effective_issuer_url
  audiences  = var.audiences
  conditions = var.conditions
}

locals {
  # Contract translation: exact -> StringEquals, wildcard -> StringLike,
  # each claim referenced as {issuer_host}:{claim}. The contract's duplicate
  # claim+match guard (in ci-oidc-trust) is what makes these merges safe.
  string_equals_conditions = {
    for c in module.trust.exact_conditions : "${module.trust.issuer_host}:${c.claim}" => c.values
  }
  string_like_conditions = {
    for c in module.trust.wildcard_conditions : "${module.trust.issuer_host}:${c.claim}" => c.values
  }

  trust_policy_conditions = merge(
    length(local.string_equals_conditions) > 0 ? { StringEquals = local.string_equals_conditions } : {},
    length(local.string_like_conditions) > 0 ? { StringLike = local.string_like_conditions } : {},
  )

  oidc_provider_arn = local.create_oidc_provider ? aws_iam_openid_connect_provider.ci[0].arn : var.oidc_provider_arn
  role_name         = "${var.project_name_prefix}-ci-${var.role_name_suffix}"
}

resource "aws_iam_openid_connect_provider" "ci" {
  count = local.create_oidc_provider ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.issuer_url != null
      error_message = "issuer_url is required when creating a new OIDC provider (oidc_provider_arn = null)."
    }
  }

  url             = module.trust.issuer_url
  client_id_list  = var.audiences
  thumbprint_list = var.thumbprints

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-ci-oidc-${var.role_name_suffix}"
  })
}

resource "aws_iam_role" "ci" {
  name                 = local.role_name
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = local.trust_policy_conditions
      }
    ]
  })

  tags = merge(var.tags, {
    Name = local.role_name
  })
}

resource "aws_iam_role_policy_attachment" "ci" {
  count      = length(var.policy_arns)
  policy_arn = var.policy_arns[count.index]
  role       = aws_iam_role.ci.name
}
