resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = local.normalized_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "security_header" {
  zone_id    = local.normalized_zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = var.hsts_max_age > 0
      include_subdomains = var.hsts_include_subdomains
      max_age            = var.hsts_max_age
      preload            = var.hsts_preload
    }
  }
}

resource "cloudflare_zone_setting" "brotli" {
  zone_id    = local.normalized_zone_id
  setting_id = "brotli"
  value      = local.resolved_brotli ? "on" : "off"
}

resource "cloudflare_zone_setting" "polish" {
  zone_id    = local.normalized_zone_id
  setting_id = "polish"
  value      = local.resolved_polish
}

resource "cloudflare_zone_setting" "mirage" {
  zone_id    = local.normalized_zone_id
  setting_id = "mirage"
  value      = local.resolved_mirage ? "on" : "off"
}

resource "cloudflare_zone_setting" "early_hints" {
  zone_id    = local.normalized_zone_id
  setting_id = "early_hints"
  value      = local.resolved_early_hints ? "on" : "off"
}

resource "cloudflare_zone_setting" "bot_fight_mode" {
  zone_id    = local.normalized_zone_id
  setting_id = "bot_fight_mode"
  value      = var.enable_bot_fight_mode ? "on" : "off"
}

resource "cloudflare_ruleset" "cache" {
  zone_id     = local.normalized_zone_id
  name        = "Website acceleration cache rules"
  description = "Profile-based cache rules for static and immutable website assets"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "cache_immutable_assets"
      description = "Cache immutable fingerprinted static assets"
      expression  = local.immutable_assets_expression
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = local.resolved_edge_ttl_immutable
        }
        browser_ttl = {
          mode    = "override_origin"
          default = local.resolved_browser_ttl_immutable
        }
      }
    },
    {
      ref         = "cache_static_assets"
      description = "Cache common static assets"
      expression  = local.static_assets_expression
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = local.resolved_edge_ttl_static
        }
        browser_ttl = {
          mode    = "override_origin"
          default = local.resolved_browser_ttl_static
        }
      }
    }
  ]
}

resource "cloudflare_ruleset" "redirect" {
  count = length(local.redirect_rules) > 0 ? 1 : 0

  zone_id     = local.normalized_zone_id
  name        = "Website acceleration redirect rules"
  description = "Canonical host redirect rules"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    for rule in local.redirect_rules : {
      ref         = rule.ref
      description = rule.description
      expression  = rule.expression
      action      = "redirect"
      enabled     = true
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url = {
            expression = rule.target_url_expression
          }
        }
      }
    }
  ]
}
