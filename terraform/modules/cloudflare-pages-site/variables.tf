variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the Pages project."

  validation {
    condition     = trimspace(var.account_id) != ""
    error_message = "account_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.account_id)))
    error_message = "account_id must be a 32-character lowercase hex string."
  }
}

variable "project_name" {
  type        = string
  description = "Cloudflare Pages project name."

  validation {
    condition     = trimspace(var.project_name) != ""
    error_message = "project_name must be non-empty."
  }

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,56}[a-z0-9])?$", trimspace(var.project_name)))
    error_message = "project_name must be 1-58 characters of lowercase letters, digits, or hyphens and cannot start or end with a hyphen (Cloudflare Pages naming rules)."
  }
}

variable "production_branch" {
  type        = string
  default     = "main"
  description = "Git branch treated as production by Cloudflare Pages."

  validation {
    condition     = trimspace(var.production_branch) != ""
    error_message = "production_branch must be non-empty."
  }
}

variable "build_config" {
  type = object({
    build_command   = optional(string)
    destination_dir = optional(string)
    root_dir        = optional(string)
    build_caching   = optional(bool)
  })
  default     = null
  description = "Optional Cloudflare Pages build config. Set to null for direct-upload workflows."
}

variable "custom_domains" {
  type = list(object({
    hostname          = string
    zone_id           = optional(string)
    create_dns_record = optional(bool, true)
    proxied           = optional(bool, true)
    comment           = optional(string)
  }))
  default     = []
  description = "Custom domains to attach to the Pages project. When create_dns_record is true (the default) a proxied CNAME to <project>.pages.dev is managed here and zone_id is required; set create_dns_record = false to attach the domain only and manage DNS elsewhere (zone_id may then be omitted)."

  validation {
    condition     = alltrue([for d in var.custom_domains : trimspace(d.hostname) != ""])
    error_message = "Each custom_domains item must define a non-empty hostname."
  }

  validation {
    condition = alltrue([
      for d in var.custom_domains : can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", trimspace(d.hostname)))
    ])
    error_message = "Each custom_domains.hostname must be a valid fully qualified domain name."
  }

  validation {
    condition = alltrue([
      for d in var.custom_domains :
      !d.create_dns_record || can(regex("^[0-9a-f]{32}$", trimspace(d.zone_id)))
    ])
    error_message = "Each custom_domains item with create_dns_record = true must set zone_id to a 32-character lowercase hex string."
  }

  validation {
    condition     = length(var.custom_domains) == length(distinct([for d in var.custom_domains : lower(trimspace(d.hostname))]))
    error_message = "custom_domains hostnames must be unique (case-insensitive)."
  }
}
