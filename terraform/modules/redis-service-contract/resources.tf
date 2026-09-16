locals {
  normalized = {
    mode                 = var.contract.mode
    auth_required        = var.contract.auth_required
    tls_required         = var.contract.tls_required
    reader_required      = var.contract.reader_required
    persistence_required = var.contract.persistence_required
    availability         = var.contract.availability
  }
}
