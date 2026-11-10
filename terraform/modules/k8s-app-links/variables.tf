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

variable "apps" {
  type = list(object({
    name = string
    ios = optional(object({
      team_id   = string
      bundle_id = string
      paths     = list(string)
    }))
    android = optional(object({
      package_name        = string
      sha256_fingerprints = list(string)
    }))
  }))
  nullable = false

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios != null || app.android != null, false)])
    error_message = "Each app must declare at least one platform."
  }

  validation {
    condition     = alltrue([for app in var.apps : app == null ? true : try(trimspace(app.name) != "" && app.name == trimspace(app.name), false)])
    error_message = "App name must be non-null, non-empty and have no leading or trailing whitespace."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : can(regex("^[A-Z0-9]{10}$", app.ios.team_id))])
    error_message = "iOS team_id must be ten uppercase letters or digits."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : try(trimspace(app.ios.bundle_id) != "", false)])
    error_message = "iOS bundle_id must be non-empty."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : try(app.ios.bundle_id == trimspace(app.ios.bundle_id) && !can(regex("[\\s\\p{Z}\\p{Cc}]", app.ios.bundle_id)), false)])
    error_message = "bundle_id must be trimmed and must not contain whitespace or control characters."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : try(length(app.ios.paths) > 0, false)])
    error_message = "iOS paths must be a non-empty list."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : try(alltrue([for path in app.ios.paths : startswith(path, "/")]), false)])
    error_message = "Each iOS path must begin with /."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.ios, null) == null ? true : try(alltrue([for path in app.ios.paths : !can(regex("[?#\\s\\p{Z}\\p{Cc}]", path))]), false)])
    error_message = "iOS paths must not contain ?, #, whitespace or control characters."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.android, null) == null ? true : try(trimspace(app.android.package_name) != "", false)])
    error_message = "Android package_name must be non-empty."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.android, null) == null ? true : try(app.android.package_name == trimspace(app.android.package_name) && !can(regex("[\\s\\p{Z}\\p{Cc}]", app.android.package_name)), false)])
    error_message = "package_name must be trimmed and must not contain whitespace or control characters."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.android, null) == null ? true : try(length(app.android.sha256_fingerprints) > 0, false)])
    error_message = "Android sha256_fingerprints must be a non-empty list."
  }

  validation {
    condition     = alltrue([for app in var.apps : try(app.android, null) == null ? true : try(alltrue([for fingerprint in app.android.sha256_fingerprints : can(regex("^([0-9A-F]{2}:){31}[0-9A-F]{2}$", fingerprint))]), false)])
    error_message = "Android fingerprints must be uppercase colon-separated SHA-256."
  }

  validation {
    condition = (
      length(distinct([for app in var.apps : app.ios.bundle_id if try(app.ios, null) != null])) ==
      length([for app in var.apps : app.ios.bundle_id if try(app.ios, null) != null])
    )
    error_message = "iOS bundle identifiers must be unique."
  }

  validation {
    condition = (
      length(distinct([for app in var.apps : app.android.package_name if try(app.android, null) != null])) ==
      length([for app in var.apps : app.android.package_name if try(app.android, null) != null])
    )
    error_message = "Android package identifiers must be unique."
  }
}
