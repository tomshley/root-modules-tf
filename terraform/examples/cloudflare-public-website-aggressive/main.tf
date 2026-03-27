variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_domain_baseline" {
  source = "../../modules/cloudflare-domain-baseline"

  zone_id         = var.zone_id
  ssl_mode        = "strict"
  min_tls_version = "1.2"

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

module "cloudflare_website_acceleration" {
  source = "../../modules/cloudflare-website-acceleration"

  zone_id             = module.cloudflare_domain_baseline.zone_id
  performance_profile = "aggressive"
  canonical_redirect  = "www-to-apex"
}
