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

variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_pages_site" {
  source = "../../modules/cloudflare-pages-site"

  account_id   = var.account_id
  project_name = "example-landing-site"

  custom_domains = [
    {
      hostname = "example.com"
      zone_id  = var.zone_id
      comment  = "Example apex"
    },
    {
      hostname = "www.example.com"
      zone_id  = var.zone_id
      comment  = "Example www"
    },
  ]
}

output "project_subdomain" {
  value = module.cloudflare_pages_site.project_subdomain
}
