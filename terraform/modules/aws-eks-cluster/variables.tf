variable "project_name_prefix" {
  type = string
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Explicit — not derived internally."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group placement (from VPC module)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for EKS cluster networking (from VPC module)"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "public_access_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.public_access_cidrs) > 0
    error_message = "public_access_cidrs must be explicitly set."
  }

  description = "Explicit CIDR blocks allowed to access the EKS public API endpoint. Must be provided."
}

variable "authentication_mode" {
  type        = string
  default     = "API_AND_CONFIG_MAP"
  description = "EKS authentication mode. Must be API, API_AND_CONFIG_MAP, or CONFIG_MAP. API or API_AND_CONFIG_MAP is required for EKS access entries."

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, API_AND_CONFIG_MAP, CONFIG_MAP"
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  default     = true
  description = "Whether the cluster creator IAM principal gets admin access. ForceNew — must match the value used at cluster creation to avoid replacement."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
