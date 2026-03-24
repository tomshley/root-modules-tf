variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for all resources created by this module"
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
  default     = "event_journal"
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

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
