output "bucket_name" {
  value = google_storage_bucket.secure.name
}

output "bucket_arn" {
  value = "projects/_/buckets/${google_storage_bucket.secure.name}"
}

output "bucket_id" {
  value = google_storage_bucket.secure.id
}

output "readwrite_policy_arn" {
  value = "roles/storage.objectAdmin"
}

output "readonly_policy_arn" {
  value = "roles/storage.objectViewer"
}
