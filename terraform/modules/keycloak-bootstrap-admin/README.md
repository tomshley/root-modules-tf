# keycloak-bootstrap-admin

A cloud-agnostic Terraform module that solves the **Keycloak Day-0 admin
provisioning** problem: how do you create the first realm-admin user in a
fresh Keycloak deployment without using the master-realm admin for routine
operations?

## Problem

Keycloak ships with a single super-user in the `master` realm. For
SOC2/HIPAA/FedRAMP-aligned deployments, that account should not be used for
day-to-day user provisioning. Operators need:

- A least-privilege client that holds two granular realm-management roles in one specific realm: `manage-users` (user CRUD, role-mappings, attribute writes) and `manage-realm` (partialImport — the only id-preserving user-create endpoint on existing realms; KC#12454). No cross-realm access, no master-realm access, no impersonation.
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
  - The service-account user entry that assigns two granular
    realm-management roles to the auto-created service-account user:
    `realm-management.manage-users` (user CRUD / role-mappings /
    attribute writes) and `realm-management.manage-realm`
    (`partialImport` — the only Admin REST endpoint that preserves
    client-supplied user `id`s on existing realms; see
    [keycloak/keycloak#12454](https://github.com/keycloak/keycloak/issues/12454)).
    **This is the load-bearing role grant** — without it the JWT
    issued via `client_credentials` carries no roles and Admin API
    calls return 403. `manage-users` and `manage-realm` are sibling
    granular roles inside the `realm-management` client; neither is
    a parent of the other. The `realm-admin` composite would grant
    both AND impersonation, manage-events, manage-clients,
    manage-identity-providers, manage-authorization — over-scoped
    for an automated bootstrap client and inappropriate for
    HIPAA/SOC2/FedRAMP-aligned deployments where service-account
    impersonation is a red flag.
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
calls the Keycloak Admin API to materialise the user with `id =
admin_user_id`, `requiredActions = admin_user_required_actions`, and
the assigned role. **Use `POST /admin/realms/{realm}/partialImport`**
(not `POST /users`) for the create call. partialImport is the only
Admin REST endpoint that preserves the client-supplied `id` field on
existing realms; `POST /users` silently auto-generates ids regardless
of what the request body specifies
([keycloak/keycloak#12454](https://github.com/keycloak/keycloak/issues/12454)),
which breaks the deterministic-`sub` contract this module's
`admin_user_id` output establishes. Idempotent payload: set
`ifResourceExists: "SKIP"` on the partialImport call so re-runs return
`results=[].action=SKIPPED` instead of failing on the existing user.
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

## Audit posture

Designed for SOC2 / HIPAA / FedRAMP-aligned deployments where
master-realm-admin use is restricted. Cloud-agnostic by construction —
the module emits Terraform-managed identifiers, secret material, and
realm-JSON snippets, but does not constrain where the consumer stores
secrets, how the bootstrap mechanism is invoked, or what platform the
Kubernetes substrate runs on (Rancher / Linode / EKS / GKE / AKS /
on-prem are all in scope).

### Why this design is auditable

The structural choices below are what make the privilege boundary in
the next section enforceable, rather than just policy on paper:

- **Cloud-agnostic by construction.** Pure Terraform locals plus
  `random_uuid` and `random_password`. No cloud-provider resources, no
  Kubernetes resources, no `provider-keycloak` admin calls. The same
  module instance produces the same outputs on Rancher, Linode, EKS,
  GKE, AKS, or on-prem — the only thing that varies is where the
  consumer stores the secret and which mechanism invokes the
  bootstrap.
- **Right separation of concerns.** Realm-import (Terraform-managed,
  atomic with realm creation) owns the bootstrap-client, the
  service-account user, and the administrative-role definition —
  these are chicken-and-egg with respect to the bootstrap client and
  must be expressible declaratively at realm-create time. The
  bootstrap mechanism (imperative, idempotent) owns the administrative
  user record itself — this requires the only Admin REST endpoint
  that preserves client-supplied user identifiers
  (`POST /admin/realms/{realm}/partialImport`;
  [keycloak/keycloak#12454](https://github.com/keycloak/keycloak/issues/12454)).
  Each piece lives where it can correctly be expressed; neither tries
  to do the other's job.
- **Minimum-necessary privilege.** The two granular roles
  (`manage-users` + `manage-realm`) are verifiable as the smallest set
  the documented operations require. Substituting either with a
  narrower role (`view-users`, etc.) breaks at least one operation;
  expanding to the `realm-admin` composite would grant impersonation
  and is rejected on audit-attribution grounds (next section).
- **Tamper evidence is structural, not policy.** The deterministic
  UUID emitted by `admin_user_id` cryptographically ties the JWT `sub`
  claim to the consuming application's user record. An attacker who
  substitutes a different administrative user record out-of-band
  breaks the bridge instantly and visibly — every existing JWT fails
  to resolve. This is math, not procedure.
- **No impersonation path.** The `realm-admin` composite role is
  deliberately not granted because it includes impersonation, which
  would create a PHI access path that bypasses audit attribution
  (impersonator acts as the impersonated user, with the latter's
  identity in the audit log). For HIPAA-aligned deployments, this is
  not acceptable for an automated service account.
- **Defense in depth.** The bootstrap client is configured with
  `fullScopeAllowed=false`, so even if the service-account user is
  granted additional roles out-of-band, the JWT can only carry the
  two scope-mapped roles. The scope mapping is independent of the
  user's role grants; both must be widened to widen the JWT.
- **Idempotent end-to-end.** Both fresh-boot and existing-user paths
  converge to the same exit-zero state on re-run. The bootstrap
  mechanism's contract is "make Keycloak match the declared identity
  tuple, exit zero whether or not changes were needed."
- **Audit attribution end-to-end.** Every administrative action
  (token grant, user create, role assignment, attribute write) is
  attributable to one named service-account principal in Keycloak's
  admin event log.
- **Sanctioned API surface.** `partialImport` is upstream Keycloak's
  documented mechanism for id-preserving user creation. Not a
  workaround for a bug; the Keycloak team has stated `POST /users`
  intentionally auto-generates ids. Stable contract, no migration risk.

### Privilege boundary

*HIPAA §164.308(a)(4) (information access management); §164.312(a)(1)
(access control — least privilege).*

| Aspect | Bound |
| --- | --- |
| **Subject** | Automated bootstrap mechanism (service account; no interactive use; no human credential). |
| **Object** | Exactly one realm — the realm this module is instantiated against. |
| **Operations** | Create / update one administrative user record; assign one realm role to that user. |
| **Out of scope** | No cross-realm access; no master-realm access; no user impersonation; no read/write of audit events; no client management; no identity-provider management; no authorization-service management; no PHI access path. |

### Granted roles — minimum-necessary set

Two granular sibling roles inside one realm's `realm-management` client:

- **`manage-users`**: needed to create/update the administrative user record and assign its realm role.
- **`manage-realm`**: needed to materialise the user with the deterministic identifier issued by this module (`admin_user_id`). Without it the identifier is silently auto-generated by Keycloak and the user's `sub` claim drifts across deploys, breaking the downstream application's user-record bridge.

Neither role implies the other; both must be granted explicitly.

### Deliberately not granted

- **`realm-admin` (composite)**: would also grant impersonation, `manage-events`, `manage-clients`, `manage-identity-providers`, and `manage-authorization`. None are required by the documented operations above; impersonation in particular is rejected on audit-attribution grounds (see "Why this design is auditable" above).
- **`master-realm-admin`**: not granted; the bootstrap client cannot reach the master realm.

### Consumer-side compensating controls (platform-specific)

The module CANNOT solve these; they depend on the consumer's deploy
substrate. The consumer is responsible for documenting how each is
satisfied in their environment.

#### CC-1 — Encryption at rest of the realm-JSON ConfigMap

*HIPAA §164.312(a)(2)(iv) (encryption decision).*

The `realm_client_json` output embeds `bootstrap_client_secret` inline
(this is how Keycloak's realm-import format encodes client secrets).
When the consumer splices this into a realm JSON and renders it as a
Kubernetes ConfigMap (the typical `keycloakConfigCli.existingConfigmap`
pattern), the secret material lives in plaintext in ConfigMap data.

Kubernetes ConfigMaps are not envelope-encrypted at rest by default.
The consumer's platform must provide an at-rest encryption mechanism
that covers ConfigMap resources, OR the consumer must accept the
residual and document compensating RBAC restrictions:

| Platform | Mechanism | Coverage |
| --- | --- | --- |
| Rancher (RKE2/k3s) | RKE2 `secrets-encryption` / k3s `--secrets-encryption` with `EncryptionConfiguration` listing `configmaps` in `resources` | Covers ConfigMaps when explicitly listed |
| On-prem K8s / GKE / AKS | KMS provider plugin to `kube-apiserver` per upstream Kubernetes docs (`EncryptionConfiguration` with `configmaps` listed) | Same — must list `configmaps`, not just `secrets` |
| Linode LKE | LKE does not currently expose customer-managed encryption-at-rest; falls back to platform disk-level encryption only | Document residual; revisit when LKE-Enterprise tier exposes the option |
| AWS EKS | EKS's KMS encryption provider covers K8s **Secrets only**, NOT ConfigMaps. Falls back to AWS-managed etcd-volume disk-level encryption + namespace RBAC | Document residual; stronger option = pre-process realm JSON outside cluster, mount via Secret (requires forking chart's `keycloakConfigCli` helper — see LT-1) |

#### CC-2 — Audit log capture

*HIPAA §164.312(b) (audit controls).*

Keycloak admin events covering every action the bootstrap mechanism
takes (token grant, `partialImport` / user create, role assignment,
attribute write) must be captured to the consumer's audit log
retention store. The module does not configure this; the consumer's
Keycloak deployment + their log-shipping pipeline does.

#### CC-3 — Bootstrap-client secret rotation cadence

*HIPAA §164.308(a)(5)(ii)(D) (credential management, applied to
non-human credentials).*

The module provides the rotation primitive (`tofu taint
module.<name>.random_password.bootstrap_client_secret` — see Strategy A
above) but does not enforce a cadence. The consumer is responsible
for documenting rotation cadence, procedure, and the propagation
path through their secret-distribution mechanism (ESO / Vault Agent /
sealed-secrets / etc.) in their operations runbook.

#### CC-4 — IaC vs. runtime drift reconciliation

*HIPAA §164.312(b) (audit controls — periodic review of access).*

Between Terraform applies, a Keycloak admin could widen the
bootstrap-client scope or assign additional roles via the Admin UI.
The typical compensating control is `keycloakConfigCli`'s realm
re-import on every Helm upgrade, which reverts manual changes — but
this only fires on chart upgrades, not on a continuous schedule. The
consumer is responsible for scheduling a reconciliation cadence
appropriate to their drift tolerance (e.g., nightly
`keycloakConfigCli` Job, external Keycloak-config-as-code reconciler).

### Module-level guarantees

The auditor can rely on these without reviewing the consumer's deploy
substrate:

- The privilege boundary above is encoded structurally in the
  module's outputs; widening it requires changing the module source,
  not consumer configuration.
- The deterministic UUID is generated once and stable across applies;
  rotating it is an explicit destructive action (`tofu taint` on
  `random_uuid.admin_user_id`).
- The bootstrap client is configured with `client_credentials` grant
  only — no browser flow, no password grant, no implicit flow, no
  refresh tokens. Locks the credential to programmatic, audited use.
- `fullScopeAllowed=false` on the client is defense-in-depth: even
  if the service-account user were granted additional roles
  out-of-band (CC-4 drift window), the JWT can only carry the two
  scope-mapped roles.

### Long-term improvements (tracked, not blockers)

Honest acknowledgement of architectural smells inherited from
upstream choices, with upgrade paths the consumer can pursue when
priorities allow:

#### LT-1 — Eliminate CC-1 by mounting realm JSON from a Secret

The `bootstrap_client_secret`-in-ConfigMap residual is inherited from
the upstream chart's `keycloakConfigCli.existingConfigmap` pattern.
A chart fork that mounts the realm JSON from a Secret instead would
eliminate CC-1 entirely — no platform-specific compensating control
needed. Substantial work (chart fork, ongoing maintenance), and
non-urgent because per-platform compensating controls under CC-1 are
HIPAA-acceptable.

#### LT-2 — "Rename administrative user" runbook entry

If an operator changes `admin_user_email` in tfvars after the
bootstrap has run, the next bootstrap-mechanism execution will see
`partialImport` match by the *new* username, fail to find the
existing user, and try to ADD a new one — which may collide on the
underlying email or create a duplicate depending on
`realm.duplicateEmailsAllowed`. The script does not have a "rename"
path. The consumer should document a manual-update procedure for
this case in their operations runbook.

#### LT-3 — Close the rotation propagation window

`tofu taint random_password.bootstrap_client_secret` updates the
Terraform-managed paths (secret backend + realm JSON ConfigMap)
atomically, but the K8s Secret consumed by the bootstrap mechanism
is synced by the consumer's secret-distribution operator (ESO /
Vault Agent / sealed-secrets / etc.) on its own cadence. Between
rotation and next sync, the bootstrap mechanism will 401 against
Keycloak. The consumer's rotation procedure should explicitly
trigger a sync and verify Secret refresh before re-running the
mechanism.

## License

Apache 2.0 — see the repository LICENSE file.
