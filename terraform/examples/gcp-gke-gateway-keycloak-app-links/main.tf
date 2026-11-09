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
  public_origin = "https://${var.public_hostname}"
  realm         = jsondecode(replace(file("${path.module}/realm/realm.json"), "$(env:PUBLIC_ORIGIN)", local.public_origin))
  realm_name    = "example"
  apps = [{
    name = "example-mobile"
    ios = {
      team_id   = "ABCDE12345"
      bundle_id = "test.example.mobile"
      paths     = ["/oauth/callback"]
    }
    android = {
      package_name        = "test.example.mobile"
      sha256_fingerprints = [join(":", [for byte in range(32) : "AA"])]
    }
  }]
  redirect_uris = concat(
    [for path in module.app_links.callback_paths : "${local.public_origin}${path}"],
    ["test.example.mobile:/oauth/callback", "http://127.0.0.1/*", "http://[::1]/*"],
  )
}

check "realm_name_matches_json" {
  assert {
    condition     = local.realm.realm == local.realm_name
    error_message = "realm name in locals does not match realm.json"
  }
}

check "redirect_uris_match_app_links" {
  assert {
    condition     = toset([for client in local.realm.clients : client.redirectUris if client.clientId == "mobile"][0]) == toset(local.redirect_uris)
    error_message = "mobile client redirectUris do not match the derived set"
  }
}

module "cert_manager" {
  create_namespace = false
  source           = "../../modules/k8s-cert-manager"
  chart_version    = "v1.21.3"
  issuer = {
    name       = "dns01"
    acme_email = "ops@example.test"
    dns01 = {
      provider               = "cloudflare"
      credential_secret_name = "cloudflare-dns01"
    }
  }
}

module "gateway" {
  create_namespace = false
  source           = "../../modules/gcp-gke-gateway"
  name             = "public-gateway"
  namespace        = "identity"
  chart_version    = "v1.9.3"
  internal         = false
  listeners = {
    auth = {
      hostname = var.public_hostname
      protocol = "HTTPS"
      port     = 443
      tls_issuer = {
        name = module.cert_manager.issuer_name
        kind = module.cert_manager.issuer_kind
      }
    }
  }
}

module "keycloak" {
  source           = "../../modules/gcp-gke-keycloak"
  project_id       = var.project_id
  namespace        = module.gateway.gateway_namespace
  create_namespace = false
  service_type     = "ClusterIP"
  public_hostname  = var.public_hostname
  realm_json_path  = "${path.module}/realm/realm.json"
  db_endpoint      = var.db_endpoint
  db_name          = "keycloak"
  db_user          = ""
  existing_secrets = {
    admin = { name = "keycloak-admin" }
    db    = { name = "keycloak-db" }
  }
  extra_helm_values = [jsonencode({
    proxyHeaders = "xforwarded"
    keycloakConfigCli = {
      extraEnvVars = [
        { name = "IMPORT_VARSUBSTITUTION_ENABLED", value = "true" },
        { name = "PUBLIC_ORIGIN", value = local.public_origin },
      ]
    }
  })]
}

module "app_links" {
  source = "../../modules/k8s-app-links"
  apps   = local.apps
}

module "static_responder" {
  source    = "../../modules/k8s-static-responder"
  name      = "app-links"
  image     = "nginxinc/nginx-unprivileged@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"
  namespace = module.gateway.gateway_namespace
  files     = module.app_links.files
}

resource "kubernetes_manifest" "route_well_known" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = "well-known", namespace = module.gateway.gateway_namespace }
    spec = {
      parentRefs = [{ name = module.gateway.gateway_name, namespace = module.gateway.gateway_namespace }]
      hostnames  = [var.public_hostname]
      rules = [{
        matches = [for path in module.app_links.paths : { path = { type = "Exact", value = path } }]
        backendRefs = [{
          name = module.static_responder.service_name
          port = module.static_responder.service_port
        }]
      }]
    }
  }
}

resource "kubernetes_manifest" "route_keycloak" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = "keycloak", namespace = module.gateway.gateway_namespace }
    spec = {
      parentRefs = [{ name = module.gateway.gateway_name, namespace = module.gateway.gateway_namespace }]
      hostnames  = [var.public_hostname]
      rules = [{
        matches = [{ path = { type = "PathPrefix", value = "/" } }]
        backendRefs = [{
          name = module.keycloak.keycloak_service_name
          port = module.keycloak.keycloak_service_port
        }]
      }]
    }
  }
}

module "dns" {
  source  = "../../modules/cloudflare-domain-baseline"
  zone_id = var.zone_id
  dns_records = [{
    name    = var.public_hostname
    type    = "A"
    value   = module.gateway.load_balancer_ip
    proxied = false
  }]
}

output "public_url" { value = module.keycloak.public_url }
output "gateway_name" { value = module.gateway.gateway_name }
output "association_paths" { value = module.app_links.paths }
