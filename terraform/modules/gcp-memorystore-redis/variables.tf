variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for Memorystore resources."
}

variable "workload_name" {
  type        = string
  description = "Logical workload name."

  validation {
    condition     = can(regex("^[a-z](-?[a-z0-9])+$", var.workload_name))
    error_message = "workload_name must be lowercase alphanumeric with single hyphens, starting with a letter."
  }
}

variable "region" {
  type        = string
  description = "Memorystore region."
}

variable "authorized_network" {
  type        = string
  description = "VPC network ID authorized to access Memorystore."
}

variable "private_services_connection_id" {
  type        = string
  description = "Private service networking connection ID from gcp-network."
}

variable "tier" {
  type        = string
  default     = "STANDARD_HA"
  description = "Memorystore tier."

  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "tier must be BASIC or STANDARD_HA."
  }
}

variable "redis_contract" {
  type = object({
    mode                 = string
    auth_required        = bool
    tls_required         = bool
    reader_required      = bool
    persistence_required = bool
    availability         = string
  })
  default     = null
  nullable    = true
  description = "Optional provider-independent Redis contract. Null preserves the legacy inputs exactly."
}

variable "memory_size_gb" {
  type        = number
  default     = 1
  description = "Redis memory size in GiB."

  validation {
    condition     = var.memory_size_gb >= 1
    error_message = "memory_size_gb must be at least 1."
  }
}

variable "redis_version" {
  type        = string
  default     = "REDIS_7_2"
  description = "Memorystore Redis engine version."
}

variable "maintenance_window_day" {
  type        = string
  default     = "SUNDAY"
  description = "UTC weekday for maintenance."
}

variable "maintenance_window_hour" {
  type        = number
  default     = 5
  description = "UTC hour for maintenance."

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the Memorystore instance."
}
