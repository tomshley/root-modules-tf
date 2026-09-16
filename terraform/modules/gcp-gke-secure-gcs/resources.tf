module "secure_gcs" {
  source = "../gcp-secure-gcs"

  project_id            = var.project_id
  bucket_name           = var.bucket_name
  location              = var.location
  force_destroy         = var.force_destroy
  versioning_enabled    = var.versioning_enabled
  retention_policy_days = var.retention_policy_days
  labels                = var.labels
}
