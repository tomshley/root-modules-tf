locals {
  engine_major_version = split(".", var.engine_version)[0]
}

resource "random_password" "master_password" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "event_journal" {
  name       = "${var.project_name_prefix}-event-journal"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal"
  })
}

resource "aws_security_group" "event_journal" {
  name        = "${var.project_name_prefix}-event-journal"
  description = "Aurora PostgreSQL access for event journal workloads"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from allowed security groups"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal"
  })
}

resource "aws_rds_cluster_parameter_group" "event_journal" {
  name        = "${var.project_name_prefix}-event-journal-pg"
  family      = "aurora-postgresql${local.engine_major_version}"
  description = "Aurora PostgreSQL event journal tuning"

  lifecycle {
    precondition {
      condition     = contains(["13", "14", "15", "16", "17"], local.engine_major_version)
      error_message = "engine_version must start with a supported Aurora PostgreSQL major version (13–17)."
    }
  }

  parameter {
    name         = "max_connections"
    value        = "400"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "wal_buffers"
    value        = "2048"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "300"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal-pg"
  })
}

resource "aws_rds_cluster" "event_journal" {
  cluster_identifier              = "${var.project_name_prefix}-event-journal-db"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = random_password.master_password.result
  db_subnet_group_name            = aws_db_subnet_group.event_journal.name
  vpc_security_group_ids          = [aws_security_group.event_journal.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.event_journal.name
  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_period
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier      = var.skip_final_snapshot ? null : "${var.project_name_prefix}-event-journal-final"
  copy_tags_to_snapshot           = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal-db"
  })
}

resource "aws_rds_cluster_instance" "event_journal_writer" {
  identifier         = "${var.project_name_prefix}-event-journal-db-1"
  cluster_identifier = aws_rds_cluster.event_journal.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.event_journal.engine
  engine_version     = aws_rds_cluster.event_journal.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal-db-1"
  })
}

resource "aws_secretsmanager_secret" "event_journal" {
  name = "${var.project_name_prefix}-event-journal-db"

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-event-journal-db"
  })
}

resource "aws_secretsmanager_secret_version" "event_journal" {
  secret_id = aws_secretsmanager_secret.event_journal.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master_password.result
    host     = aws_rds_cluster.event_journal.endpoint
    port     = var.port
    dbname   = var.database_name
  })
}
