variable "project_id" {
  type        = string
  description = "GCP project ID — the workload identity pool, provider and service account are created in it, and project_roles are granted on it."

  validation {
    condition     = var.project_id != "" && var.project_id == trimspace(var.project_id)
    error_message = "project_id must be non-empty and carry no leading/trailing whitespace."
  }
}

variable "project_name_prefix" {
  type        = string
  description = "Project name prefix for resource naming."

  validation {
    condition     = var.project_name_prefix != "" && var.project_name_prefix == trimspace(var.project_name_prefix)
    error_message = "project_name_prefix must be non-empty and carry no leading/trailing whitespace."
  }
}

variable "role_name_suffix" {
  type        = string
  description = "Suffix for the service account ID (e.g. 'infrastructure-deploy', 'gitlab-deploy'). Final ID: {project_name_prefix}-ci-{role_name_suffix}."

  validation {
    condition     = var.role_name_suffix != "" && var.role_name_suffix == trimspace(var.role_name_suffix)
    error_message = "role_name_suffix must be non-empty and carry no leading/trailing whitespace."
  }

  # GCP service account IDs are 6-30 characters of lowercase letters, digits
  # and hyphens, starting with a letter; fail at plan time with the offending
  # lengths named rather than at apply with an opaque API error.
  validation {
    condition     = length(var.project_name_prefix) + length("-ci-") + length(var.role_name_suffix) >= 6
    error_message = "The service account ID {project_name_prefix}-ci-{role_name_suffix} is under GCP's 6-character minimum — lengthen one of the two inputs."
  }

  validation {
    condition     = length(var.project_name_prefix) + length("-ci-") + length(var.role_name_suffix) <= 30
    error_message = "The service account ID {project_name_prefix}-ci-{role_name_suffix} exceeds GCP's 30-character limit — shorten one of the two inputs."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", "${var.project_name_prefix}-ci-${var.role_name_suffix}"))
    error_message = "The service account ID {project_name_prefix}-ci-{role_name_suffix} must contain only lowercase letters, digits and hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "issuer_url" {
  type        = string
  default     = null
  description = "OIDC issuer URL of the CI platform. The workload identity provider is always created by this module — there is no existing-provider reuse path, so this is required."

  validation {
    condition     = var.issuer_url != null
    error_message = "issuer_url is required — this module always creates the workload identity provider and has no reuse path for an existing one."
  }
}

variable "audiences" {
  type        = list(string)
  default     = []
  description = "Allowed audiences for the OIDC provider. Empty applies the platform default, which on GCP is the issuer URL itself; entries given here are passed through verbatim."

  validation {
    condition = alltrue([
      for a in var.audiences : a != "" && a == trimspace(a)
    ])
    error_message = "audiences entries must be non-empty and carry no leading/trailing whitespace."
  }
}

variable "conditions" {
  type = list(object({
    claim  = string
    match  = string
    values = list(string)
  }))
  description = "Trust conditions in the ci-oidc-trust contract shape: claim, match = \"exact\" | \"wildcard\", values. Translated here as exact -> equality and wildcard -> RE2 .matches() on assertion.{claim} inside the provider's CEL attribute_condition. Validation lives in ci-oidc-trust."
}

variable "project_roles" {
  type        = list(string)
  default     = []
  description = "GCP project-level roles to grant to the service account on project_id (e.g. roles/editor). Trust only restricts who can impersonate it; these are what it can do."
}

variable "pool_id" {
  type        = string
  default     = null
  description = "Workload Identity Pool ID. Null derives {project_name_prefix}-ci-pool."

  validation {
    condition     = var.pool_id == null || can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.pool_id))
    error_message = "pool_id must be 4-32 characters of lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }

  validation {
    condition     = var.pool_id == null || !startswith(var.pool_id, "gcp-")
    error_message = "pool_id must not start with the reserved prefix 'gcp-'."
  }
}

variable "provider_id" {
  type        = string
  default     = null
  description = "Workload Identity Provider ID. Null derives {project_name_prefix}-ci-oidc."

  validation {
    condition     = var.provider_id == null || can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.provider_id))
    error_message = "provider_id must be 4-32 characters of lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }

  validation {
    condition     = var.provider_id == null || !startswith(var.provider_id, "gcp-")
    error_message = "provider_id must not start with the reserved prefix 'gcp-'."
  }
}

variable "attribute_mapping" {
  type        = map(string)
  default     = { "google.subject" = "assertion.sub" }
  nullable    = false
  description = "Mapping from Google attributes to OIDC assertion attributes on the workload identity provider. Must include 'google.subject'. Conditions always address raw token claims as assertion.{claim}, independent of this map."

  validation {
    condition     = contains(keys(var.attribute_mapping), "google.subject")
    error_message = "attribute_mapping must include a 'google.subject' key — it is the identity GCP binds pool membership to."
  }
}
