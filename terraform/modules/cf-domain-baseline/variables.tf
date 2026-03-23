variable "zone_id" {
  type        = string
  description = "Existing Cloudflare zone ID to configure."

  validation {
    condition     = trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty."
  }
}

variable "ssl_mode" {
  type        = string
  default     = "strict"
  description = "Cloudflare SSL/TLS mode for the zone. Allowed values: off, flexible, full, strict."

  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.ssl_mode)
    error_message = "ssl_mode must be one of: off, flexible, full, strict."
  }
}

variable "min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version accepted by Cloudflare for the zone. Allowed values: 1.0, 1.1, 1.2, 1.3."

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.min_tls_version)
    error_message = "min_tls_version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "dns_records" {
  type = list(object({
    name    = string
    type    = string
    value   = optional(string)
    ttl     = optional(number, 1)
    proxied = optional(bool)
    caa = optional(object({
      flags = optional(number, 0)
      tag   = string
      value = string
    }))
  }))
  default = []

  description = "Curated baseline DNS records. Supported types are A, AAAA, CNAME, TXT, and CAA. Use value for A, AAAA, CNAME, and TXT. Use caa.flags, caa.tag, and caa.value for CAA. proxied is valid only for A, AAAA, and CNAME. ttl defaults to 1 (automatic)."

  validation {
    condition     = alltrue([for record in var.dns_records : trimspace(record.name) != ""])
    error_message = "Each dns_records item must define a non-empty name."
  }

  validation {
    condition     = alltrue([for record in var.dns_records : contains(["A", "AAAA", "CNAME", "TXT", "CAA"], upper(record.type))])
    error_message = "dns_records supports only A, AAAA, CNAME, TXT, and CAA record types."
  }

  validation {
    condition     = alltrue([for record in var.dns_records : record.ttl == 1 || (record.ttl >= 60 && record.ttl <= 86400)])
    error_message = "Each dns_records ttl must be 1 (automatic) or between 60 and 86400 seconds."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : contains(["A", "AAAA", "CNAME"], upper(record.type)) ? true : try(record.proxied, null) == null
    ])
    error_message = "dns_records.proxied may be set only for A, AAAA, and CNAME records."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "CAA" ? try(record.caa, null) != null : try(record.caa, null) == null
    ])
    error_message = "CAA records must define caa, and non-CAA records must not define caa."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "CAA" ? try(record.value, null) == null : try(trimspace(record.value), "") != ""
    ])
    error_message = "Non-CAA records must set value. CAA records must leave value unset."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "A" ? (
        can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", trimspace(record.value))) &&
        can(cidrhost("${trimspace(record.value)}/32", 0))
      ) : true
    ])
    error_message = "A records must use a valid IPv4 address in value."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "AAAA" ? can(cidrhost("${record.value}/128", 0)) : true
    ])
    error_message = "AAAA records must use a valid IPv6 address in value."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "CAA" ? contains(["issue", "issuewild", "iodef"], lower(trimspace(try(record.caa.tag, "")))) : true
    ])
    error_message = "CAA records must use one of the supported tags: issue, issuewild, iodef."
  }

  validation {
    condition = alltrue([
      for record in var.dns_records : upper(record.type) == "CAA" ? trimspace(try(record.caa.value, "")) != "" : true
    ])
    error_message = "CAA records must set a non-empty caa.value."
  }

  validation {
    condition = alltrue([
      for name in distinct([for record in var.dns_records : lower(trimspace(record.name))]) : !(
        contains([for record in var.dns_records : upper(record.type) if lower(trimspace(record.name)) == name], "CNAME") &&
        length([for record in var.dns_records : record if lower(trimspace(record.name)) == name && contains(["A", "AAAA"], upper(record.type))]) > 0
      )
    ])
    error_message = "A or AAAA records cannot share the same name as a CNAME record."
  }
}

variable "origin_ca" {
  type = object({
    csr                = string
    hostnames          = list(string)
    request_type       = optional(string, "origin-rsa")
    requested_validity = optional(number, 5475)
  })
  default     = null
  description = "Optional Origin CA certificate request. Set to null to skip Origin CA. When provided, csr and hostnames are required. request_type defaults to origin-rsa and requested_validity defaults to 5475 days."

  validation {
    condition     = var.origin_ca == null ? true : trimspace(var.origin_ca.csr) != ""
    error_message = "origin_ca.csr must be non-empty when origin_ca is provided."
  }

  validation {
    condition     = var.origin_ca == null ? true : length(var.origin_ca.hostnames) > 0
    error_message = "origin_ca.hostnames must contain at least one hostname when origin_ca is provided."
  }

  validation {
    condition = var.origin_ca == null ? true : alltrue([
      for hostname in var.origin_ca.hostnames : can(regex("^(\\*\\.)?([[:alnum:]-]+\\.)+[[:alnum:]-]+$", hostname))
    ])
    error_message = "origin_ca.hostnames must contain fully qualified hostnames or single-level wildcard hostnames such as *.example.com."
  }

  validation {
    condition     = var.origin_ca == null ? true : contains(["origin-rsa", "origin-ecc", "keyless-certificate"], var.origin_ca.request_type)
    error_message = "origin_ca.request_type must be one of: origin-rsa, origin-ecc, keyless-certificate."
  }

  validation {
    condition     = var.origin_ca == null ? true : contains([7, 30, 90, 365, 730, 1095, 5475], var.origin_ca.requested_validity)
    error_message = "origin_ca.requested_validity must be one of: 7, 30, 90, 365, 730, 1095, 5475 when origin_ca is provided."
  }
}
