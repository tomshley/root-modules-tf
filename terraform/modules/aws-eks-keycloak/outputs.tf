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

output "release_name" {
  description = "Name of the Helm release"
  value       = module.keycloak.release_name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = module.keycloak.release_namespace
}

output "release_version" {
  description = "Chart version of the Helm release"
  value       = module.keycloak.release_version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = module.keycloak.release_status
}

output "keycloak_service_name" {
  description = "Kubernetes Service name for Keycloak (for in-cluster consumers)"
  value       = module.keycloak.keycloak_service_name
}

output "keycloak_service_port" {
  description = "Kubernetes Service port for Keycloak HTTP. Defaults to the Bitnami chart default (HTTP/80). Override via var.service_port if TLS or a non-standard port is configured."
  value       = module.keycloak.keycloak_service_port
}

output "base_url" {
  description = "Keycloak base URL (in-cluster, HTTP). Append /realms/<realm> for the OIDC issuer URL, or /admin for the admin console. When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = module.keycloak.base_url
}

output "jwks_uri_template" {
  description = "JWKS URI template (in-cluster, HTTP). Replace {realm} with the target realm name. When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = module.keycloak.jwks_uri_template
}

output "admin_console_url" {
  description = "Keycloak admin console URL (in-cluster, HTTP). When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = module.keycloak.admin_console_url
}
