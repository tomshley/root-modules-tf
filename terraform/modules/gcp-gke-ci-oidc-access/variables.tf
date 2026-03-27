variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "pool_id" {
  type        = string
  description = "Workload Identity Pool ID (e.g., 'github-ci-pool')."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.pool_id))
    error_message = "pool_id must be 4-32 lowercase alphanumeric characters or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "pool_display_name" {
  type        = string
  default     = null
  description = "Display name for the Workload Identity Pool. Defaults to pool_id."
}

variable "provider_id" {
  type        = string
  description = "Workload Identity Provider ID (e.g., 'github-oidc')."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.provider_id))
    error_message = "provider_id must be 4-32 lowercase alphanumeric characters or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "provider_display_name" {
  type        = string
  default     = null
  description = "Display name for the Workload Identity Provider. Defaults to provider_id."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the CI platform (e.g., https://token.actions.githubusercontent.com)."

  validation {
    condition     = can(regex("^https://", var.oidc_issuer_url))
    error_message = "oidc_issuer_url must start with 'https://'."
  }
}

variable "oidc_allowed_audiences" {
  type        = list(string)
  default     = []
  description = "Allowed audiences for the OIDC provider. When empty, the pool's default audience is used."
}

variable "attribute_mapping" {
  type        = map(string)
  description = "Mapping from Google attributes to OIDC assertion attributes. Must include 'google.subject'."

  validation {
    condition     = contains(keys(var.attribute_mapping), "google.subject")
    error_message = "attribute_mapping must include a 'google.subject' key."
  }
}

variable "attribute_condition" {
  type        = string
  description = "CEL expression to restrict which OIDC tokens are accepted (e.g., assertion.repository == 'org/repo'). Required — provides defense-in-depth in addition to the explicit IAM binding scope."

  validation {
    condition     = trimspace(var.attribute_condition) != ""
    error_message = "attribute_condition must be a non-empty CEL expression to restrict which tokens can impersonate the service account."
  }
}

variable "service_account_id" {
  type        = string
  description = "Service account ID to create (e.g., 'github-ci-deploy')."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "service_account_id must be 6-30 lowercase alphanumeric characters or hyphens."
  }
}

variable "service_account_display_name" {
  type        = string
  default     = null
  description = "Display name for the service account. Defaults to service_account_id."
}

variable "repository_attribute" {
  type        = string
  default     = "attribute.repository"
  description = "Mapped attribute name for the IAM binding principal set (e.g., 'attribute.repository' for GitHub, 'attribute.namespace_path' for GitLab, 'attribute.repository_uuid' for Bitbucket)."

  validation {
    condition     = startswith(var.repository_attribute, "attribute.")
    error_message = "repository_attribute must start with 'attribute.' (e.g., 'attribute.repository')."
  }
}

variable "repository_selector" {
  type        = string
  description = "Repository or namespace selector for explicit IAM binding scope (e.g., 'my-org/my-repo' for GitHub, 'my-group' for GitLab group, UUID for Bitbucket). This creates a narrow, explicit IAM binding instead of relying solely on provider attribute_condition."

  validation {
    condition     = trimspace(var.repository_selector) != ""
    error_message = "repository_selector must be a non-empty string because it defines the explicit IAM binding scope for service account impersonation."
  }
}

variable "project_roles" {
  type        = list(string)
  description = "GCP project-level roles to grant to the service account (e.g., roles/container.developer)."

  validation {
    condition     = length(var.project_roles) > 0
    error_message = "At least one project_role is required."
  }
}

