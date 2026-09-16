variable "contract" {
  type = object({
    purpose                = string
    reader_required        = bool
    tls_required           = bool
    retention_days         = number
    authoritative          = bool
    projection_rebuildable = bool
  })
  nullable    = false
  description = "Provider-independent PostgreSQL workload requirements. retention_days is the minimum elapsed-day point-in-time recovery window, not a backup-count setting."

  validation {
    condition     = contains(["generic", "event-store", "read-store"], var.contract.purpose)
    error_message = "contract.purpose must be generic, event-store, or read-store."
  }

  validation {
    condition     = var.contract.retention_days >= 1
    error_message = "contract.retention_days must be at least one day."
  }

  validation {
    condition     = var.contract.authoritative != var.contract.projection_rebuildable
    error_message = "An authoritative store is not a rebuildable projection, and a rebuildable projection is not authoritative."
  }

  validation {
    condition = (
      var.contract.purpose == "event-store" && var.contract.authoritative && !var.contract.projection_rebuildable
      ) || (
      var.contract.purpose == "read-store" && !var.contract.authoritative && var.contract.projection_rebuildable
    ) || var.contract.purpose == "generic"
    error_message = "event-store and read-store purposes must carry their matching authority and rebuild semantics."
  }
}
