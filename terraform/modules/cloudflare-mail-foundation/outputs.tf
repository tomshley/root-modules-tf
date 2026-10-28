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

output "mx_record_ids" {
  description = "Cloudflare DNS record IDs for MX records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.mx)) : cloudflare_dns_record.mx[key].id]
}

output "spf_record_id" {
  description = "Cloudflare DNS record ID for the SPF TXT record."
  value       = cloudflare_dns_record.spf.id
}

output "dkim_record_ids" {
  description = "Cloudflare DNS record IDs for DKIM records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.dkim)) : cloudflare_dns_record.dkim[key].id]
}

output "dmarc_record_id" {
  description = "Cloudflare DNS record ID for the DMARC TXT record."
  value       = cloudflare_dns_record.dmarc.id
}

output "verification_record_ids" {
  description = "Cloudflare DNS record IDs for verification TXT records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.verification)) : cloudflare_dns_record.verification[key].id]
}
