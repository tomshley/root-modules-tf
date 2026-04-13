output "cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = var.port
}

output "database_name" {
  value = var.database_name
}

output "master_username" {
  value = var.master_username
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "master_secret_arn" {
  value = aws_secretsmanager_secret.this.arn
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "cluster_id" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "parameter_group_name" {
  value = aws_rds_cluster_parameter_group.this.name
}
