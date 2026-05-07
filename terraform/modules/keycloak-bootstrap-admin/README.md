# keycloak-bootstrap-admin

A cloud-agnostic Terraform module that solves the **Keycloak Day-0 admin
provisioning** problem: how do you create the first realm-admin user in a
fresh Keycloak deployment without using the master-realm admin for routine
operations?

## Problem

Keycloak ships with a single super-user in the `master` realm. For
SOC2/HIPAA/FedRAMP-aligned deployments, that account should not be used for
day-to-day user provisioning. Operators need:

- A least-privilege client that can only `manage-users` in one specific realm
- A deterministic identity (UUID, email, name) for the bootstrap admin so
  downstream applications can pre-seed user records against a stable `sub`
- A repeatable, idempotent way to create that user from CI/CD on every fresh
  cluster (and verify it exists on rerun)

This module produces all three. The values flow into your secret backend of
choice; the bootstrap mechanism (a Kubernetes Job, a `null_resource +
local-exec`, the `terraform-provider-keycloak`, etc.) is your choice.

## What this module does

- Generates a stable random `client_secret` for a bootstrap service-account
  client.
- Generates a stable random UUID for the admin user identity.
- Surfaces both as Terraform outputs (one sensitive).
- Outputs three ready-to-merge JSON snippets for your realm import:
  - The bootstrap client object (with `client_credentials` grant only,
    `fullScopeAllowed=false`).
  - The service-account user entry that assigns
    `realm-management.manage-users` to the auto-created service-account
    user. **This is the load-bearing role grant** — without it the JWT
    issued via `client_credentials` carries no roles and Admin API calls
    return 403.
  - The client scope mapping that authorises the role to appear in tokens
    issued for the bootstrap client (required because the client is
    configured with `fullScopeAllowed=false`).

## What this module does NOT do

- Does not store secrets in any backend. You wire the outputs.
- Does not call the Keycloak Admin API. You choose the bootstrap mechanism.
- Does not depend on any cloud provider, Kubernetes, or Helm. Pure
  `random` provider.
- Does not impose a realm role hierarchy. You supply `admin_user_role`.
- Does not generate the realm JSON for you. You compose snippets into your
  existing realm JSON via `jsondecode` + `merge`.

## Usage

```hcl
module "platform_admin_bootstrap" {
  # Pin to a release tag in production; replace <TAG> with the tag that
  # ships this module (this README is published alongside the module so
  # the next release tag of root-modules-tf will be the first that
  # contains it).
  source = "github.com/tomshley/root-modules-tf//terraform/modules/keycloak-bootstrap-admin?ref=<TAG>"

  realm_name           = "platform"
  bootstrap_client_id  = "platform-bootstrap"
  admin_user_email     = "ops@example.com"
  admin_user_firstname = "Platform"
  admin_user_lastname  = "Admin"
  admin_user_role      = "platform-admin"
}

# Wire the outputs into your secret backend (example: AWS Secrets Manager):

resource "aws_secretsmanager_secret" "bootstrap_client" {
  name = "${local.prefix}-bootstrap-client-secret"
}

resource "aws_secretsmanager_secret_version" "bootstrap_client" {
  secret_id = aws_secretsmanager_secret.bootstrap_client.id
  secret_string = jsonencode({
    client_id     = module.platform_admin_bootstrap.bootstrap_client_id
    client_secret = module.platform_admin_bootstrap.bootstrap_client_secret
  })
  # No ignore_changes: keeps Terraform-driven rotation (taint the
  # random_password resource) coherent with the secret backend. If you
  # rotate out-of-band instead (ESO, AWS native rotation), add
  # `lifecycle { ignore_changes = [secret_string] }` here AND update the
  # Rotation section below — the two patterns are mutually exclusive.
}

resource "aws_secretsmanager_secret" "admin_user" {
  name = "${local.prefix}-admin-user-bootstrap"
}

resource "aws_secretsmanager_secret_version" "admin_user" {
  secret_id = aws_secretsmanager_secret.admin_user.id
  secret_string = jsonencode({
    user_id          = module.platform_admin_bootstrap.admin_user_id
    email            = module.platform_admin_bootstrap.admin_user_email
    firstname        = module.platform_admin_bootstrap.admin_user_firstname
    lastname         = module.platform_admin_bootstrap.admin_user_lastname
    role             = module.platform_admin_bootstrap.admin_user_role
    required_actions = module.platform_admin_bootstrap.admin_user_required_actions
  })
  # See note on the bootstrap_client secret_version above re: rotation.
}

# Splice the snippets into your realm JSON before importing it:

locals {
  base_realm = jsondecode(file("${path.module}/realm/platform.json"))

  enriched_realm = merge(local.base_realm, {
    clients = concat(
      lookup(local.base_realm, "clients", []),
      [jsondecode(module.platform_admin_bootstrap.realm_client_json)],
    )
    users = concat(
      lookup(local.base_realm, "users", []),
      [jsondecode(module.platform_admin_bootstrap.realm_service_account_user_json)],
    )
    clientScopeMappings = merge(
      lookup(local.base_realm, "clientScopeMappings", {}),
      jsondecode(module.platform_admin_bootstrap.realm_role_mapping_json),
    )
  })
}

resource "local_file" "realm_enriched" {
  content  = jsonencode(local.enriched_realm)
  filename = "${path.module}/.terraform/realm/platform-enriched.json"
}
```

