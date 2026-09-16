locals {
  normalized = {
    host                 = var.binding.host
    port                 = var.binding.port
    database_name        = var.binding.database_name
    tls_required         = var.binding.tls_required
    ca_secret_name       = var.binding.ca_secret_name
    username_secret_name = var.binding.username_secret_name
    password_secret_name = var.binding.password_secret_name
    reader_host          = var.binding.reader_host
    reader_capable       = var.binding.reader_capable
  }
}
