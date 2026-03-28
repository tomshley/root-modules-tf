variable "zone_id" {
  type        = string
  description = "Existing Cloudflare zone ID for publishing mail DNS records."

  validation {
    condition     = trimspace(var.zone_id) != ""
    error_message = "zone_id must be non-empty."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", trimspace(var.zone_id)))
    error_message = "zone_id must be a 32-character lowercase hex string."
  }
}

variable "mx_records" {
  type = list(object({
    priority = number
    value    = string
  }))
  default     = []
  description = "MX records published at the zone apex. Each item defines priority and mail host value."

  validation {
    condition     = alltrue([for record in var.mx_records : record.priority >= 0])
    error_message = "Each mx_records priority must be greater than or equal to 0."
  }

  validation {
    condition     = alltrue([for record in var.mx_records : trimspace(record.value) != ""])
    error_message = "Each mx_records value must be non-empty."
  }
}

variable "spf_value" {
  type        = string
  description = "SPF TXT record value published at the zone apex."

  validation {
    condition     = trimspace(var.spf_value) != ""
    error_message = "spf_value must be non-empty."
  }

  validation {
    condition     = can(regex("^v=spf1\\b", trimspace(var.spf_value)))
    error_message = "spf_value must start with v=spf1."
  }
}

variable "dkim_records" {
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default     = []
  description = "DKIM records. Supports CNAME and TXT records only."

  validation {
    condition     = alltrue([for record in var.dkim_records : trimspace(record.name) != ""])
    error_message = "Each dkim_records name must be non-empty."
  }

  validation {
    condition     = alltrue([for record in var.dkim_records : contains(["CNAME", "TXT"], upper(record.type))])
    error_message = "dkim_records supports only CNAME and TXT record types."
  }

  validation {
    condition     = alltrue([for record in var.dkim_records : trimspace(record.value) != ""])
    error_message = "Each dkim_records value must be non-empty."
  }
}

variable "dmarc_value" {
  type        = string
  description = "DMARC TXT record value published at _dmarc."

  validation {
    condition     = trimspace(var.dmarc_value) != ""
    error_message = "dmarc_value must be non-empty."
  }

  validation {
    condition     = can(regex("^v=DMARC1(;|\\b)", trimspace(var.dmarc_value)))
    error_message = "dmarc_value must start with v=DMARC1."
  }
}

variable "verification_records" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Optional mail provider verification TXT records."

  validation {
    condition     = alltrue([for record in var.verification_records : trimspace(record.name) != ""])
    error_message = "Each verification_records name must be non-empty."
  }

  validation {
    condition     = alltrue([for record in var.verification_records : trimspace(record.value) != ""])
    error_message = "Each verification_records value must be non-empty."
  }
}
