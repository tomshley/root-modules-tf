locals {
  performance_profiles = {
    standard = {
      edge_ttl_static       = 14400
      browser_ttl_static    = 3600
      edge_ttl_immutable    = 2592000
      browser_ttl_immutable = 604800
      brotli                = true
      polish                = "off"
      mirage                = false
      early_hints           = false
    }
    aggressive = {
      edge_ttl_static       = 2592000
      browser_ttl_static    = 604800
      edge_ttl_immutable    = 31536000
      browser_ttl_immutable = 31536000
      brotli                = true
      polish                = "lossless"
      mirage                = true
      early_hints           = true
    }
  }

  selected_profile = local.performance_profiles[var.performance_profile]

  resolved_edge_ttl_static       = coalesce(var.edge_ttl_static, local.selected_profile.edge_ttl_static)
  resolved_browser_ttl_static    = coalesce(var.browser_ttl_static, local.selected_profile.browser_ttl_static)
  resolved_edge_ttl_immutable    = coalesce(var.edge_ttl_immutable, local.selected_profile.edge_ttl_immutable)
  resolved_browser_ttl_immutable = coalesce(var.browser_ttl_immutable, local.selected_profile.browser_ttl_immutable)
  resolved_brotli                = coalesce(var.enable_brotli, local.selected_profile.brotli)
  resolved_polish                = coalesce(var.enable_polish, local.selected_profile.polish)
  resolved_mirage                = coalesce(var.enable_mirage, local.selected_profile.mirage)
  resolved_early_hints           = coalesce(var.enable_early_hints, local.selected_profile.early_hints)

  immutable_assets_expression = "lower(http.request.uri.path) matches \".*[-_.][0-9a-f]{8,}\\.(css|js|svg|woff2)$\""
  static_assets_expression    = "(ends_with(lower(http.request.uri.path), \".css\") or ends_with(lower(http.request.uri.path), \".js\") or ends_with(lower(http.request.uri.path), \".svg\") or ends_with(lower(http.request.uri.path), \".woff2\")) and not (${local.immutable_assets_expression})"

  redirect_rules = var.canonical_redirect == "www-to-apex" ? [
    {
      ref                   = "canonical_www_to_apex"
      description           = "Redirect www host to zone apex"
      expression            = "http.host eq concat(\"www.\", cf.zone.name)"
      target_url_expression = "concat(\"https://\", cf.zone.name, http.request.uri.path)"
    }
    ] : var.canonical_redirect == "apex-to-www" ? [
    {
      ref                   = "canonical_apex_to_www"
      description           = "Redirect zone apex to www host"
      expression            = "http.host eq cf.zone.name"
      target_url_expression = "concat(\"https://www.\", cf.zone.name, http.request.uri.path)"
    }
  ] : []
}
