resource "aws_iam_role" "irsa_role" {
  name = "${var.project_name_prefix}-irsa-${var.role_name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-irsa-${var.role_name_suffix}"
  })
}

resource "aws_iam_role_policy_attachment" "irsa_policies" {
  # NOTE: count-based enumeration (not for_each = toset(...)) is deliberate.
  # `for_each = toset(var.policy_arns)` requires set elements known at plan
  # time, which breaks when consumers derive policy_arns from another
  # module's outputs (the ARN strings are unknown until apply). count +
  # length() works here because length of a fixed-length list is known even
  # when individual elements are unknown. The tradeoff: reordering the list
  # churns attachments. Keep policy_arns ordering stable at the call site.
  #
  # CALLER CONTRACT: `length(var.policy_arns)` must be known at plan time.
  # A literal list of apply-unknown ARNs (e.g.
  #   policy_arns = [module.other.some_map[each.key]]
  # ) works — the list length is statically 1 even though the element is
  # unknown. A comprehension over an apply-unknown map (e.g.
  #   policy_arns = [for arn in module.other.unknown_map : arn]
  # ) does NOT work — Terraform rejects it at plan with
  # "count value depends on resource attributes that cannot be determined
  #  until apply". Iterate the known-keys input upstream and look up each
  # ARN by key, as in examples/aws-eks-aurora-multi-tenant/main.tf.
  count      = length(var.policy_arns)
  policy_arn = var.policy_arns[count.index]
  role       = aws_iam_role.irsa_role.name
}
