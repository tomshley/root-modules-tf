locals {
  normalized = {
    purpose                = var.contract.purpose
    reader_required        = var.contract.reader_required
    tls_required           = var.contract.tls_required
    retention_days         = var.contract.retention_days
    authoritative          = var.contract.authoritative
    projection_rebuildable = var.contract.projection_rebuildable
  }
}
