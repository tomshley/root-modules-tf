variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_mail_foundation" {
  source = "../../modules/cloudflare-mail-foundation"

  zone_id = var.zone_id

  mx_records = [
    {
      priority = 1
      value    = "aspmx.l.google.com"
    },
    {
      priority = 5
      value    = "alt1.aspmx.l.google.com"
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

  verification_records = [
    {
      name  = "google-site-verification"
      value = "verification-token"
    }
  ]
}
