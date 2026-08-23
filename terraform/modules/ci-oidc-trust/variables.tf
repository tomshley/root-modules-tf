variable "issuer_url" {
  type        = string
  nullable    = false
  description = "OIDC issuer URL of the CI platform (e.g. https://gitlab.com, https://token.actions.githubusercontent.com). Multi-segment issuer paths are preserved (e.g. Bitbucket workspace issuers)."

  validation {
    condition     = can(regex("^https://", var.issuer_url))
    error_message = "issuer_url must start with 'https://' — OIDC discovery requires TLS."
  }

  validation {
    condition     = trimspace(var.issuer_url) == var.issuer_url
    error_message = "issuer_url must not contain leading or trailing whitespace."
  }
}

variable "audiences" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Allowed audiences (aud) for tokens presented by the CI platform. Empty means the implementation module applies its platform-appropriate default; entries given here are passed through verbatim."

  validation {
    condition = alltrue([
      for a in var.audiences : a != "" && a == trimspace(a)
    ])
    error_message = "audiences entries must be non-empty and carry no leading/trailing whitespace."
  }
}

variable "conditions" {
  type = list(object({
    claim  = string
    match  = string
    values = list(string)
  }))
  nullable    = false
  description = <<-EOT
    Trust conditions restricting which CI workloads may assume the resulting
    identity. Each entry names a token claim, a match kind, and the allowed
    values. match is one of:
      - "exact":    the claim must equal one of the values verbatim
      - "wildcard": values may use * (any sequence) and ? (any single
                    character) glob syntax
    Combination semantics are part of the contract: ALL conditions must hold
    simultaneously (logical AND across entries), while the values within one
    condition are alternatives (logical OR). Implementation modules translate
    this shape into their platform's native trust grammar (e.g. equality and
    pattern operators in an IAM trust policy, attribute conditions elsewhere)
    and MUST preserve these semantics. A platform that cannot express a match
    kind MUST reject it at plan time rather than weaken it.
  EOT

  validation {
    condition     = length(var.conditions) > 0
    error_message = "At least one condition is required — an unconditioned federation trusts every workload on the issuer."
  }

  validation {
    condition = alltrue([
      for c in var.conditions : contains(["exact", "wildcard"], c.match)
    ])
    error_message = "conditions[*].match must be \"exact\" or \"wildcard\"."
  }

  validation {
    condition = alltrue([
      for c in var.conditions : c.claim != "" && c.claim == trimspace(c.claim)
    ])
    error_message = "conditions[*].claim must be non-empty and carry no leading/trailing whitespace."
  }

  validation {
    condition = alltrue([
      for c in var.conditions : length(c.values) > 0
    ])
    error_message = "conditions[*].values must contain at least one entry."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.conditions : [
        for v in c.values : v != "" && v == trimspace(v)
      ]
    ]))
    error_message = "conditions[*].values entries must be non-empty and carry no leading/trailing whitespace."
  }

  validation {
    condition = length(var.conditions) == length(distinct([
      for c in var.conditions : "${c.match}:${c.claim}"
    ]))
    error_message = "conditions must not repeat a claim+match combination — merge the allowed values into a single entry's values list."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.conditions : [
        for v in c.values :
        c.match != "exact" || (!strcontains(v, "*") && !strcontains(v, "?"))
      ]
    ]))
    error_message = "conditions with match = \"exact\" must not contain * or ? in their values — use match = \"wildcard\" for glob patterns, so a pattern is never silently compared verbatim."
  }

  validation {
    condition = alltrue([
      for c in var.conditions :
      c.match != "wildcard" || anytrue([
        for v in c.values : strcontains(v, "*") || strcontains(v, "?")
      ])
    ])
    error_message = "conditions with match = \"wildcard\" must contain at least one value using * or ? — an all-literal wildcard condition is an exact condition and must say so."
  }
}
