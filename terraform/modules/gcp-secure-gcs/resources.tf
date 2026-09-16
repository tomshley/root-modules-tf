resource "google_storage_bucket" "secure" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  force_destroy               = var.force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels

  versioning { enabled = var.versioning_enabled }

  dynamic "retention_policy" {
    for_each = var.retention_policy_days > 0 ? [var.retention_policy_days] : []
    content {
      retention_period = retention_policy.value * 86400
    }
  }
}
