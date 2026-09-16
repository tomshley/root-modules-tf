variable "binding" {
  type = object({
    host                 = string
    port                 = number
    database_name        = string
    tls_required         = bool
    ca_secret_name       = optional(string)
    username_secret_name = string
    password_secret_name = string
    reader_host          = optional(string)
    reader_capable       = bool
  })
  nullable    = false
  description = "Portable PostgreSQL workload binding."

  validation {
    condition     = var.binding.port >= 1 && var.binding.port <= 65535
    error_message = "binding.port must be a valid TCP port."
  }

  validation {
    condition     = !var.binding.tls_required || var.binding.ca_secret_name != null
    error_message = "tls_required bindings must name a CA Secret."
  }

  validation {
    condition     = var.binding.reader_capable == (var.binding.reader_host != null)
    error_message = "reader_capable must match the presence of reader_host."
  }
}
