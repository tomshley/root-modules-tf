variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

variable "tunnel_secret" {
  type      = string
  sensitive = true
  default   = "AQIDBAUGBwgBAgMEBQYHCAECAwQFBgcIAQIDBAUGBwg="
}

module "cloudflare_preview_website" {
  source = "../../modules/cloudflare-preview-website"

  account_id    = var.account_id
  tunnel_name   = "multi-hostname-example-tunnel"
  tunnel_secret = var.tunnel_secret
  origin_url    = "http://localhost:8080"

  # One tunnel serves hostnames across two zones; each entry names its own
  # zone and may override the shared origin_url.
  hostnames = [
    {
      hostname = "alpha.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
    {
      hostname   = "beta.example.org"
      zone_id    = "00000000000000000000000000000002"
      origin_url = "http://localhost:9090"
    },
    {
      hostname = "staging.example.com"
      zone_id  = "00000000000000000000000000000001"
    },
  ]
}
