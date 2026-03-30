variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  type        = string
}

variable "karpenter_controller_role_arn" {
  description = "IAM role ARN for the Karpenter controller (from aws-eks-karpenter-prereqs)"
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for spot interruption events (from aws-eks-karpenter-prereqs)"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.1.0"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace for Karpenter controller"
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account_name" {
  description = "Kubernetes service account name for Karpenter controller"
  type        = string
  default     = "karpenter"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
