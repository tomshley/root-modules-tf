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

output "tunnel_id" {
  description = "Cloudflare Tunnel ID for the tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.preview.id
}

output "tunnel_cname" {
  description = "Canonical tunnel CNAME target shared by every published hostname."
  value       = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

output "preview_hostname" {
  description = "Hostname published through the legacy preview_hostname input, or null when unset."
  value       = local.normalized_preview_hostname
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID for the preview_hostname CNAME; null when preview_hostname is unset or manage_dns_records is false."
  value       = one(cloudflare_dns_record.preview[*].id)
}

output "hostnames" {
  description = "Every hostname published through the tunnel, sorted ascending."
  value       = sort([for e in local.all_entries : e.hostname])
}

output "dns_record_ids" {
  description = "Map of published hostname to Cloudflare DNS record ID, covering both preview_hostname and hostnames entries; empty when manage_dns_records is false."
  value = merge(
    { for r in cloudflare_dns_record.preview : local.normalized_preview_hostname => r.id },
    { for hostname, r in cloudflare_dns_record.published : hostname => r.id },
  )
}

output "tunnel_token" {
  description = "Connector token for the tunnel, present only when expose_tunnel_token is true."
  value       = one(data.cloudflare_zero_trust_tunnel_cloudflared_token.this[*].token)
  sensitive   = true
}
