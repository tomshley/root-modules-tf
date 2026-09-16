output "contract" {
  value       = local.normalized
  description = "Normalized PostgreSQL workload contract for provider adapters."
}

output "is_authoritative" {
  value       = local.normalized.authoritative
  description = "Whether the workload owns authoritative state."
}

output "requires_reader" {
  value       = local.normalized.reader_required
  description = "Whether the adapter must provide dedicated reader capacity."
}
