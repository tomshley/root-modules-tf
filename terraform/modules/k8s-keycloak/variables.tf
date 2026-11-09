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

variable "public_hostname" {
  description = "Bare lowercase DNS name for Keycloak's public HTTPS URL; null preserves chart defaults."
  type        = string
  default     = null
  validation {
    condition     = var.public_hostname == null ? true : alltrue([length(var.public_hostname) <= 253, can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.public_hostname)), can(regex("[a-z]", reverse(split(".", var.public_hostname))[0]))])
    error_message = "public_hostname must be null or a bare lowercase DNS name, without a scheme, path, port or whitespace, and with a letter in the last label."
  }
}

variable "existing_secrets" {
  description = "Existing Kubernetes Secret names and keys for admin and database credentials; null preserves password handling."
  type = object({
    admin = optional(object({
      name         = string
      password_key = optional(string, "admin-password")
    }))
    db = optional(object({
      name         = string
      user_key     = optional(string, "db-user")
      password_key = optional(string, "db-password")
    }))
  })
  default = null
  validation {
    condition     = var.existing_secrets == null ? true : alltrue([for secret in [var.existing_secrets.admin, var.existing_secrets.db] : secret == null ? true : try(alltrue([length(secret.name) <= 253, can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", secret.name))]), false)])
    error_message = "existing_secrets names must be non-empty DNS-1123 Secret names of at most 253 characters."
  }
  validation {
    condition     = var.existing_secrets == null ? true : alltrue([for secret in [var.existing_secrets.admin, var.existing_secrets.db] : secret == null ? true : alltrue([for key, value in secret : try(alltrue([length(value) <= 253, !contains([".", ".."], value), !startswith(value, ".."), can(regex("^[-._a-zA-Z0-9]+$", value))]), false) if key != "name"])])
    error_message = "existing_secrets keys must be 1-253 characters matching ^[-._a-zA-Z0-9]+$, must not be . or .., and must not start with two dots."
  }
}

variable "release_name" {
  type    = string
  default = "keycloak"
}
variable "namespace" {
  type    = string
  default = "identity"
}
variable "create_namespace" {
  type    = bool
  default = true
}
variable "chart_version" {
  type    = string
  default = "24.4.2"
}
variable "image_tag" {
  type    = string
  default = null
}
variable "db_endpoint" { type = string }
variable "db_port" {
  type    = number
  default = 5432
}
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" {
  type      = string
  default   = null
  sensitive = true

  validation {
    condition     = var.db_password == null ? true : try(var.existing_secrets.db, null) == null
    error_message = "existing_secrets.db and db_password are mutually exclusive."
  }

  validation {
    condition     = var.db_password != null || try(var.existing_secrets.db, null) != null
    error_message = "Either db_password or existing_secrets.db must be provided."
  }
}
variable "admin_user" {
  type    = string
  default = "admin"
}
variable "admin_password" {
  type      = string
  default   = null
  sensitive = true

  validation {
    condition     = var.admin_password == null ? true : try(var.existing_secrets.admin, null) == null
    error_message = "existing_secrets.admin and admin_password are mutually exclusive."
  }

  validation {
    condition     = var.admin_password != null || try(var.existing_secrets.admin, null) != null
    error_message = "Either admin_password or existing_secrets.admin must be provided."
  }
}
variable "realm_json_path" {
  type    = string
  default = null
}
variable "service_port" {
  type    = number
  default = 80
}
variable "service_type" {
  type    = string
  default = "ClusterIP"
}
variable "replicas" {
  type    = number
  default = 1
}
variable "pod_annotations" {
  type    = map(string)
  default = {}
}
variable "labels" {
  type        = map(string)
  default     = {}
  description = "Provider-neutral labels applied to Kubernetes resources."
}
variable "db_secret_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations applied to the database credentials Secret by the provider adapter."
}
variable "admin_secret_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations applied to the admin credentials Secret by the provider adapter."
}
variable "resources_requests_cpu" {
  type    = string
  default = "500m"
}
variable "resources_requests_memory" {
  type    = string
  default = "512Mi"
}
variable "resources_limits_cpu" {
  type    = string
  default = "1000m"
}
variable "resources_limits_memory" {
  type    = string
  default = "1024Mi"
}
variable "helm_timeout" {
  type    = number
  default = 600
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
  validation {
    condition     = var.public_hostname == null ? true : alltrue([for values in var.extra_helm_values : can(yamldecode(values))])
    error_message = "When public_hostname is set, every extra_helm_values entry must decode as a single YAML document."
  }
  validation {
    condition     = var.public_hostname == null ? true : alltrue([for values in var.extra_helm_values : !try(contains(keys(yamldecode(values)), "extraEnvVars"), false)])
    error_message = "public_hostname and top-level extraEnvVars in extra_helm_values are mutually exclusive because Helm replaces lists."
  }
}
