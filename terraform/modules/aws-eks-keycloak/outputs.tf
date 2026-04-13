output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.keycloak.name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.keycloak.namespace
}

output "release_version" {
  description = "Chart version of the Helm release"
  value       = helm_release.keycloak.version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.keycloak.status
}

output "keycloak_service_name" {
  description = "Kubernetes Service name for Keycloak (for in-cluster consumers)"
  value       = helm_release.keycloak.name
}

output "keycloak_service_port" {
  description = "Kubernetes Service port for Keycloak HTTP. Defaults to the Bitnami chart default (HTTP/80). Override via var.service_port if TLS or a non-standard port is configured."
  value       = var.service_port
}

output "base_url" {
  description = "Keycloak base URL (in-cluster, HTTP). Append /realms/<realm> for the OIDC issuer URL, or /admin for the admin console. When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = "http://${local.service_host}${local.port_suffix}"
}

output "jwks_uri_template" {
  description = "JWKS URI template (in-cluster, HTTP). Replace {realm} with the target realm name. When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = "http://${local.service_host}${local.port_suffix}/realms/{realm}/protocol/openid-connect/certs"
}

output "admin_console_url" {
  description = "Keycloak admin console URL (in-cluster, HTTP). When TLS is configured via extra_helm_values, consumers must reconstruct the URL with https://."
  value       = "http://${local.service_host}${local.port_suffix}/admin"
}
