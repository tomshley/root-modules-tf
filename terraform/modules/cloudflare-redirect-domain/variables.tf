variable "zone_name" {
  type        = string
  description = "Redirect source domain to create and configure in Cloudflare."

  validation {
    condition     = trimspace(var.zone_name) != ""
    error_message = "zone_name must be non-empty."
  }

  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(var.zone_name)))
    error_message = "zone_name must be a valid domain name."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID that will own the redirect source zone."

  validation {
    condition     = trimspace(var.account_id) != ""
    error_message = "account_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.account_id)))
    error_message = "account_id must be a 32-character lowercase hex string."
  }
}

variable "redirect_target" {
  type        = string
  description = "Final canonical destination host for the redirect."

  validation {
    condition     = trimspace(var.redirect_target) != ""
    error_message = "redirect_target must be non-empty."
  }

  validation {
    condition     = !can(regex("://", trimspace(var.redirect_target)))
    error_message = "redirect_target must be a host name only, not a full URL."
  }

  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(var.redirect_target)))
    error_message = "redirect_target must be a valid domain name."
  }
}

variable "redirect_code" {
  type        = number
  default     = 301
  description = "HTTP status code used for redirects. Allowed values: 301, 302."

  validation {
    condition     = contains([301, 302], var.redirect_code)
    error_message = "redirect_code must be one of: 301, 302."
  }
}

variable "preserve_path" {
  type        = bool
  default     = true
  description = "Whether the redirect should preserve the incoming request path."
}

variable "preserve_query" {
  type        = bool
  default     = true
  description = "Whether the redirect should preserve the incoming request query string."
}
