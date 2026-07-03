###############################################################################
# incident.io Alert Source + Grafana Cloud Alerting — Composed Example
#
# The GitOps closure of the alerting last hop: instead of hand-creating an
# alert source in the incident.io UI and copy-pasting its event URL + secret
# token into your alerting stack, Terraform owns the source and its exported
# alert_events_url/secret_token flow into the Grafana webhook contact point
# through state — no human ever handles the webhook credential.
#
#   module.incident_source ──alert_events_url/secret_token──▶ module.alerting
#     (incident_alert_source)        (grafana_contact_point webhook, Bearer)
#
# Requires TWO providers configured at this root:
#   - grafana  (url + glsa_ service-account token) — see the
#     grafana-cloud-alerting example for the credential nuances.
#   - incident (api_key = inc_… from incident.io -> Settings -> API keys with
#     the "View data" + "Create and manage on-call resources" bundles; see the
#     module's provider.tf header for the least-privilege rationale).
#
# Cold-start: both modules follow the repo's count-gating convention, each
# gated on its OWN provider's readiness — incident_io_api_key_present gates
# the alert source, grafana_configured gates the alerting module (its
# datasource lookups run at plan time, so a credential-less plan must keep it
# disabled). With both false, nothing is created and no API is touched.
#
# Alert ROUTES (alerts -> incidents/escalations) are deliberately NOT wrapped
# by a module: their schema is deep and organization-specific (escalation
# paths, channels, catalog bindings). Author routes in the incident.io visual
# editor, use its Terraform "Export" flow, and commit the generated
# incident_alert_route alongside this composition — module.incident_source.id
# is the alert_source_id those routes bind to.
###############################################################################

variable "incident_io_api_key_present" {
  type        = bool
  default     = false
  description = "Gate for cold-start plans: set true once the incident provider has a real API key. Callers typically derive this from their key variable, e.g. var.incident_io_api_key != null."
}

variable "grafana_configured" {
  type        = bool
  default     = false
  description = "Gate for cold-start plans: set true once the grafana provider points at a real instance (url + service-account token). The alerting module's datasource lookups run at plan time, so it must stay disabled until then. Callers typically derive this, e.g. var.grafana_url != null && var.grafana_sa_token != null."
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "namespace" {
  type    = string
  default = "example-workload"
}

variable "grafana_stack_slug" {
  type    = string
  default = "example-stack" # derives grafanacloud-<slug>-prom / -logs datasource names
}

module "incident_source" {
  source = "../../modules/incident-io-alert-source"

  enabled = var.incident_io_api_key_present

  # One source per environment keeps tokens, routes, and blast radius
  # separated; the environment belongs in the name.
  name = "example ${var.environment} Grafana"

  # "grafana" accepts Grafana's webhook contact-point payload natively. The
  # module's default template binds Payload -> Title / Payload -> Description,
  # which is exactly what Grafana sends — no template inputs needed. For
  # richer templates (attributes bound to catalog teams, parsed severities),
  # author in the incident.io UI and paste its Terraform export into
  # title_template / description_template / attributes / expressions.
  source_type = "grafana"
}

module "alerting" {
  source = "../../modules/grafana-cloud-alerting"

  # Gated on grafana provider readiness (datasource lookups run at plan time).
  # Once true, rules deploy + evaluate even before the incident.io source
  # exists (require_webhook = false); they route to the org default
  # notification policy until the contact point attaches (see the
  # grafana-cloud-alerting example).
  enabled         = var.grafana_configured
  require_webhook = false

  namespace          = var.namespace
  grafana_stack_slug = var.grafana_stack_slug

  # The composition point: webhook credentials come from state, not a human.
  # Both outputs are null while the source is disabled; flipping
  # incident_io_api_key_present creates the source AND attaches the contact
  # point in the SAME apply — count is driven by the plan-time-known
  # webhook_configured below, and the not-yet-known URL/token are ordinary
  # attribute values resolved at apply.
  webhook_url   = module.incident_source.alert_events_url
  webhook_token = module.incident_source.secret_token

  # REQUIRED for resource-sourced webhook credentials: the URL/token above are
  # unknown until apply, so the module's default `webhook_url != null` gate
  # cannot drive count. This plan-time-known bool gates the contact point
  # instead ("Invalid count argument" otherwise).
  webhook_configured = module.incident_source.enabled

  alert_labels = {
    team    = "platform"
    service = "example-workload"
  }
}

output "incident_source_id" {
  description = "Bind incident_alert_route alert_sources entries to this."
  value       = module.incident_source.id
}

output "alerting_notifications_enabled" {
  description = "True once rules route to the incident.io contact point."
  value       = module.alerting.notifications_enabled
}
