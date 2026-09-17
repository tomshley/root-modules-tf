variable "zone_id" {
  type        = string
  default     = null
  description = "Existing Cloudflare zone ID where preview_hostname is published. Required when preview_hostname is set; hostnames entries carry their own zone_id."

  validation {
    condition     = var.zone_id == null || trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty when supplied."
  }

  validation {
    condition     = var.zone_id == null || can(regex("^[0-9a-f]{32}$", trimspace(var.zone_id)))
    error_message = "zone_id must be a 32-character lowercase hex string."
  }

  validation {
    condition     = var.preview_hostname == null || var.zone_id != null
    error_message = "zone_id is required when preview_hostname is set."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the tunnel."

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
  default     = null
  description = "Hostname to publish through the tunnel. At least one of preview_hostname or hostnames must be supplied."

  validation {
    condition     = var.preview_hostname == null || trimspace(var.preview_hostname) != ""
    error_message = "preview_hostname must be non-empty when supplied."
  }

  validation {
    condition     = var.preview_hostname == null || can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(var.preview_hostname)))
    error_message = "preview_hostname must be a valid fully qualified domain name."
  }
}

variable "origin_url" {
  type        = string
  default     = null
  description = "Origin URL that cloudflared proxies to. Required when preview_hostname is set; the default origin for hostnames entries that omit their own."

  validation {
    condition     = var.origin_url == null || trimspace(var.origin_url) != ""
    error_message = "origin_url must be non-empty when supplied."
  }

  validation {
    condition     = var.origin_url == null || can(regex("^https?://", trimspace(var.origin_url)))
    error_message = "origin_url must start with http:// or https://."
  }

  validation {
    condition     = var.preview_hostname == null || var.origin_url != null
    error_message = "origin_url is required when preview_hostname is set."
  }
}

variable "hostnames" {
  type = list(object({
    hostname   = string
    zone_id    = string
    origin_url = optional(string)
    proxied    = optional(bool, true)
  }))
  default     = []
  nullable    = false
  description = "Additional hostnames to publish through the same tunnel. Entries may live in different zones and may override the default origin_url per hostname."

  validation {
    condition     = length(var.hostnames) > 0 || var.preview_hostname != null
    error_message = "At least one of preview_hostname or hostnames must be supplied."
  }

  validation {
    condition = alltrue([
      for h in var.hostnames : can(regex("^[0-9a-f]{32}$", trimspace(h.zone_id)))
    ])
    error_message = "Every hostnames entry zone_id must be a 32-character lowercase hex string."
  }

  validation {
    condition = alltrue([
      for h in var.hostnames : can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(h.hostname)))
    ])
    error_message = "Every hostnames entry hostname must be a valid fully qualified domain name."
  }

  validation {
    condition = alltrue([
      for h in var.hostnames : h.origin_url != null || var.origin_url != null
    ])
    error_message = "A hostnames entry without its own origin_url requires origin_url to be set."
  }

  validation {
    condition = length(distinct(concat(
      var.preview_hostname == null ? [] : [lower(trimspace(var.preview_hostname))],
      [for h in var.hostnames : lower(trimspace(h.hostname))]
      ))) == length(concat(
      var.preview_hostname == null ? [] : [lower(trimspace(var.preview_hostname))],
      [for h in var.hostnames : lower(trimspace(h.hostname))]
    ))
    error_message = "Hostnames must be unique across preview_hostname and hostnames."
  }
}

variable "expose_tunnel_token" {
  type        = bool
  default     = false
  nullable    = false
  description = "Read the tunnel connector token through the cloudflare_zero_trust_tunnel_cloudflared_token data source and expose it as the tunnel_token output. Requires Cloudflare Tunnel Write permission on the API token."
}
