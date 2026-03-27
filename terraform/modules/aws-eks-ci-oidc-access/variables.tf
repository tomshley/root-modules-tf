variable "project_name_prefix" {
  type        = string
  description = "Project name prefix for resource naming."
}

variable "role_name_suffix" {
  type        = string
  description = "Suffix for the IAM role name (e.g., 'github-deploy', 'gitlab-deploy')."
}

variable "oidc_provider_arn" {
  type        = string
  default     = null
  description = "Existing OIDC provider ARN. When null, creates a new provider. Only one provider per issuer URL is allowed per AWS account."

  validation {
    condition     = var.oidc_provider_arn == null || can(regex(":oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN containing ':oidc-provider/' (e.g., arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com)."
  }
}

variable "oidc_issuer_url" {
  type        = string
  default     = null
  description = "OIDC issuer URL of the CI platform. Required when creating a new provider."

  validation {
    condition     = var.oidc_issuer_url == null || can(regex("^https://", var.oidc_issuer_url))
    error_message = "oidc_issuer_url must start with 'https://'."
  }

}

variable "oidc_audiences" {
  type        = list(string)
  default     = ["sts.amazonaws.com"]
  description = "Allowed audiences for the OIDC provider."
}

variable "oidc_thumbprints" {
  type        = list(string)
  default     = []
  description = "TLS certificate thumbprints for the OIDC provider. Empty list is valid for providers using a trusted CA."
}

variable "trust_conditions" {
  type = list(object({
    test   = string
    claim  = string
    values = list(string)
  }))
  description = "IAM trust policy conditions. Each entry maps a claim from the OIDC token to allowed values. The claim is automatically prefixed with the OIDC issuer host."

  validation {
    condition = alltrue([
      for c in var.trust_conditions : contains([
        "StringEquals", "StringLike", "StringNotEquals", "StringNotLike",
        "ForAnyValue:StringLike", "ForAnyValue:StringEquals",
        "ForAllValues:StringLike", "ForAllValues:StringEquals"
      ], c.test)
    ])
    error_message = "trust_conditions test must be a valid IAM condition operator (StringEquals, StringLike, etc.)."
  }

  validation {
    condition     = length(var.trust_conditions) > 0
    error_message = "At least one trust_condition is required to restrict which CI tokens can assume this role."
  }

  validation {
    condition = length(var.trust_conditions) == length(distinct([
      for c in var.trust_conditions : "${c.test}:${c.claim}"
    ]))
    error_message = "trust_conditions must not contain duplicate test+claim combinations. Combine multiple allowed values into a single entry's values list."
  }
}

variable "policy_arns" {
  type        = list(string)
  default     = []
  description = "IAM policy ARNs to attach to the CI deploy role (e.g., ECR read, EKS describe)."
}

variable "eks_cluster_name" {
  type        = string
  description = "Target EKS cluster name for the access entry."
}

variable "eks_access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  description = "EKS access policy ARN for the access entry."
}

variable "eks_access_scope_type" {
  type        = string
  default     = "cluster"
  description = "Access scope type: 'cluster' or 'namespace'."

  validation {
    condition     = contains(["cluster", "namespace"], var.eks_access_scope_type)
    error_message = "eks_access_scope_type must be either 'cluster' or 'namespace'."
  }
}

variable "eks_access_scope_namespaces" {
  type        = list(string)
  default     = []
  description = "Kubernetes namespaces for namespace-scoped access. Required when eks_access_scope_type is 'namespace'."

}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources."
}
