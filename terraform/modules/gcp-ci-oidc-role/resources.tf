# GCP implementation of the ci-oidc-trust contract: creates a Workload
# Identity Pool and OIDC provider for a CI platform and mints a federated
# service account from the normalized trust object. Carries NO Kubernetes
# coupling — this is the identity for pipelines that exist before, or
# independent of, any cluster (infrastructure provisioning being the
# canonical case). Cluster-binding compositions layer on top of this module.

locals {
  pool_id            = coalesce(var.pool_id, "${var.project_name_prefix}-ci-pool")
  provider_id        = coalesce(var.provider_id, "${var.project_name_prefix}-ci-oidc")
  service_account_id = "${var.project_name_prefix}-ci-${var.role_name_suffix}"

  # Empty audiences means the platform default, which on GCP is the issuer
  # URL itself.
  effective_audiences = length(var.audiences) > 0 ? var.audiences : [module.trust.issuer_url]
}

module "trust" {
  source = "../ci-oidc-trust"

  issuer_url = var.issuer_url
  audiences  = var.audiences
  conditions = var.conditions
}

locals {
  # Contract translation: the conditions list becomes one CEL
  # attribute_condition. The contract's combination semantics are preserved
  # structurally — every condition contributes one alternative group joined
  # by && (AND across entries), while a condition's values are joined by ||
  # (OR within a condition) and parenthesized so the grouping survives.

  # Glob-to-RE2 character table: * and ? are the glob operators and map to
  # .* and . — every OTHER RE2 metacharacter in a literal segment is
  # escaped. GitLab-style claims carry / : . and -; only . among them needs
  # escaping, and the table keeps every translation auditable in one place.
  glob_to_re2 = {
    "*"  = ".*"
    "?"  = "."
    "."  = "\\."
    "^"  = "\\^"
    "$"  = "\\$"
    "+"  = "\\+"
    "("  = "\\("
    ")"  = "\\)"
    "["  = "\\["
    "]"  = "\\]"
    "{"  = "\\{"
    "}"  = "\\}"
    "|"  = "\\|"
    "\\" = "\\\\"
  }

  # Per (condition, value) CEL fragment, order-preserved. Both arms route
  # through the same CEL string-literal escape — backslashes doubled first
  # (CEL reads \\ as one backslash, so the RE2 escapes produced above arrive
  # intact), then single quotes — so a literal quote or backslash in a value
  # can neither break the expression nor alter its meaning. Wildcard values
  # are converted character-by-character through glob_to_re2, then anchored
  # ^...$ because CEL matches() is a substring match.
  condition_alternatives = [
    for c in module.trust.conditions : [
      for v in c.values : (
        c.match == "exact"
        ? "assertion.${c.claim} == '${replace(replace(v, "\\", "\\\\"), "'", "\\'")}'"
        : "assertion.${c.claim}.matches('^${replace(replace(join("", [
          for i in range(length(v)) : lookup(local.glob_to_re2, substr(v, i, 1), substr(v, i, 1))
        ]), "\\", "\\\\"), "'", "\\'")}$')"
      )
    ]
  ]

  condition_expressions = [
    for alternatives in local.condition_alternatives :
    length(alternatives) > 1 ? "(${join(" || ", alternatives)})" : alternatives[0]
  ]

  attribute_condition = join(" && ", local.condition_expressions)
}

resource "google_iam_workload_identity_pool" "ci" {
  project                   = var.project_id
  workload_identity_pool_id = local.pool_id
  display_name              = local.pool_id

  lifecycle {
    # Explicit pool_id values are validated on the variable; this guards the
    # derived name so a long or malformed project_name_prefix fails here with
    # the offending value named, not inside an API error at apply.
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", local.pool_id)) && !startswith(local.pool_id, "gcp-")
      error_message = "Workload identity pool ID '${local.pool_id}' violates GCP's rules: 4-32 characters of lowercase letters, digits and hyphens, starting with a letter, never with 'gcp-'. Set pool_id explicitly or shorten project_name_prefix."
    }
  }
}

resource "google_iam_workload_identity_pool_provider" "ci" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = local.provider_id
  display_name                       = local.provider_id

  attribute_mapping   = var.attribute_mapping
  attribute_condition = local.attribute_condition

  oidc {
    issuer_uri        = module.trust.issuer_url
    allowed_audiences = local.effective_audiences
  }

  lifecycle {
    # Defense in depth: the contract currently admits only exact and
    # wildcard. If it ever grows a kind this adapter does not translate,
    # fail loudly here rather than silently dropping the condition.
    precondition {
      condition = alltrue([
        for c in module.trust.conditions : contains(["exact", "wildcard"], c.match)
      ])
      error_message = "gcp-ci-oidc-role translates only 'exact' and 'wildcard' match kinds into CEL — an untranslatable condition must be rejected, never weakened."
    }

    # Conditions are emitted as assertion.{claim}; a claim that is not a
    # valid CEL identifier would corrupt the expression or change its
    # meaning, so it is rejected at plan time.
    precondition {
      condition = alltrue([
        for c in module.trust.conditions : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", c.claim))
      ])
      error_message = "conditions[*].claim must be a CEL-safe identifier (letters, digits, underscore; not starting with a digit) — GCP addresses claims as assertion.{claim}."
    }

    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", local.provider_id)) && !startswith(local.provider_id, "gcp-")
      error_message = "Workload identity provider ID '${local.provider_id}' violates GCP's rules: 4-32 characters of lowercase letters, digits and hyphens, starting with a letter, never with 'gcp-'. Set provider_id explicitly or shorten project_name_prefix."
    }
  }
}

resource "google_service_account" "ci_deploy" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = local.service_account_id
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.ci_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/*"
}

resource "google_project_iam_member" "ci_deploy" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci_deploy.email}"
}
