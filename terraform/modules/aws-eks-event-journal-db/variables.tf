variable "project_name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  type = list(string)
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "database_name" {
  type    = string
  default = "event_journal"
}

variable "master_username" {
  type    = string
  default = "postgres"
}

variable "min_capacity" {
  type    = number
  default = 0.5
}

variable "max_capacity" {
  type    = number
  default = 2
}

variable "port" {
  type    = number
  default = 5432
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
