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

output "project_id" {
  description = "Cloudflare Pages project ID."
  value       = cloudflare_pages_project.this.id
}

output "project_name" {
  description = "Cloudflare Pages project name."
  value       = cloudflare_pages_project.this.name
}

output "project_subdomain" {
  description = "Default pages.dev subdomain for the project."
  value       = cloudflare_pages_project.this.subdomain
}

output "custom_domains" {
  description = "Custom domains attached to the project."
  value       = [for _, d in cloudflare_pages_domain.custom : d.name]
}

output "custom_domain_dns_record_ids" {
  description = "Cloudflare DNS record IDs for custom-domain CNAME records managed by this module."
  value       = { for hostname, record in cloudflare_dns_record.custom_domain_cname : hostname => record.id }
}
