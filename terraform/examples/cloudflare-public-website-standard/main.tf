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
  performance_profile = "standard"
  canonical_redirect  = "www-to-apex"
}

module "cloudflare_mail_foundation" {
  source = "../../modules/cloudflare-mail-foundation"

  zone_id = module.cloudflare_domain_baseline.zone_id

  mx_records = [
    {
      priority = 1
      value    = "aspmx.l.google.com"
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
