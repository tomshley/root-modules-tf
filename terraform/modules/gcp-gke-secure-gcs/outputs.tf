output "bucket_name" {
  value = module.secure_gcs.bucket_name
}

output "bucket_arn" {
  value = module.secure_gcs.bucket_arn
}

output "bucket_id" {
  value = module.secure_gcs.bucket_id
}

output "readwrite_policy_arn" {
  value = module.secure_gcs.readwrite_policy_arn
}

output "readonly_policy_arn" {
  value = module.secure_gcs.readonly_policy_arn
}
