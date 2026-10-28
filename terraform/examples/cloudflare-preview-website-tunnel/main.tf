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

variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

variable "tunnel_secret" {
  type      = string
  sensitive = true
  default   = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
}

module "cloudflare_domain_baseline" {
  source = "../../modules/cloudflare-domain-baseline"

  zone_id         = var.zone_id
  ssl_mode        = "strict"
  min_tls_version = "1.2"
  dns_records     = []
}

module "cloudflare_preview_website" {
  source = "../../modules/cloudflare-preview-website"

  zone_id          = module.cloudflare_domain_baseline.zone_id
  account_id       = var.account_id
  tunnel_name      = "preview-example-tunnel"
  tunnel_secret    = var.tunnel_secret
  preview_hostname = "preview.example.com"
  origin_url       = "http://localhost:8080"
}

module "cloudflare_access_guard" {
  source = "../../modules/cloudflare-access-guard"

  zone_id               = module.cloudflare_domain_baseline.zone_id
  hostname              = module.cloudflare_preview_website.preview_hostname
  application_name      = "Preview Example"
  allowed_email_domains = ["example.com"]
}
