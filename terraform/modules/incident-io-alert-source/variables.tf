variable "enabled" {
  description = "Master switch / provider-readiness gate (count-gating convention shared across this repo). The caller must pass false whenever the incident provider is not yet configured with a real API key, so cold-start / credential-less plans create nothing and never touch the incident.io API."
  type        = bool
  default     = true
}

variable "name" {
  description = "Unique (per incident.io organization) display name of the alert source, e.g. \"acme staging Grafana\". Include the environment in the name when creating one source per environment."
  type        = string
}

variable "source_type" {
  description = "incident.io alert source type. \"grafana\" accepts Grafana's webhook contact-point payload natively; \"http\" is the generic HTTP source for custom producers; other webhook-style types (e.g. \"cloudwatch\") work identically. Integration-based types (jira, email) do not fit this module's webhook contract — their events arrive through native integrations, not alert_events_url."
  type        = string
  default     = "grafana"

  validation {
    condition     = length(var.source_type) > 0
    error_message = "source_type must be a non-empty incident.io alert source type, e.g. \"grafana\" or \"http\"."
  }
}

# --- Payload template ------------------------------------------------------
# incident.io renders alert title/description from the source payload via
# rich-text "engine expression" documents (the same TipTap/varSpec JSON the
# web editor generates). The defaults below bind Payload -> Title and
# Payload -> Description — correct for Grafana webhook payloads and for any
# webhook source whose payload carries title/description attributes. Override
# only for custom payload shapes; the easiest authoring path for anything
# fancier is: build the source in the incident.io UI, use its Terraform
# "Export" flow, and paste the generated template into these inputs.

variable "title_template" {
  description = "Rich-text engine-expression document (JSON string) for the alert title. Null uses the module default: bind the payload's `title` attribute (Payload -> Title). An empty string also falls back to the default (coalesce() skips \"\"). Author complex templates in the incident.io UI and copy from its Terraform export."
  type        = string
  default     = null
}

variable "description_template" {
  description = "Rich-text engine-expression document (JSON string) for the alert description. Null uses the module default: bind the payload's `description` attribute (Payload -> Description). An empty string also falls back to the default (coalesce() skips \"\"). Author complex templates in the incident.io UI and copy from its Terraform export."
  type        = string
  default     = null
}

variable "attributes" {
  description = "Alert attribute bindings (template.attributes) to set on alerts from this source — e.g. binding payload fields or expressions to catalog-backed attributes used by alert-route conditions. Shape follows the incident_alert_source resource schema. Default: none. Authoring tip: attributes usually reference incident_alert_attribute IDs (data source or resource) and pair with entries in `expressions`."
  type = set(object({
    alert_attribute_id = string
    binding = object({
      merge_strategy = optional(string)
      value = optional(object({
        literal   = optional(string)
        reference = optional(string)
      }))
      array_value = optional(list(object({
        literal   = optional(string)
        reference = optional(string)
      })))
    })
  }))
  default = []
}

variable "expressions" {
  description = "Template expressions (template.expressions) available to attribute bindings — e.g. parsing a team slug out of the payload for routing. Passed through verbatim as a raw structure because the upstream schema is deep and evolves; author in the incident.io UI and paste from its Terraform export. Default: none."
  type        = any
  default     = []
}

variable "is_private" {
  description = "Whether alerts produced by this source are private (visible only per incident.io's private-alert rules). Maps to template.is_private; null leaves the platform default."
  type        = bool
  default     = null
}

variable "auto_resolve_timeout_minutes" {
  description = "When set, alerts from this source auto-resolve after this many minutes without updates. Null (default) disables timeout-based auto-resolution. Useful for sources whose producers cannot send resolve events."
  type        = number
  default     = null
}
