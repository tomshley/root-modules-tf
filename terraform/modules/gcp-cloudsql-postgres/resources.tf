module "workload_contract" {
  source   = "../postgres-workload-contract"
  contract = var.workload_contract
}

resource "terraform_data" "private_services_connection" {
  input = var.private_services_connection_id
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "master" {
  project   = var.project_id
  secret_id = "${var.project_name_prefix}-${var.workload_name}-db-master"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "master" {
  secret = google_secret_manager_secret.master.id
  secret_data = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}

resource "google_sql_database_instance" "primary" {
  depends_on = [terraform_data.private_services_connection]

  project             = var.project_id
  name                = "${var.project_name_prefix}-${var.workload_name}-db"
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  lifecycle {
    precondition {
      condition     = !module.workload_contract.requires_reader || var.reader_instance_count > 0
      error_message = "The selected PostgreSQL workload contract requires at least one dedicated reader instance."
    }

    precondition {
      condition     = module.workload_contract.contract.retention_days <= 7
      error_message = "Cloud SQL can provide at most a seven-day point-in-time recovery window through this adapter; a longer PostgreSQL retention contract is refused."
    }
  }

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    user_labels       = var.labels

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = module.workload_contract.contract.retention_days
      backup_retention_settings {
        retained_backups = var.backup_retained_backups
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network_id
      ssl_mode        = module.workload_contract.contract.tls_required ? "ENCRYPTED_ONLY" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }
  }
}

resource "google_sql_database" "default" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.primary.name
}

resource "google_sql_user" "master" {
  project  = var.project_id
  name     = var.master_username
  instance = google_sql_database_instance.primary.name
  password = random_password.master.result
}

resource "google_sql_database_instance" "reader" {
  count = var.reader_instance_count

  project              = var.project_id
  name                 = "${var.project_name_prefix}-${var.workload_name}-db-reader-${count.index + 1}"
  region               = var.region
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name

  settings {
    tier        = var.tier
    user_labels = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network_id
      ssl_mode        = module.workload_contract.contract.tls_required ? "ENCRYPTED_ONLY" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }
  }
}
