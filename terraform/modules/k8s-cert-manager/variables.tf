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

variable "namespace" {
  type        = string
  default     = "cert-manager"
  description = "Namespace for cert-manager and the existing DNS credential Secret."

  validation {
    condition     = try(length(var.namespace) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)), false)
    error_message = "namespace must be a non-null DNS-1123 label of at most 63 characters."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Allow Helm to create the namespace when installing cert-manager."

  validation {
    condition     = var.create_namespace != null
    error_message = "create_namespace must be non-null."
  }
}

variable "chart_version" {
  type        = string
  description = "Exact official chart version matching the module's image digest set."

  validation {
    condition     = var.chart_version == "v1.21.3"
    error_message = "chart_version must be v1.21.3, the version supported by the pinned image digests."
  }
}

variable "issuer" {
  type = object({
    name        = string
    acme_email  = string
    acme_server = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
    dns01 = object({
      provider               = string
      credential_secret_name = string
      credential_secret_key  = optional(string, "api-token")
    })
  })
  description = "One ACME ClusterIssuer using an existing Cloudflare API-token Secret."

  validation {
    condition     = var.issuer != null
    error_message = "issuer must be non-null."
  }

  validation {
    condition     = var.issuer == null ? true : try(length(var.issuer.name) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.issuer.name)), false)
    error_message = "issuer.name must be a non-null DNS-1123 label of at most 63 characters."
  }

  validation {
    condition     = var.issuer == null ? true : try(length(var.issuer.acme_email) <= 254 && length(split("@", var.issuer.acme_email)[0]) <= 64 && !can(regex("^[0-9]+$", reverse(split(".", split("@", var.issuer.acme_email)[1]))[0])) && can(regex("^[A-Za-z0-9_+-]+(\\.[A-Za-z0-9_+-]+)*@[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$", var.issuer.acme_email)), false)
    error_message = "issuer.acme_email must be a non-null email address with a supported ASCII dot-atom local part of at most 64 characters and a dotted domain, at most 254 characters."
  }

  validation {
    condition     = var.issuer == null ? true : can(regex("^https://[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*(:[0-9]{1,5})?([/?][^\\s\\p{Z}\\p{Cc}#]*)?$", var.issuer.acme_server)) && try(tonumber(regex("^https://[^/:?]+:([0-9]+)([/?]|$)", var.issuer.acme_server)[0]) >= 1 && tonumber(regex("^https://[^/:?]+:([0-9]+)([/?]|$)", var.issuer.acme_server)[0]) <= 65535, true) && !can(regex("^[0-9]+$", reverse(split(".", regex("^https://([^/:?]+)", var.issuer.acme_server)[0]))[0])) && length(regexall("%", replace(var.issuer.acme_server, "/%[0-9A-Fa-f]{2}/", ""))) == 0
    error_message = "issuer.acme_server must be an HTTPS URL with a DNS hostname, an optional port from 1 to 65535, well-formed percent escapes, and no credentials, whitespace or fragment."
  }

  validation {
    condition     = var.issuer == null ? true : var.issuer.dns01 != null
    error_message = "issuer.dns01 must be non-null."
  }

  validation {
    condition     = try(var.issuer.dns01 == null, true) ? true : var.issuer.dns01.provider == "cloudflare"
    error_message = "issuer.dns01.provider must be cloudflare."
  }

  validation {
    condition = try(var.issuer.dns01 == null, true) ? true : try(
      length(var.issuer.dns01.credential_secret_name) <= 253 && alltrue([
        for label in split(".", var.issuer.dns01.credential_secret_name) :
        length(label) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", label))
      ]), false
    )
    error_message = "issuer.dns01.credential_secret_name must be a non-null DNS-1123 subdomain of at most 253 characters, with labels of at most 63 characters."
  }

  validation {
    condition     = try(var.issuer.dns01.credential_secret_name != "cm-acme-${substr(sha256(var.issuer.name), 0, 24)}", true)
    error_message = "issuer.dns01.credential_secret_name must differ from the generated ACME account-key Secret name."
  }

  validation {
    condition     = try(var.issuer.dns01.credential_secret_name != "cert-manager-webhook-ca", true)
    error_message = "issuer.dns01.credential_secret_name must differ from the cert-manager webhook CA Secret name."
  }

  validation {
    condition = try(var.issuer.dns01 == null, true) ? true : try(
      length(var.issuer.dns01.credential_secret_key) <= 253 &&
      can(regex("^[A-Za-z0-9._-]+$", var.issuer.dns01.credential_secret_key)) &&
      var.issuer.dns01.credential_secret_key != "." && !startswith(var.issuer.dns01.credential_secret_key, ".."), false
    )
    error_message = "issuer.dns01.credential_secret_key must contain 1 to 253 letters, digits, dots, underscores or hyphens, must not be a single dot, and must not start with two dots."
  }
}

variable "extra_helm_values" {
  type        = list(string)
  default     = []
  description = "Additional YAML mappings appended after generated cert-manager chart values."

  validation {
    condition     = try(alltrue([for value in var.extra_helm_values : can(keys(yamldecode(value)))]), false)
    error_message = "extra_helm_values must be a non-null list of non-null YAML mappings."
  }
}
