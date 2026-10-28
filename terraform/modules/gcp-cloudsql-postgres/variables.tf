# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for Cloud SQL resources."
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
  description = "Cloud SQL region."
}

variable "workload_contract" {
  type = object({
    purpose                = string
    reader_required        = bool
    tls_required           = bool
    retention_days         = number
    authoritative          = bool
    projection_rebuildable = bool
  })
  default = {
    purpose                = "generic"
    reader_required        = false
    tls_required           = true
    retention_days         = 7
    authoritative          = true
    projection_rebuildable = false
  }
  nullable    = false
  description = "Provider-independent PostgreSQL workload contract consumed by the Cloud SQL adapter."

  validation {
    condition     = var.workload_contract.retention_days <= 7
    error_message = "Cloud SQL adapter retention_days must be at most seven elapsed days; longer point-in-time recovery windows are not supported by this adapter."
  }
}

variable "private_network_id" {
  type        = string
  description = "VPC network ID with private services access configured."
}

variable "private_services_connection_id" {
  type        = string
  description = "Private service networking connection ID from gcp-network."
}

variable "database_name" {
  type        = string
  description = "Default PostgreSQL database name."
}

variable "master_username" {
  type        = string
  default     = "postgres"
  description = "Name of the PostgreSQL master user."

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must be a valid PostgreSQL identifier."
  }
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_16"
  description = "Cloud SQL PostgreSQL engine version."

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  type        = string
  default     = "db-custom-2-7680"
  description = "Machine tier for primary and read replicas."
}

variable "edition" {
  type        = string
  default     = null
  description = "Cloud SQL edition for the primary instance — ENTERPRISE or ENTERPRISE_PLUS. Left null on purpose: an unset edition lets the API choose, which is the long-standing behavior, so an existing consumer whose instance was created under the API default re-plans to zero changes — pinning a default here would try to change the edition of a live instance. Recent PostgreSQL versions resolve an unset edition to ENTERPRISE_PLUS, which rejects db-custom tiers at apply time; set this explicitly to pair the edition with the tier family it accepts."

  validation {
    condition     = var.edition == null || contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS when set."
  }
}

variable "availability_type" {
  type        = string
  default     = "ZONAL"
  description = "Cloud SQL availability type for the primary instance."

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "reader_instance_count" {
  type        = number
  default     = 0
  description = "Number of read replicas. Zero retains a writer-only endpoint contract."

  validation {
    condition     = var.reader_instance_count >= 0 && var.reader_instance_count <= 15
    error_message = "reader_instance_count must be between 0 and 15."
  }
}

variable "port" {
  type        = number
  default     = 5432
  description = "PostgreSQL TCP port."

  validation {
    condition     = var.port > 0 && var.port < 65536
    error_message = "port must be a valid TCP port."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Enable deletion protection for the primary instance."
}

variable "backup_retained_backups" {
  type        = number
  default     = 7
  description = "Number of retained automated backups. This is a backup count, not the elapsed-day point-in-time recovery contract."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to Cloud SQL instances."
}
