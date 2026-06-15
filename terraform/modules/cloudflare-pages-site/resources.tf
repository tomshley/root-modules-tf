locals {
  normalized_account_id        = trimspace(var.account_id)
  normalized_project_name      = trimspace(var.project_name)
  normalized_production_branch = trimspace(var.production_branch)

  normalized_custom_domains = {
    for d in var.custom_domains : lower(trimspace(d.hostname)) => {
      hostname          = lower(trimspace(d.hostname))
      zone_id           = d.zone_id == null ? null : trimspace(d.zone_id)
      create_dns_record = try(d.create_dns_record, true)
      proxied           = try(d.proxied, true)
      comment           = try(d.comment, null)
    }
  }

  custom_domains_with_dns = {
    for hostname, d in local.normalized_custom_domains : hostname => d if d.create_dns_record
  }
}

resource "cloudflare_pages_project" "this" {
  account_id        = local.normalized_account_id
  name              = local.normalized_project_name
  production_branch = local.normalized_production_branch
  build_config      = var.build_config

  # Git integration is intentionally not managed by this module: the provider's
  # `source` (repo connection) and `deployment_configs` (env vars, bindings,
  # preview/production settings) blocks are not exposed. This module targets
  # direct-upload workflows (for example CI `wrangler pages deploy`) plus
  # `build_config`. To support git-driven builds, add `source` and
  # `deployment_configs` here and surface them as module variables.
}

resource "cloudflare_pages_domain" "custom" {
  for_each = local.normalized_custom_domains

  account_id   = local.normalized_account_id
  project_name = cloudflare_pages_project.this.name
  name         = each.value.hostname

  # Attach only after the module-managed CNAME exists so Cloudflare verifies the
  # domain within a single apply (no plan/apply, then plan/apply cycle).
  depends_on = [cloudflare_dns_record.custom_domain_cname]
}

resource "cloudflare_dns_record" "custom_domain_cname" {
  for_each = local.custom_domains_with_dns

  zone_id = each.value.zone_id
  name    = each.value.hostname
  type    = "CNAME"
  ttl     = 1
  proxied = each.value.proxied
  content = cloudflare_pages_project.this.subdomain
  comment = each.value.comment
}
