output "enabled" {
  description = "Whether the alert source was deployed (false on cold-start / disabled plans)."
  value       = var.enabled
}

output "id" {
  description = "ID of the alert source (null when not deployed). Useful for incident_alert_route alert_sources bindings authored alongside this module."
  value       = var.enabled ? incident_alert_source.this[0].id : null
}

output "alert_events_url" {
  description = "HTTP endpoint that receives alert events for this source (null when not deployed). Feed this to your alerting producer — e.g. grafana-cloud-alerting's webhook_url — through state, never by hand. Treat as a secret: together with secret_token it is sufficient to inject alerts."
  value       = var.enabled ? incident_alert_source.this[0].alert_events_url : null
  sensitive   = true
}

output "secret_token" {
  description = "Bearer token authenticating events to this source (null when not deployed). Feed to your producer's Authorization header — e.g. grafana-cloud-alerting's webhook_token. Rotate by replacing this resource (see resources.tf header); rotating the provider API key does not rotate this."
  value       = var.enabled ? incident_alert_source.this[0].secret_token : null
  sensitive   = true
}
