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

output "zone_id" {
  description = "Configured Cloudflare zone ID."
  value       = local.normalized_zone_id
}

output "dns_record_ids" {
  description = "Map of deterministic DNS record keys to Cloudflare DNS record IDs."
  value = merge(
    {
      for key, record in cloudflare_dns_record.standard : key => record.id
    },
    {
      for key, record in cloudflare_dns_record.txt : key => record.id
    },
    {
      for key, record in cloudflare_dns_record.caa : key => record.id
    }
  )
}

output "origin_ca_certificate" {
  description = "Origin CA certificate PEM when origin_ca is configured, otherwise null."
  value       = try(one([for certificate in cloudflare_origin_ca_certificate.this : certificate.certificate]), null)
  sensitive   = true
}
