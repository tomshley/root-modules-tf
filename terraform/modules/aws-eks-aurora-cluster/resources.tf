resource "random_password" "master_password" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name_prefix}-${var.workload_name}"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.project_name_prefix}-${var.workload_name}"
  description = local.resolved_sg_description
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
    Name = "${var.project_name_prefix}-${var.workload_name}"
  })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.project_name_prefix}-${var.workload_name}-pg"
  family      = "aurora-postgresql${local.engine_major_version}"
  description = local.resolved_pg_description

  lifecycle {
    precondition {
      condition     = contains(["13", "14", "15", "16", "17"], local.engine_major_version)
      error_message = "engine_version must start with a supported Aurora PostgreSQL major version (13–17)."
    }
  }

  # --- Preset-resolved tunable parameters (only added when non-null) ---

  dynamic "parameter" {
    for_each = local.resolved_max_connections != null ? [local.resolved_max_connections] : []
    content {
      name         = "max_connections"
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_wal_buffers != null ? [local.resolved_wal_buffers] : []
    content {
      name         = "wal_buffers"
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_random_page_cost != null ? [local.resolved_random_page_cost] : []
    content {
      name  = "random_page_cost"
      value = parameter.value
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_work_mem != null ? [local.resolved_work_mem] : []
    content {
      name  = "work_mem"
      value = parameter.value
    }
  }

  # --- Always-on audit parameters ---

  parameter {
    name  = "log_min_duration_statement"
    value = "300"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-pg"
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.project_name_prefix}-${var.workload_name}-db"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = random_password.master_password.result
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_period
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.project_name_prefix}-${var.workload_name}-final"
  copy_tags_to_snapshot           = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db"
  })
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.project_name_prefix}-${var.workload_name}-db-1"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db-1"
  })
}

resource "aws_rds_cluster_instance" "reader" {
  count = var.reader_instance_count

  identifier          = "${var.project_name_prefix}-${var.workload_name}-db-reader-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db-reader-${count.index + 1}"
  })
}

resource "aws_secretsmanager_secret" "this" {
  name = "${var.project_name_prefix}-${var.workload_name}-db"

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db"
  })
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master_password.result
    host     = aws_rds_cluster.this.endpoint
    port     = var.port
    dbname   = var.database_name
  })
}
