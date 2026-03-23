locals {
  normalized_zone_name      = lower(trimspace(var.zone_name))
  normalized_redirect_host  = lower(trimspace(var.redirect_target))
  redirect_rule_ref         = format("redirect_%s", substr(sha256(local.normalized_zone_name), 0, 12))
  redirect_target_expression = var.preserve_path ? format("concat(\"https://%s\", http.request.uri.path)", local.normalized_redirect_host) : format("\"https://%s/\"", local.normalized_redirect_host)
  redirect_match_expression  = format("(http.host eq \"%s\" or http.host eq \"www.%s\")", local.normalized_zone_name, local.normalized_zone_name)
}

resource "cloudflare_zone" "redirect" {
  account = {
    id = trimspace(var.account_id)
  }

  name = local.normalized_zone_name
}

resource "cloudflare_dns_record" "apex_placeholder" {
  zone_id = cloudflare_zone.redirect.id
  name    = "@"
  type    = "A"
  ttl     = 1
  proxied = true
  content = "192.0.2.1"
}

resource "cloudflare_dns_record" "www_placeholder" {
  zone_id = cloudflare_zone.redirect.id
  name    = "www"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  content = local.normalized_zone_name
}

resource "cloudflare_ruleset" "redirect" {
  zone_id     = cloudflare_zone.redirect.id
  name        = format("Redirect domain rules for %s", local.normalized_zone_name)
  description = format("Enable redirect behavior for %s", local.normalized_zone_name)
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    {
      ref         = local.redirect_rule_ref
      description = format("Redirect requests for %s", local.normalized_zone_name)
      expression  = local.redirect_match_expression
      action      = "redirect"
      enabled     = true
      action_parameters = {
        from_value = {
          status_code           = var.redirect_code
          preserve_query_string = var.preserve_query
          target_url = {
            expression = local.redirect_target_expression
          }
        }
      }
    }
  ]

  depends_on = [
    cloudflare_dns_record.apex_placeholder,
    cloudflare_dns_record.www_placeholder
  ]
}
