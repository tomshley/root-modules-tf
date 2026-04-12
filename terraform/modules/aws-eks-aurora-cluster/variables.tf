variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for all resources created by this module"
}

variable "workload_name" {
  type        = string
  description = "Logical workload name used in all resource naming (e.g. event-journal, readmodel)"

  validation {
    condition     = can(regex("^[a-z](-?[a-z0-9])+$", var.workload_name))
    error_message = "workload_name must be lowercase alphanumeric with single hyphens, starting with a letter, minimum 2 characters."
  }
}

variable "workload_preset" {
  type        = string
  default     = "generic"
  description = "Tuning preset. Allowed values: event-store, read-store, generic."

  validation {
    condition     = contains(["event-store", "read-store", "generic"], var.workload_preset)
    error_message = "workload_preset must be one of: event-store, read-store, generic."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group placement"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Aurora DB subnet group placement"
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to access the Aurora cluster on the configured port"
}

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "Aurora PostgreSQL engine version (major version must be 13-17)"
}

variable "database_name" {
  type        = string
  description = "Name of the default database created in the cluster"
}

variable "master_username" {
  type        = string
  default     = "postgres"
  description = "Master username for the Aurora cluster"
}

variable "min_capacity" {
  type        = number
  default     = 0.5
  description = "Minimum ACU capacity for Serverless v2 scaling"
}

variable "max_capacity" {
  type        = number
  default     = 2
  description = "Maximum ACU capacity for Serverless v2 scaling"
}

variable "port" {
  type        = number
  default     = 5432
  description = "PostgreSQL port for the Aurora cluster"
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Enable deletion protection on the Aurora cluster"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip final snapshot when destroying the cluster"
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated backups"
}

variable "reader_instance_count" {
  type        = number
  default     = 0
  description = "Number of Aurora reader instances to create (0 = writer only)"

  validation {
    condition     = var.reader_instance_count >= 0 && var.reader_instance_count <= 15
    error_message = "reader_instance_count must be between 0 and 15."
  }
}

# --- Tunable parameter overrides (nullable, preset value used when null) ---

variable "max_connections" {
  type        = string
  default     = null
  description = "Optional override for max_connections parameter."
}

variable "wal_buffers" {
  type        = string
  default     = null
  description = "Optional override for wal_buffers parameter (8 kB units)."
}

variable "random_page_cost" {
  type        = string
  default     = null
  description = "Optional override for random_page_cost parameter."
}

variable "work_mem" {
  type        = string
  default     = null
  description = "Optional override for work_mem parameter (kB)."
}

variable "security_group_description" {
  type        = string
  default     = null
  description = "Override for the security group description (ForceNew). Defaults to auto-generated from workload_name. Migrating consumers should pass the old literal to avoid recreation."
}

variable "parameter_group_description" {
  type        = string
  default     = null
  description = "Override for the cluster parameter group description (ForceNew). Defaults to auto-generated from workload_name and preset. Migrating consumers should pass the old literal to avoid recreation."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
