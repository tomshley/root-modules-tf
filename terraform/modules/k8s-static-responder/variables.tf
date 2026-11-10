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

variable "name" {
  type = string
  validation {
    condition     = try(length(var.name) <= 63 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)), false)
    error_message = "name must be a DNS-1035 label of at most 63 characters."
  }
}
variable "namespace" {
  type = string
  validation {
    condition     = try(length(var.namespace) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)), false)
    error_message = "namespace must be a DNS-1123 label of at most 63 characters."
  }
}
variable "files" {
  type = map(object({
    content      = string
    content_type = string
  }))
  nullable = false

  validation {
    condition     = alltrue([for path in keys(var.files) : startswith(path, "/") && !can(regex("[?#*]", path))])
    error_message = "File keys must begin with / and must not contain ?, # or *."
  }

  validation {
    condition     = alltrue([for path in keys(var.files) : !can(regex("//|/\\./|/\\.\\./|/\\.$|/\\.\\.$|%", path))])
    error_message = "File keys must not contain //, /./, /../, a trailing /. or /.., or %."
  }

  validation {
    condition     = alltrue([for path in keys(var.files) : !endswith(path, "/")])
    error_message = "File keys must not end in /, including / itself."
  }

  validation {
    condition     = alltrue([for path in keys(var.files) : !can(regex("\\p{Cc}", path))])
    error_message = "File keys must not contain control characters."
  }

  validation {
    condition = alltrue([for file in values(var.files) : try(
      file.content != null && trim(file.content_type, " ") != "" &&
      can(regex("^[\\x20-\\x7e]*$", file.content_type)) &&
      !startswith(file.content_type, " ") && !endswith(file.content_type, " "), false
    )])
    error_message = try(compact([for file in values(var.files) :
      !try(file.content != null && trim(file.content_type, " ") != "", false) ? "Files must have non-null content and a non-empty content_type." :
      !can(regex("^[\\x20-\\x7e]*$", file.content_type)) ? "content_type must contain only printable ASCII characters." :
      startswith(file.content_type, " ") || endswith(file.content_type, " ") ? "content_type must not have leading or trailing whitespace." : ""
    ])[0], "Files must have non-null content and a non-empty content_type.")
  }

  validation {
    condition     = length(base64encode(jsonencode(var.files))) <= 1228800
    error_message = "Files must fit within the 900 KiB ConfigMap budget."
  }
}
variable "image" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^.+@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must be pinned with a sha256 digest."
  }
}
variable "replicas" {
  type     = number
  default  = 2
  nullable = false
  validation {
    condition     = var.replicas >= 1 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a positive integer."
  }
}
variable "pdb_min_available" {
  type     = number
  default  = 1
  nullable = false
  validation {
    condition     = var.pdb_min_available >= 0 && floor(var.pdb_min_available) == var.pdb_min_available
    error_message = "pdb_min_available must be a non-negative integer."
  }
  validation {
    condition     = var.pdb_min_available < var.replicas
    error_message = "pdb_min_available must be smaller than replicas."
  }
}
variable "service_port" {
  type     = number
  default  = 80
  nullable = false
  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535 && floor(var.service_port) == var.service_port
    error_message = "service_port must be an integer between 1 and 65535."
  }
}
variable "resources_requests_cpu" {
  type    = string
  default = null
}
variable "resources_requests_memory" {
  type    = string
  default = null
}
variable "resources_limits_cpu" {
  type    = string
  default = null
}
variable "resources_limits_memory" {
  type    = string
  default = null
}
variable "labels" {
  type    = map(string)
  default = {}
}
