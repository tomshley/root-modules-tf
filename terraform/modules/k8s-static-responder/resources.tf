# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  selector = {
    "app.kubernetes.io/name"      = var.name
    "app.kubernetes.io/component" = "static-responder"
  }
  labels = merge(var.labels, local.selector)
  locations = [for path, file in var.files : chomp(<<-LOCATION
    location = "${replace(replace(path, "\\", "\\\\"), "\"", "\\\"")}" {
      types { }
      default_type "${replace(replace(file.content_type, "\\", "\\\\"), "\"", "\\\"")}";
      alias /srv/files/${sha256(path)};
    }
  LOCATION
  )]
  nginx_config = <<-NGINX
    worker_processes 1;
    pid /tmp/nginx.pid;
    error_log /dev/stderr warn;
    events { worker_connections 1024; }
    http {
      server_tokens off;
      access_log /dev/stdout;
      client_body_temp_path /tmp/client_temp;
      proxy_temp_path /tmp/proxy_temp;
      fastcgi_temp_path /tmp/fastcgi_temp;
      uwsgi_temp_path /tmp/uwsgi_temp;
      scgi_temp_path /tmp/scgi_temp;
      server {
        listen 8080;
        server_name _;
        merge_slashes off;
        ${indent(4, join("\n", concat(local.locations, ["location / { return 404; }"])))}
      }
    }
  NGINX
  config_data = merge(
    { "nginx.conf" = local.nginx_config },
    { for path, file in var.files : sha256(path) => file.content }
  )
}

resource "kubernetes_config_map_v1" "files" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  data = local.config_data

  lifecycle {
    precondition {
      condition     = length(base64encode(jsonencode(local.config_data))) <= 1228800
      error_message = "Files and generated configuration must fit within the 900 KiB ConfigMap budget."
    }
  }
}

resource "kubernetes_deployment_v1" "responder" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.replicas
    selector { match_labels = local.selector }
    template {
      metadata {
        labels      = local.labels
        annotations = { "checksum/files" = sha256(jsonencode(local.config_data)) }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        security_context {
          run_as_non_root = true
          run_as_user     = 101
          run_as_group    = 101
          fs_group        = 101
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name    = "nginx"
          image   = var.image
          command = ["nginx"]
          args    = ["-g", "daemon off;", "-c", "/srv/files/nginx.conf"]
          port {
            name           = "http"
            container_port = 8080
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          readiness_probe {
            tcp_socket { port = "http" }
            initial_delay_seconds = 1
            period_seconds        = 5
          }
          liveness_probe {
            tcp_socket { port = "http" }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = { for key, value in {
              cpu = var.resources_requests_cpu, memory = var.resources_requests_memory
            } : key => value if value != null }
            limits = { for key, value in {
              cpu = var.resources_limits_cpu, memory = var.resources_limits_memory
            } : key => value if value != null }
          }
          volume_mount {
            name       = "files"
            mount_path = "/srv/files"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "files"
          config_map { name = kubernetes_config_map_v1.files.metadata[0].name }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "responder" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    type     = "ClusterIP"
    selector = local.selector
    port {
      port        = var.service_port
      target_port = "http"
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "responder" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    min_available = var.pdb_min_available
    selector { match_labels = local.selector }
  }
}