Then point your existing Keycloak realm-import (e.g. via the
`aws-eks-keycloak` module's `realm_json_path`) at `local_file.realm_enriched.filename`.

## Bootstrap mechanisms

This module is mechanism-agnostic. Reference patterns:

### Pattern A — Kubernetes Job (recommended for K8s deployments)

A short Python or shell script in a Job pod that uses the
`bootstrap_client_secret` to obtain a JWT via `client_credentials`, then
calls the Keycloak Admin API to create the user with `id =
admin_user_id`, `requiredActions = admin_user_required_actions`, and
the assigned role. Idempotent: GET the user first; exit 0 if it exists.
After creation, call `executeActionsEmail` (passing the same
`requiredActions` list) so the user receives a one-time onboarding email
covering every action in a single message. The Job's logs flow through
the cluster's existing log pipeline.

### Pattern B — `null_resource` + `local-exec`

A bash + `curl` script that runs on the operator's host during `tofu
apply`. Simpler but requires network access from the operator's host to
Keycloak (typically requires kubectl port-forward), and logs only land on
the operator's terminal — weaker audit trail.

### Pattern C — `terraform-provider-keycloak`

The Terraform provider can create users directly. Caveat: requires admin
credentials in Terraform state (a regression on the goal of avoiding
master-admin use), and the `executeActionsEmail` action is not exposed by
the provider as of this writing.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `realm_name` | Keycloak realm the client and user are scoped to. | `string` | n/a | yes |
| `bootstrap_client_id` | clientId for the bootstrap client. Lowercase DNS-label, max 64 chars. | `string` | `platform-bootstrap` | no |
| `bootstrap_client_name` | UI-friendly client name. | `string` | (descriptive default) | no |
| `admin_user_email` | Admin user email. Real, monitored mailbox in production. | `string` | n/a | yes |
| `admin_user_firstname` | Admin user first name. No newlines, `=`, or quotes. | `string` | n/a | yes |
| `admin_user_lastname` | Admin user last name. No newlines, `=`, or quotes. | `string` | n/a | yes |
| `admin_user_role` | Realm role to assign. Must already exist in the realm. | `string` | n/a | yes |
| `bootstrap_client_secret_length` | Generated secret length in chars. 32–128. | `number` | `48` | no |
| `admin_user_required_actions` | Initial requiredActions on the user. Each entry must match `^[A-Z][A-Z0-9_]*$`. | `list(string)` | `["UPDATE_PASSWORD","VERIFY_EMAIL"]` | no |

## Outputs

| Name | Description | Sensitive |
|------|-------------|:---------:|
| `bootstrap_client_id` | Client ID. | no |
| `bootstrap_client_secret` | Client secret. | yes |
| `admin_user_id` | Deterministic UUID for the admin user. | no |
| `admin_user_email` | Admin user email. | no |
| `admin_user_firstname` | Admin user first name. | no |
| `admin_user_lastname` | Admin user last name. | no |
| `admin_user_role` | Assigned realm role. | no |
| `admin_user_required_actions` | Required actions for the bootstrap mechanism to apply. | no |
| `realm_client_json` | JSON-encoded client object for `clients[]` splicing. | yes (contains secret) |
| `realm_service_account_user_json` | JSON-encoded user entry for `users[]` splicing. The actual role grant for the bootstrap service account. | no |
| `realm_role_mapping_json` | JSON-encoded scope mapping for `clientScopeMappings` splicing. Authorises the role to appear in JWTs issued for the bootstrap client (paired with `fullScopeAllowed=false`). | no |
| `summary` | Non-sensitive summary object. | no |

## Compatibility

- Tested against Keycloak 24.x, 25.x, and 26.x via the Bitnami chart.
- The realm JSON shape produced is compatible with both
  `keycloakConfigCli` (managed-mode and import-mode) and Keycloak's native
  realm import (via the `--import-realm` boot flag).
- Provider requirements: `random ~> 3.0`, Terraform/OpenTofu `>= 1.9`. No cloud-provider dependencies.

## Rotation

Two rotation strategies are supported. They are mutually exclusive at the
secret-version layer; pick one per consumer.

### Strategy A — Terraform-driven (recommended for most consumers)

The example wiring above (without `ignore_changes`) supports rotating the
bootstrap client secret via:

```bash
tofu taint module.platform_admin_bootstrap.random_password.bootstrap_client_secret
tofu apply
```

The new secret value flows through the module outputs and into both the
realm JSON (so Keycloak's database is updated on the next realm-import
reconcile) and the secret backend (so consumers reading from it get the
new value). Coordinate with any consumers holding the old secret.

### Strategy B — Out-of-band rotation (ESO, AWS Secrets Manager native rotation, etc.)

If rotation is owned by separate tooling, add
`lifecycle { ignore_changes = [secret_string] }` to the secret_version
resources in the example. That preserves the OOB-rotated value across
`tofu apply`. Strategy A's `tofu taint` flow then no longer rotates the
secret backend — do not mix the two.

## Compliance

Suitable for SOC2 / HIPAA / FedRAMP-aligned deployments where
master-realm-admin use is restricted. Auditable properties:

- Bootstrap client cannot escalate beyond `manage-users` in one realm.
- Admin user identity is deterministic — no UUID drift across redeploys.
- The mechanism the consumer chooses (Job, null_resource, etc.) governs
  the audit log stream — this module does not constrain it.

## License

Apache 2.0 — see the repository LICENSE file.
