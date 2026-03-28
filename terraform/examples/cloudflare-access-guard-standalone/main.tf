variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_access_guard" {
  source = "../../modules/cloudflare-access-guard"

  zone_id               = var.zone_id
  hostname              = "app.example.com"
  application_name      = "Standalone Access Guard"
  allowed_email_domains = ["example.com"]
}
