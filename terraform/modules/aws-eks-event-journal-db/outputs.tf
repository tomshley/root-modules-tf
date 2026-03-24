output "cluster_endpoint" {
  value = aws_rds_cluster.event_journal.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.event_journal.reader_endpoint
}

output "port" {
  value = var.port
}

output "database_name" {
  value = var.database_name
}

output "security_group_id" {
  value = aws_security_group.event_journal.id
}

output "master_secret_arn" {
  value = aws_secretsmanager_secret.event_journal.arn
}

output "cluster_arn" {
  value = aws_rds_cluster.event_journal.arn
}

output "cluster_id" {
  value = aws_rds_cluster.event_journal.cluster_identifier
}

output "parameter_group_name" {
  value = aws_rds_cluster_parameter_group.event_journal.name
}
