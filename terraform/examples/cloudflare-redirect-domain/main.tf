variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_redirect_domain" {
  source = "../../modules/cloudflare-redirect-domain"

  zone_name       = "legacy-example.com"
  account_id      = var.account_id
  redirect_target = "example.com"
  redirect_code   = 301
  preserve_path   = true
  preserve_query  = true
}
