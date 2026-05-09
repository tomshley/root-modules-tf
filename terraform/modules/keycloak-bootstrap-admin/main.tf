###############################################################################
# keycloak-bootstrap-admin — Resources and locals
#
# Pure resource set: a deterministic UUID for the admin user identity, and a
# random secret for the bootstrap service-account client. No cloud-provider
# resources, no Kubernetes resources, no provider-keycloak admin calls.
#
# Consumer is responsible for:
#   - Storing bootstrap_client_secret in their secret backend
#   - Storing admin_user_id + email + firstname + lastname + role +
#     required_actions in their secret backend (the deterministic identity
#     tuple consumed by the bootstrap mechanism)
#   - Splicing realm_client_json into 'clients[]', realm_service_account_user_json
#     into 'users[]', and (optionally) realm_role_mapping_json into
#     'clientScopeMappings' of their realm JSON before importing it (typically
#     via keycloakConfigCli)
#   - Invoking a one-shot bootstrap mechanism that consumes those values to
#     create the admin user via the Keycloak Admin API. Reference patterns:
#     a) A K8s Job using a published image + this module's outputs as env
#     b) A null_resource + local-exec calling curl from the operator's host
#     c) terraform-provider-keycloak (caveat: requires admin creds in state)
#
# This module deliberately does not pick the mechanism — the right choice
# depends on the consumer's tooling, audit requirements, and tolerance for
# adding providers or images to their stack.
###############################################################################

# Deterministic UUID for the admin user identity. Stored in Terraform state
# and stable across applies so the user's `sub` claim in Keycloak matches the
# downstream application's user record forever (no UUID drift after the user
# table is seeded).
resource "random_uuid" "admin_user_id" {}

# Bootstrap client secret. Generated once, stable across applies.
# special=false so the value is URL-safe and works in client_credentials
# token requests without escaping (Keycloak Admin API).
resource "random_password" "bootstrap_client_secret" {
  length  = var.bootstrap_client_secret_length
  special = false
}

locals {
  # JSON snippet for the bootstrap client entry. The consumer splices this
  # into the "clients" array of their realm JSON before importing.
  #
  # Notable choices:
  #   publicClient=false + serviceAccountsEnabled=true → client_credentials
  #     grant ONLY. No browser flow, no password grant, no implicit flow —
  #     locks the client to programmatic, audited use.
  #   refresh tokens disabled → service-account JWTs are short-lived and
  #     non-refreshable. Forces re-auth via client_credentials each call,
  #     simplifying the bootstrap script's idempotent rerun model.
  #   fullScopeAllowed=false → JWTs only carry roles that are explicitly
  #     scope-mapped to this client. Combined with realm_role_mapping
  #     (clientScopeMappings entry below) this restricts the JWT to
  #     'realm-management.manage-users' + 'realm-management.manage-realm'
  #     (the two granular roles required for the documented bootstrap
  #     operations) even if the service-account user is later granted
  #     additional roles out-of-band.
  realm_client = {
    clientId                  = var.bootstrap_client_id
    name                      = var.bootstrap_client_name
    publicClient              = false
    serviceAccountsEnabled    = true
    standardFlowEnabled       = false
    directAccessGrantsEnabled = false
    implicitFlowEnabled       = false
    fullScopeAllowed          = false
    secret                    = random_password.bootstrap_client_secret.result
    attributes = {
      "use.refresh.tokens"                   = "false"
      "client_credentials.use_refresh_token" = "false"
    }
  }

  # CLIENT SCOPE MAPPING — authorises the realm-management roles below
  # to appear in JWTs minted for this client. Required because the client
  # is configured with fullScopeAllowed=false (above): without this entry
  # the token carries no roles even after realm_service_account_user
  # (below) assigns them to the user. Both pieces are needed; one
  # authorises the role to appear in the token, the other actually grants
  # the role to the user.
  #
  # PRIVILEGE BOUNDARY (HIPAA §164.308(a)(4) information access management;
  # §164.312(a)(1) access control — least privilege):
  #   Subject:      automated bootstrap K8s Job (service account; no
  #                 interactive use; no human credential).
  #   Object:       exactly one realm — the realm this module is
  #                 instantiated against.
  #   Operations:   create/update one administrative user record;
  #                 assign one realm role to that user.
  #   Out of scope: no cross-realm access; no master-realm access;
  #                 no user impersonation; no read/write of audit
  #                 events; no client management; no identity-provider
  #                 management; no authorization-service management;
  #                 no PHI access path.
  #
  # GRANTED — minimum-necessary set, two granular roles inside one
  # realm's realm-management client:
  #   manage-users:  needed to create/update the administrative user
  #                  record and assign its realm role.
  #   manage-realm:  needed to materialise the user with the
  #                  deterministic identifier issued by this module
  #                  (admin_user_id). Without it the identifier is
  #                  silently auto-generated by Keycloak and the
  #                  user's `sub` claim drifts across deploys, breaking
  #                  the downstream application's user-record bridge.
  # These two roles are siblings inside the realm-management client;
  # neither implies the other, so both must be granted explicitly.
  #
  # NOT GRANTED — deliberate exclusions, with the audit rationale:
  #   realm-admin (composite): would also grant impersonation,
  #     manage-events, manage-clients, manage-identity-providers, and
  #     manage-authorization. None are required by the documented
  #     operations above; impersonation in particular would create a
  #     PHI access path that bypasses audit attribution (the
  #     impersonator acts as the impersonated user, with the latter's
  #     identity in the audit log) and is incompatible with an
  #     automated service account.
  #   master-realm-admin: not granted; the bootstrap client cannot
  #     reach the master realm.
  #
  # Implementation reference: the manage-realm requirement is upstream
  # Keycloak's authorization for the partialImport endpoint, which is
  # the only Admin REST endpoint that preserves client-supplied user
  # identifiers on an existing realm (keycloak/keycloak#12454).
  realm_role_mapping = {
    "realm-management" = [
      {
        client = var.bootstrap_client_id
        roles  = ["manage-users", "manage-realm"]
      }
    ]
  }

  # SERVICE-ACCOUNT USER ENTRY — actually grants the two realm-management
  # roles to the service-account user that Keycloak auto-creates for the
  # bootstrap client. Pairs with realm_role_mapping (above): without this
  # entry the user holds no roles regardless of scope mapping, and every
  # Admin API call returns 403.
  #
  # Username convention is fixed by Keycloak: 'service-account-${clientId}'.
  # The 'serviceAccountClientId' field links this user record to the
  # auto-created service-account user during realm import so Keycloak
  # does not create a second, role-less user with the same username.
  #
  # See realm_role_mapping (above) for the privilege boundary, the
  # HIPAA-aligned rationale for the two-role minimum-necessary set, and
  # the explicit list of what is NOT granted (realm-admin composite,
  # impersonation, master-realm access, etc.).
  realm_service_account_user = {
    username               = "service-account-${var.bootstrap_client_id}"
    enabled                = true
    serviceAccountClientId = var.bootstrap_client_id
    clientRoles = {
      "realm-management" = ["manage-users", "manage-realm"]
    }
  }
}
