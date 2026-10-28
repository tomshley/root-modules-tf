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

locals {
  normalized_zone_id = trimspace(var.zone_id)

  normalized_dns_records = {
    for index, record in var.dns_records : format("%03d-%s-%s", index, upper(record.type), lower(trimspace(record.name))) => {
      name    = trimspace(record.name)
      type    = upper(record.type)
      ttl     = record.ttl
      value   = try(record.value, null)
      proxied = contains(["A", "AAAA", "CNAME"], upper(record.type)) ? (record.proxied != null ? record.proxied : true) : null
      comment = try(record.comment, null)
      caa     = try(record.caa, null)
    }
  }

  proxied_dns_records = {
    for key, record in local.normalized_dns_records : key => record if contains(["A", "AAAA", "CNAME"], record.type)
  }

  txt_dns_records = {
    for key, record in local.normalized_dns_records : key => record if record.type == "TXT"
  }

  caa_dns_records = {
    for key, record in local.normalized_dns_records : key => record if record.type == "CAA"
  }
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = local.normalized_zone_id
  setting_id = "ssl"
  value      = var.ssl_mode
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = local.normalized_zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}

resource "cloudflare_zone_setting" "email_obfuscation" {
  zone_id    = local.normalized_zone_id
  setting_id = "email_obfuscation"
  value      = var.email_obfuscation ? "on" : "off"
}

resource "cloudflare_dns_record" "standard" {
  for_each = local.proxied_dns_records

  zone_id = local.normalized_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  content = each.value.value
  proxied = each.value.proxied
  comment = each.value.comment
}

resource "cloudflare_dns_record" "txt" {
  for_each = local.txt_dns_records

  zone_id = local.normalized_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  content = each.value.value
  comment = each.value.comment
}

resource "cloudflare_dns_record" "caa" {
  for_each = local.caa_dns_records

  zone_id = local.normalized_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  comment = each.value.comment

  data = {
    flags = try(each.value.caa.flags, 0)
    tag   = lower(each.value.caa.tag)
    value = each.value.caa.value
  }
}

resource "cloudflare_origin_ca_certificate" "this" {
  for_each = var.origin_ca == null ? {} : { default = var.origin_ca }

  csr                = each.value.csr
  hostnames          = each.value.hostnames
  request_type       = each.value.request_type
  requested_validity = each.value.requested_validity
}
