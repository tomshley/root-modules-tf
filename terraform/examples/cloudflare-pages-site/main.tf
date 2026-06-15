variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_pages_site" {
  source = "../../modules/cloudflare-pages-site"

  account_id   = var.account_id
  project_name = "example-landing-site"

  custom_domains = [
    {
      hostname = "example.com"
      zone_id  = var.zone_id
      comment  = "Example apex"
    },
    {
      hostname = "www.example.com"
      zone_id  = var.zone_id
      comment  = "Example www"
    },
  ]
}

output "project_subdomain" {
  value = module.cloudflare_pages_site.project_subdomain
}
