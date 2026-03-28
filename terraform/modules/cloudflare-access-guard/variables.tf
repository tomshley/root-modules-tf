variable "zone_id" {
  type        = string
  default     = null
  description = "Cloudflare zone ID for the protected hostname. Required when account_id is not set."

  validation {
    condition     = var.zone_id == null ? true : trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty when provided."
  }

  validation {
    condition     = var.zone_id == null ? true : can(regex("^[0-9a-f]{32}$", trimspace(var.zone_id)))
    error_message = "zone_id must be a 32-character lowercase hex string."
  }
}

variable "account_id" {
  type        = string
  default     = null
  description = "Cloudflare account ID that owns the Access policy. When set, the Access application is managed at account level. When null, zone_id is used instead."

  validation {
    condition     = var.account_id == null ? true : trimspace(var.account_id) != ""
    error_message = "account_id must be non-empty when provided."
  }

  validation {
    condition     = var.account_id == null ? true : can(regex("^[0-9a-f]{32}$", trimspace(var.account_id)))
    error_message = "account_id must be a 32-character lowercase hex string."
  }
}

variable "hostname" {
  type        = string
  description = "Hostname to protect with Cloudflare Access."

  validation {
    condition     = trimspace(var.hostname) != ""
    error_message = "hostname must be non-empty."
  }

  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(var.hostname)))
    error_message = "hostname must be a valid fully qualified domain name."
  }
}

variable "application_name" {
  type        = string
  description = "Display name for the Cloudflare Access application."

  validation {
    condition     = trimspace(var.application_name) != ""
    error_message = "application_name must be non-empty."
  }
}

variable "allowed_emails" {
  type        = list(string)
  default     = []
  description = "Explicit email addresses allowed by the Access policy."
}

variable "allowed_email_domains" {
  type        = list(string)
  default     = []
  description = "Email domains allowed by the Access policy."
}

variable "session_duration" {
  type        = string
  default     = "24h"
  description = "Session duration applied to the Access application."

  validation {
    condition     = trimspace(var.session_duration) != ""
    error_message = "session_duration must be non-empty."
  }

  validation {
    condition     = can(regex("^\\d+[mhd]$", trimspace(var.session_duration)))
    error_message = "session_duration must be a duration string such as 30m, 6h, 12h, 24h, or 7d."
  }
}
