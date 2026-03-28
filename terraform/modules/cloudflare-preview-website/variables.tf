variable "zone_id" {
  type        = string
  description = "Existing Cloudflare zone ID where the preview hostname will be published."

  validation {
    condition     = trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.zone_id)))
    error_message = "zone_id must be a 32-character lowercase hex string."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the preview tunnel."

  validation {
    condition     = trimspace(var.account_id) != ""
    error_message = "account_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.account_id)))
    error_message = "account_id must be a 32-character lowercase hex string."
  }
}

variable "tunnel_name" {
  type        = string
  description = "Display name for the Cloudflare Tunnel."

  validation {
    condition     = trimspace(var.tunnel_name) != ""
    error_message = "tunnel_name must be non-empty."
  }
}

variable "tunnel_secret" {
  type        = string
  sensitive   = true
  description = "Caller-provided tunnel secret for the Cloudflare Tunnel."

  validation {
    condition     = trimspace(var.tunnel_secret) != ""
    error_message = "tunnel_secret must be non-empty."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", trimspace(var.tunnel_secret)))
    error_message = "tunnel_secret must be a Base64 encoding of exactly 32 bytes (44 characters) after trimming surrounding whitespace."
  }
}

variable "preview_hostname" {
  type        = string
  description = "Preview hostname to publish through the tunnel."

  validation {
    condition     = trimspace(var.preview_hostname) != ""
    error_message = "preview_hostname must be non-empty."
  }

  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(var.preview_hostname)))
    error_message = "preview_hostname must be a valid fully qualified domain name."
  }
}

variable "origin_url" {
  type        = string
  description = "Origin URL that cloudflared should proxy to for the preview hostname."

  validation {
    condition     = trimspace(var.origin_url) != ""
    error_message = "origin_url must be non-empty."
  }

  validation {
    condition     = can(regex("^https?://", trimspace(var.origin_url)))
    error_message = "origin_url must start with http:// or https://."
  }
}
