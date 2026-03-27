locals {
  normalized_zone_id               = var.zone_id != null ? trimspace(var.zone_id) : null
  normalized_account_id            = var.account_id != null ? trimspace(var.account_id) : null
  normalized_hostname              = lower(trimspace(var.hostname))
  normalized_application_name      = trimspace(var.application_name)
  normalized_session_duration      = trimspace(var.session_duration)
  normalized_allowed_emails        = distinct([for email in var.allowed_emails : lower(trimspace(email)) if trimspace(email) != ""])
  normalized_allowed_email_domains = distinct([for domain in var.allowed_email_domains : lower(trimspace(domain)) if trimspace(domain) != ""])
  inline_policy_include = concat(
    [for email in local.normalized_allowed_emails : { email = { email = email } }],
    [for domain in local.normalized_allowed_email_domains : { email_domain = { domain = domain } }]
  )
}

resource "cloudflare_zero_trust_access_application" "guard" {
  zone_id                   = local.normalized_account_id == null ? local.normalized_zone_id : null
  account_id                = local.normalized_account_id
  name                      = local.normalized_application_name
  domain                    = local.normalized_hostname
  type                      = "self_hosted"
  session_duration          = local.normalized_session_duration
  auto_redirect_to_identity = false

  policies = [
    {
      name       = format("%s allow policy", local.normalized_application_name)
      decision   = "allow"
      include    = local.inline_policy_include
      precedence = 1
    }
  ]

  lifecycle {
    precondition {
      condition     = local.normalized_zone_id != null || local.normalized_account_id != null
      error_message = "At least one of zone_id or account_id must be provided."
    }
    precondition {
      condition     = !(local.normalized_zone_id != null && local.normalized_account_id != null)
      error_message = "Provide zone_id or account_id, not both. When account_id is set the Access application is managed at account level."
    }
    precondition {
      condition     = length(local.normalized_allowed_emails) > 0 || length(local.normalized_allowed_email_domains) > 0
      error_message = "At least one of allowed_emails or allowed_email_domains must contain a non-empty value."
    }
  }
}
