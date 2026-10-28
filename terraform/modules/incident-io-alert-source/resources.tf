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

# incident.io alert source as code.
#
# The one non-obvious piece this module owns: the default title/description
# templates. incident.io stores them as rich-text "engine expression"
# documents — the TipTap JSON its web editor generates — where a varSpec node
# references a payload attribute. The literals below are semantically
# equivalent to what the UI produces for the default Payload -> Title /
# Payload -> Description bindings — jsonencode() orders keys lexicographically
# rather than in the UI's insertion order, and the provider's >= 5.39 semantic
# JSON comparison is what keeps plans stable despite that — which is what
# Grafana webhook payloads (and most webhook sources) want. Anything richer:
# author in the UI, use its Terraform Export flow, and feed the result through
# var.title_template / var.description_template / var.attributes /
# var.expressions.
#
# ROTATION NOTE: rotating the provider's API key does NOT rotate this source's
# secret_token — the token is a resource attribute. To force a new token,
# taint/replace this resource; consumers wired through state (e.g. Grafana
# contact points taking the outputs below) pick up the replacement on the same
# apply. Treat both outputs as secrets: alert_events_url + secret_token
# together are sufficient to inject alerts.

locals {
  default_title_template = jsonencode({
    type = "doc"
    content = [
      {
        type = "paragraph"
        content = [
          {
            type = "varSpec"
            attrs = {
              label   = "Payload → Title"
              missing = false
              name    = "title"
            }
          },
        ]
      },
    ]
  })

  default_description_template = jsonencode({
    type = "doc"
    content = [
      {
        type = "paragraph"
        content = [
          {
            type = "varSpec"
            attrs = {
              label   = "Payload → Description"
              missing = false
              name    = "description"
            }
          },
        ]
      },
    ]
  })
}

resource "incident_alert_source" "this" {
  count = var.enabled ? 1 : 0

  name        = var.name
  source_type = var.source_type

  auto_resolve_timeout_minutes = var.auto_resolve_timeout_minutes

  template = {
    title = {
      literal = coalesce(var.title_template, local.default_title_template)
    }

    description = {
      literal = coalesce(var.description_template, local.default_description_template)
    }

    attributes  = var.attributes
    expressions = var.expressions

    is_private = var.is_private
  }
}
