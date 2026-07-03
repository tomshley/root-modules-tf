# incident-io-alert-source — provider contract
#
# Companion module to grafana-cloud-alerting: that module ends at "give me a
# webhook URL + bearer token for the contact points"; this module produces
# those two values as code by owning the incident.io alert source itself.
# Kept as a SEPARATE module (not folded into grafana-cloud-alerting) because a
# module's required_providers forces every consumer to install the provider —
# consumers who route alerts elsewhere (PagerDuty, Opsgenie, plain Slack
# webhooks) should not have to init the incident.io provider.
#
# AUTH: the incident.io provider needs an API key (inc_…) created at
# incident.io -> Settings -> API keys. Two permission bundles are sufficient
# and least-privilege for this module:
#   - "View data, like public incidents and organization settings"
#     (baseline reads for lookups/drift detection)
#   - "Create and manage on-call resources"
#     (the bundle that owns alert sources, alert routes, schedules,
#      escalation paths)
# "Create and manage escalations" is TRIGGERING live escalations — not needed.
# Only add "Manage organization settings" if you later manage alert
# ATTRIBUTES (org-level alert schema) from Terraform and the plan 403s.
#
# Configure the provider at the caller/root layer, e.g.:
#
#   provider "incident" {
#     api_key = var.incident_io_api_key   # null-safe while count-gated off
#   }

terraform {
  required_version = ">= 1.3"

  required_providers {
    incident = {
      source = "incident-io/incident"
      # >= 5.39 : semantic (not byte-wise) equality for engine param-binding
      #           `literal` JSON — required by the jsonencode()'d default
      #           templates in resources.tf, whose key order differs from the
      #           API's serialization; earlier releases risk perpetual diffs /
      #           "inconsistent result after apply" on the templates. (The
      #           other features used here are older: alert_events_url /
      #           secret_token exports landed in 5.33,
      #           auto_resolve_timeout_minutes in 5.29.)
      # <  6.0  : bump deliberately after re-testing template plan stability;
      #           do not let it float across a major.
      version = ">= 5.39.0, < 6.0.0"
    }
  }
}
