# CI OIDC Trust (generic contract)

The platform-neutral core of CI OIDC federation. This module creates **no
resources**: it normalizes and validates a CI platform's federation trust —
issuer, audiences, and claim conditions — into one canonical trust object,
so per-platform implementation modules are thin adapters over a shared,
plan-time-enforced contract instead of each re-defining it.

```
ci-oidc-trust            (this module — the contract, owned once)
   ↓ trust object
aws-ci-oidc-role         (AWS implementation: OIDC provider + IAM role)
gcp-ci-oidc-role         (future: workload identity pool + service account)
azure-ci-oidc-role       (future: federated identity credential)
   ↓ composition
aws-eks-ci-oidc-access   (adds the Kubernetes binding on the AWS path)
```

The condition grammar is deliberately minimal — `exact` and `wildcard` —
because it must stay expressible on every platform. Combination semantics are
part of the contract: **all conditions must hold simultaneously (AND across
entries); the values within one condition are alternatives (OR)**.
Implementations translate the grammar into their native trust grammar
(equality/pattern operators in an IAM trust policy, attribute conditions
elsewhere) and must preserve those semantics. A platform that cannot express
a match kind MUST reject it at plan time rather than silently weaken it; the
`wildcard_conditions` output exists so that refusal is one precondition.

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| issuer_url | OIDC issuer URL of the CI platform (https, multi-segment paths preserved) | `string` | yes | — |
| audiences | Allowed token audiences; empty means the implementation applies its platform default | `list(string)` | no | `[]` |
| conditions | Trust conditions: `[{ claim, match = "exact"\|"wildcard", values }]` | `list(object)` | yes | — |

Validation enforced here (so no implementation re-implements it): https
issuer; at least one condition; no duplicate claim+match; non-empty, trimmed
claims and values; `exact` values may not contain `*`/`?` (a pattern is never
compared verbatim by accident); every `wildcard` condition contains at least
one actual pattern.

## Outputs

| Name | Description |
|---|---|
| issuer_url | Normalized issuer URL (no trailing slash) |
| issuer_host | Issuer without the scheme, path preserved — the claim-reference prefix on most platforms |
| audiences | Audiences as given |
| conditions | Normalized conditions |
| exact_conditions | Subset with `match = "exact"` |
| wildcard_conditions | Subset with `match = "wildcard"` |
| trust | The complete normalized trust object — the single input an implementation consumes |

## Usage

```hcl
module "trust" {
  source = "./modules/ci-oidc-trust"

  issuer_url = "https://gitlab.com"
  audiences  = ["https://gitlab.com"]

  conditions = [
    { claim = "aud", match = "exact",    values = ["https://gitlab.com"] },
    { claim = "sub", match = "wildcard", values = ["project_path:my-group/my-repo:ref_type:branch:ref:*"] },
  ]
}

# An implementation module consumes module.trust.trust — see aws-ci-oidc-role.
```
