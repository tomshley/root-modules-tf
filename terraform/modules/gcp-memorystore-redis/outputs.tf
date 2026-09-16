output "primary_endpoint" {
  value = google_redis_instance.this.host
}

output "reader_endpoint" {
  value = google_redis_instance.this.host
}

output "port" {
  value = google_redis_instance.this.port
}

output "auth_token_secret_id" {
  value = google_secret_manager_secret.auth.id
}

output "app_read_policy_arn" {
  value = "roles/secretmanager.secretAccessor"
}

output "instance_id" {
  value = google_redis_instance.this.id
}

output "redis_contract" {
  description = "The normalized Redis contract when the additive contract input is used; null preserves the legacy caller path."
  value       = var.redis_contract == null ? null : module.redis_contract[0].contract
}
