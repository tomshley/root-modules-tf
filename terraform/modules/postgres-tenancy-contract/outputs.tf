output "tenant_bindings" {
  value       = local.bindings
  description = "Deterministic tenant database and role bindings for provider adapters."
}

output "tenant_keys" {
  value       = sort(keys(local.bindings))
  description = "Stable tenant keys in deterministic order."
}
