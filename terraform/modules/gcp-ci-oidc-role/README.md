# GCP CI OIDC Role

GCP implementation of the [ci-oidc-trust](../ci-oidc-trust/README.md)
contract: creates a Workload Identity Pool and OIDC provider for a CI
platform and mints a federated service account from the normalized trust
object. The conditions list becomes a single CEL `attribute_condition` —
`exact` conditions become equality on `assertion.{claim}`, `wildcard`
conditions become anchored RE2 `.matches()` — and the contract's
combination semantics are preserved: all conditions must hold (AND across
entries), values within a condition are alternatives (OR).

This module carries **no Kubernetes coupling**. It is the identity for
pipelines that exist before, or independent of, any cluster —
infrastructure provisioning being the canonical case (the pipeline that
*creates* the cluster cannot depend on one). Where a pipeline also needs
Kubernetes API access, compose a cluster-binding module on top (on GKE:
[gcp-gke-ci-oidc-access](../gcp-gke-ci-oidc-access/README.md)).

The provider is always created: GCP allows several OIDC providers per
workload identity pool, so there is no single-provider-per-issuer
constraint to reuse around (unlike AWS's one provider per issuer per
account).

## Condition translation

- `exact` → `assertion.{claim} == 'value'`, OR'd across the condition's
  values.
- `wildcard` → `assertion.{claim}.matches('^{re2}$')`. Glob `*` becomes
  `.*` and `?` becomes `.`; every other RE2 metacharacter in a literal
  segment is escaped, so a pattern only ever widens where a glob operator
  stands. The regex is anchored because CEL `matches()` is a substring
  match.
- Conditions join with `&&`; multi-value groups are parenthesized.
- Claims are emitted as `assertion.{claim}`, so every claim must be a
  CEL-safe identifier (letters, digits, underscore; not starting with a
  digit) — anything else is rejected at plan time, as is any match kind
  the adapter does not translate.

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| project_id | GCP project the pool, provider and service account live in | `string` | yes | — |
| project_name_prefix | Project name prefix for resource naming | `string` | yes | — |
| role_name_suffix | Service account suffix; final ID `{prefix}-ci-{suffix}` | `string` | yes | — |
| issuer_url | CI platform issuer URL; the provider is always created | `string` | no | `null` |
| audiences | Allowed audiences; empty applies the issuer URL | `list(string)` | no | `[]` |
| conditions | Trust conditions in the ci-oidc-trust shape (`claim`, `match = "exact"\|"wildcard"`, `values`) | `list(object)` | yes | — |
| project_roles | GCP roles granted to the service account on project_id | `list(string)` | no | `[]` |
| pool_id | Workload Identity Pool ID; null derives `{prefix}-ci-pool` | `string` | no | `null` |
| provider_id | Workload Identity Provider ID; null derives `{prefix}-ci-oidc` | `string` | no | `null` |
| attribute_mapping | Google-attribute to assertion mapping; must include `google.subject` | `map(string)` | no | `{ "google.subject" = "assertion.sub" }` |

## Outputs

| Name | Description |
|---|---|
| workload_identity_pool_name | Fully qualified pool name |
| workload_identity_provider_name | Fully qualified provider name — the value a CI platform uses for federation |
| service_account_email | Email of the federated CI service account |
| service_account_id | ID of the federated CI service account |
| issuer_host | Normalized issuer host the trust conditions are keyed on |

## Usage

```hcl
module "infrastructure_deploy" {
  source = "./modules/gcp-ci-oidc-role"

  project_id          = "my-project-production"
  project_name_prefix = "my-project-production"
  role_name_suffix    = "infrastructure-deploy"

  issuer_url = "https://gitlab.com"
  audiences  = ["https://gitlab.com"]

  conditions = [
    { claim = "aud", match = "exact", values = ["https://gitlab.com"] },
    # Tag pipelines of one project only — protected-ref trust for
    # environments that deploy exclusively from tags:
    { claim = "sub", match = "wildcard", values = ["project_path:my-group/my-infra:ref_type:tag:ref:*"] },
    { claim = "ref_protected", match = "exact", values = ["true"] },
  ]

  project_roles = [
    "roles/editor",
  ]
}
```

The permissions the service account carries come only from
`project_roles` — trust restricts who can impersonate it, never what it
can do. Scope the granted roles to the services the pipeline manages
rather than an administrative wildcard.
