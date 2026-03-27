locals {
  normalized_zone_id = trimspace(var.zone_id)

  normalized_mx_records = {
    for index, record in var.mx_records : format("%03d-%d-%s", index, record.priority, lower(trimspace(record.value))) => {
      priority = record.priority
      value    = trimspace(record.value)
    }
  }

  normalized_dkim_records = {
    for index, record in var.dkim_records : format("%03d-%s-%s", index, upper(record.type), lower(trimspace(record.name))) => {
      name  = trimspace(record.name)
      type  = upper(record.type)
      value = trimspace(record.value)
    }
  }

  normalized_verification_records = {
    for index, record in var.verification_records : format("%03d-%s", index, lower(trimspace(record.name))) => {
      name  = trimspace(record.name)
      value = trimspace(record.value)
    }
  }
}

resource "cloudflare_dns_record" "mx" {
  for_each = local.normalized_mx_records

  zone_id  = local.normalized_zone_id
  name     = "@"
  type     = "MX"
  ttl      = 1
  priority = each.value.priority
  content  = each.value.value
}

resource "cloudflare_dns_record" "spf" {
  zone_id = local.normalized_zone_id
  name    = "@"
  type    = "TXT"
  ttl     = 1
  content = trimspace(var.spf_value)
}

resource "cloudflare_dns_record" "dkim" {
  for_each = local.normalized_dkim_records

  zone_id = local.normalized_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 1
  content = each.value.value
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.normalized_zone_id
  name    = "_dmarc"
  type    = "TXT"
  ttl     = 1
  content = trimspace(var.dmarc_value)
}

resource "cloudflare_dns_record" "verification" {
  for_each = local.normalized_verification_records

  zone_id = local.normalized_zone_id
  name    = each.value.name
  type    = "TXT"
  ttl     = 1
  content = each.value.value
}
