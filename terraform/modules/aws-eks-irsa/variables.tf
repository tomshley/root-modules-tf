variable "project_name_prefix" {
  type = string
}

variable "role_name_suffix" {
  # Note on interpolation syntax below:
  #   - `description` is a narrative string that must show the literal template
  #     form of the generated name; `$${...}` escapes the interpolation so
  #     Terraform renders it verbatim in `terraform console` / `tf docs`.
  #   - `validation.error_message` is evaluated at plan time and deliberately
  #     interpolates the actual variable values so the operator sees the real
  #     name that exceeds the limit.
  type        = string
  description = "Suffix appended after '$${project_name_prefix}-irsa-' to form the IAM role name (literal template: '$${project_name_prefix}-irsa-$${role_name_suffix}'). For multi-tenant Aurora consumers this typically carries a tenant key (e.g. '<tenant>-db-app', '<tenant>-db-migrate')."

  # AWS IAM role name limit is 64 bytes. Cross-variable reference requires
  # Terraform 1.9+ (or OpenTofu 1.8+) — enforced via required_version in
  # provider.tf.
  validation {
    condition     = length("${var.project_name_prefix}-irsa-${var.role_name_suffix}") <= 64
    error_message = "Generated IAM role name ('${var.project_name_prefix}-irsa-${var.role_name_suffix}') exceeds the 64-byte AWS IAM role name limit. Shorten project_name_prefix or role_name_suffix."
  }
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN from EKS cluster module"
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL (without https://) from EKS cluster module"
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "policy_arns" {
  type        = list(string)
  description = "List of IAM policy ARNs to attach to the IRSA role"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
