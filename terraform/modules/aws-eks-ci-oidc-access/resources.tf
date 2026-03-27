locals {
  # Use existing provider or create new one
  create_oidc_provider = var.oidc_provider_arn == null
  oidc_provider_arn    = var.oidc_provider_arn != null ? var.oidc_provider_arn : aws_iam_openid_connect_provider.ci_oidc[0].arn

  # Extract issuer host from existing provider ARN if needed
  # ARN format: arn:aws:iam::{account}:oidc-provider/{issuer-host-and-path}
  # Must split on "oidc-provider/" to handle multi-segment paths (e.g., Bitbucket)
  oidc_provider_host = local.create_oidc_provider ? replace(coalesce(var.oidc_issuer_url, "https://MISSING"), "https://", "") : (
    element(split(":oidc-provider/", local.oidc_provider_arn), 1)
  )

  # Group trust conditions by test operator, then merge claim maps per operator.
  # Produces: { "StringEquals" = { "host:aud" = [...], "host:sub" = [...] }, "StringLike" = { ... } }
  conditions_grouped = {
    for cond in var.trust_conditions : cond.test => {
      "${local.oidc_provider_host}:${cond.claim}" = cond.values
    }...
  }

  trust_policy_conditions = {
    for test, claim_maps in local.conditions_grouped : test => merge(claim_maps...)
  }
}

resource "aws_iam_openid_connect_provider" "ci_oidc" {
  count = local.create_oidc_provider ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.oidc_issuer_url != null
      error_message = "oidc_issuer_url is required when creating a new OIDC provider (when oidc_provider_arn is null)."
    }
  }

  url             = var.oidc_issuer_url
  client_id_list  = var.oidc_audiences
  thumbprint_list = var.oidc_thumbprints

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-ci-oidc-${var.role_name_suffix}"
  })
}

resource "aws_iam_role" "ci_deploy" {
  name = "${var.project_name_prefix}-ci-deploy-${var.role_name_suffix}"

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
    Name = "${var.project_name_prefix}-ci-deploy-${var.role_name_suffix}"
  })
}

resource "aws_iam_role_policy_attachment" "ci_deploy" {
  count      = length(var.policy_arns)
  policy_arn = var.policy_arns[count.index]
  role       = aws_iam_role.ci_deploy.name
}

resource "aws_eks_access_entry" "ci_deploy" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.ci_deploy.arn
  type          = "STANDARD"

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-ci-deploy-${var.role_name_suffix}"
  })
}

resource "aws_eks_access_policy_association" "ci_deploy" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.ci_deploy.arn
  policy_arn    = var.eks_access_policy_arn

  lifecycle {
    precondition {
      condition     = var.eks_access_scope_type == "cluster" || length(var.eks_access_scope_namespaces) > 0
      error_message = "eks_access_scope_namespaces must be non-empty when eks_access_scope_type is 'namespace'."
    }
  }

  access_scope {
    type       = var.eks_access_scope_type
    namespaces = var.eks_access_scope_type == "namespace" ? var.eks_access_scope_namespaces : null
  }

  depends_on = [aws_eks_access_entry.ci_deploy]
}
