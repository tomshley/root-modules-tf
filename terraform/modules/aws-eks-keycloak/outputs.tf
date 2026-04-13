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
  description = "Kubernetes Service port for Keycloak HTTP. Reflects the Bitnami chart default (HTTP/80). If TLS is enabled via extra Helm values, consumers should override downstream references."
  value       = 80
}

output "base_url" {
  description = "Keycloak base URL (in-cluster). Append /realms/<realm> for the OIDC issuer URL, or /admin for the admin console."
  value       = "http://${helm_release.keycloak.name}.${helm_release.keycloak.namespace}.svc.cluster.local"
}

output "jwks_uri_template" {
  description = "JWKS URI template. Replace {realm} with the target realm name for the realm-specific JWKS endpoint."
  value       = "http://${helm_release.keycloak.name}.${helm_release.keycloak.namespace}.svc.cluster.local/realms/{realm}/protocol/openid-connect/certs"
}

output "admin_console_url" {
  description = "Keycloak admin console URL (in-cluster)"
  value       = "http://${helm_release.keycloak.name}.${helm_release.keycloak.namespace}.svc.cluster.local/admin"
}
