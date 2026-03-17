variable "project_name_prefix" {
  type = string
}

variable "cluster_name" {
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

variable "karpenter_namespace" {
  type    = string
  default = "kube-system"
}

variable "karpenter_service_account_name" {
  type    = string
  default = "karpenter"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
