output "binding" {
  value       = local.normalized
  description = "Normalized portable PostgreSQL binding."
}

output "reader_capable" {
  value       = local.normalized.reader_capable
  description = "Whether this binding has a dedicated reader endpoint."
}
