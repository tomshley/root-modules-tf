module "redis_contract" {
  count    = var.redis_contract == null ? 0 : 1
  source   = "../redis-service-contract"
  contract = var.redis_contract
}

resource "terraform_data" "private_services_connection" {
  input = var.private_services_connection_id
}

resource "google_redis_instance" "this" {
  depends_on              = [terraform_data.private_services_connection]
  project                 = var.project_id
  name                    = "${var.project_name_prefix}-${var.workload_name}"
  region                  = var.region
  tier                    = var.tier
  memory_size_gb          = var.memory_size_gb
  redis_version           = var.redis_version
  authorized_network      = var.authorized_network
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  labels                  = var.labels

  lifecycle {
    precondition {
      condition = var.redis_contract == null ? true : (
        module.redis_contract[0].contract.mode == "cache" &&
        !module.redis_contract[0].contract.reader_required &&
        !module.redis_contract[0].contract.persistence_required &&
        (module.redis_contract[0].contract.availability != "multi-zone" || var.tier == "STANDARD_HA")
      )
      error_message = "The GCP Memorystore adapter currently supports only cache contracts without dedicated readers or retained-state persistence."
    }
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = var.maintenance_window_day
      start_time {
        hours   = var.maintenance_window_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }
}

resource "google_secret_manager_secret" "auth" {
  project   = var.project_id
  secret_id = "${var.project_name_prefix}-${var.workload_name}-redis-auth"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "auth" {
  secret = google_secret_manager_secret.auth.id
  secret_data = jsonencode({
    host     = google_redis_instance.this.host
    port     = google_redis_instance.this.port
    password = google_redis_instance.this.auth_string
  })
}
