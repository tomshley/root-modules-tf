variable "project_name_prefix" {
  type = string
}

variable "role_name_suffix" {
  type = string
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
