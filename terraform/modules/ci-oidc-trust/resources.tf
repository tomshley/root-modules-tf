# This module creates no resources. It owns the CI OIDC federation contract:
# it normalizes and validates the issuer, audiences, and trust conditions
# once, so every per-platform implementation module (aws-*, gcp-*, azure-*)
# is an adapter that translates the normalized trust object into its
# platform's native grammar instead of re-defining the contract.

locals {
  # Issuer normalization: no trailing slash; host preserves multi-segment
  # issuer paths (e.g. a workspace-scoped issuer), which platforms that key
  # trust conditions by issuer host require verbatim.
  issuer_url  = trimsuffix(var.issuer_url, "/")
  issuer_host = trimprefix(local.issuer_url, "https://")

  conditions = [
    for c in var.conditions : {
      claim  = c.claim
      match  = c.match
      values = c.values
    }
  ]

  exact_conditions    = [for c in local.conditions : c if c.match == "exact"]
  wildcard_conditions = [for c in local.conditions : c if c.match == "wildcard"]
}
