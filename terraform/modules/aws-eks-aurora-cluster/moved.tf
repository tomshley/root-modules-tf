# State migration from aws-eks-event-journal-db (pre-v1.4.0) to
# aws-eks-aurora-cluster. Consumers that previously used the single-purpose
# module keep their existing resources without destroy/recreate when they
# switch source paths. Consumers that never used the old module are unaffected
# — unmatched `from` addresses are silently ignored by Terraform/OpenTofu.

moved {
  from = aws_db_subnet_group.event_journal
  to   = aws_db_subnet_group.this
}

moved {
  from = aws_security_group.event_journal
  to   = aws_security_group.this
}

moved {
  from = aws_rds_cluster_parameter_group.event_journal
  to   = aws_rds_cluster_parameter_group.this
}

moved {
  from = aws_rds_cluster.event_journal
  to   = aws_rds_cluster.this
}

moved {
  from = aws_rds_cluster_instance.event_journal_writer
  to   = aws_rds_cluster_instance.writer
}

moved {
  from = aws_secretsmanager_secret.event_journal
  to   = aws_secretsmanager_secret.this
}

moved {
  from = aws_secretsmanager_secret_version.event_journal
  to   = aws_secretsmanager_secret_version.this
}
