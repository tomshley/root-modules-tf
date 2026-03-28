variable "zone_id" {
  type        = string
  description = "Existing Cloudflare zone ID to accelerate."

  validation {
    condition     = trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.zone_id)))
    error_message = "zone_id must be a 32-character lowercase hex string."
  }
}

variable "performance_profile" {
  type        = string
  default     = "standard"
  description = "Website acceleration profile. Allowed values: standard, aggressive."

  validation {
    condition     = contains(["standard", "aggressive"], var.performance_profile)
    error_message = "performance_profile must be one of: standard, aggressive."
  }
}

variable "canonical_redirect" {
  type        = string
  default     = "none"
  description = "Canonical host redirect behavior. Allowed values: www-to-apex, apex-to-www, none."

  validation {
    condition     = contains(["www-to-apex", "apex-to-www", "none"], var.canonical_redirect)
    error_message = "canonical_redirect must be one of: www-to-apex, apex-to-www, none."
  }
}

variable "enable_bot_fight_mode" {
  type        = bool
  default     = false
  description = "Whether to enable Bot Fight Mode."
}

variable "edge_ttl_static" {
  type        = number
  default     = null
  description = "Optional override for edge TTL applied to static assets."

  validation {
    condition     = var.edge_ttl_static == null ? true : var.edge_ttl_static > 0
    error_message = "edge_ttl_static must be greater than 0 when set."
  }
}

variable "browser_ttl_static" {
  type        = number
  default     = null
  description = "Optional override for browser TTL applied to static assets."

  validation {
    condition     = var.browser_ttl_static == null ? true : var.browser_ttl_static > 0
    error_message = "browser_ttl_static must be greater than 0 when set."
  }
}

variable "edge_ttl_immutable" {
  type        = number
  default     = null
  description = "Optional override for edge TTL applied to immutable static assets."

  validation {
    condition     = var.edge_ttl_immutable == null ? true : var.edge_ttl_immutable > 0
    error_message = "edge_ttl_immutable must be greater than 0 when set."
  }
}

variable "browser_ttl_immutable" {
  type        = number
  default     = null
  description = "Optional override for browser TTL applied to immutable static assets."

  validation {
    condition     = var.browser_ttl_immutable == null ? true : var.browser_ttl_immutable > 0
    error_message = "browser_ttl_immutable must be greater than 0 when set."
  }
}

variable "enable_brotli" {
  type        = bool
  default     = null
  description = "Optional override for Brotli compression."
}

variable "enable_polish" {
  type        = string
  default     = null
  description = "Optional override for Polish. Allowed values: off, lossless, lossy."

  validation {
    condition     = var.enable_polish == null ? true : contains(["off", "lossless", "lossy"], var.enable_polish)
    error_message = "enable_polish must be one of: off, lossless, lossy when set."
  }
}

variable "enable_mirage" {
  type        = bool
  default     = null
  description = "Optional override for Mirage."
}

variable "enable_early_hints" {
  type        = bool
  default     = null
  description = "Optional override for Early Hints."
}

variable "hsts_max_age" {
  type        = number
  default     = 31536000
  description = "HSTS max-age value in seconds."

  validation {
    condition     = var.hsts_max_age >= 0
    error_message = "hsts_max_age must be greater than or equal to 0."
  }
}

variable "hsts_include_subdomains" {
  type        = bool
  default     = true
  description = "Whether HSTS should include subdomains."
}

variable "hsts_preload" {
  type        = bool
  default     = false
  description = "Whether to request HSTS preload behavior."
}
