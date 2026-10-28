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

module "cloudflare_domain_baseline" {
  source = "../../modules/cloudflare-domain-baseline"

  zone_id           = var.zone_id
  ssl_mode          = "strict"
  min_tls_version   = "1.2"
  email_obfuscation = true

  dns_records = [
    {
      name  = "example.com"
      type  = "A"
      value = "198.51.100.10"
    },
    {
      name  = "www.example.com"
      type  = "CNAME"
      value = "example.com"
    }
  ]
}

module "cloudflare_mail_foundation" {
  source = "../../modules/cloudflare-mail-foundation"

  zone_id = module.cloudflare_domain_baseline.zone_id

  mx_records = [
    {
      priority = 1
      value    = "aspmx.l.google.com"
    },
    {
      priority = 5
      value    = "alt1.aspmx.l.google.com"
    }
  ]

  spf_value = "v=spf1 include:_spf.google.com ~all"

  dkim_records = [
    {
      name  = "google._domainkey"
      type  = "CNAME"
      value = "google._domainkey.example-provider.com"
    }
  ]

  dmarc_value = "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"
}
