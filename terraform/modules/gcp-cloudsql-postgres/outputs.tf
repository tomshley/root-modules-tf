output "cluster_endpoint" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "reader_endpoint" {
  value = var.reader_instance_count == 0 ? google_sql_database_instance.primary.private_ip_address : google_sql_database_instance.reader[0].private_ip_address
}

output "port" {
  value = var.port
}

output "database_name" {
  value = google_sql_database.default.name
}

output "master_username" {
  value = google_sql_user.master.name
}

output "master_secret_id" {
  value = google_secret_manager_secret.master.id
}

output "connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "reader_instance_count" {
  value = var.reader_instance_count
}

output "workload_contract" {
  value       = module.workload_contract.contract
  description = "The normalized PostgreSQL workload contract applied by this adapter."
}
