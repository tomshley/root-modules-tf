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
  #     'realm-management.manage-users' even if the service-account user
  #     is later granted additional roles out-of-band.
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

  # Client scope mapping snippet. Declares that tokens issued for the
  # bootstrap client may carry the 'realm-management.manage-users' role.
  # This is a SCOPE setting — it controls whether the role can appear in
  # the JWT, not whether the user actually holds the role. Load-bearing
  # because the client above is configured with fullScopeAllowed=false:
  # without this entry, the JWT would carry no roles even though the
  # service-account user holds 'manage-users'. Pair with
  # realm_service_account_user (below) which assigns the role to the
  # user; this snippet authorises the role to appear in the token.
  realm_role_mapping = {
    "realm-management" = [
      {
        client = var.bootstrap_client_id
        roles  = ["manage-users"]
      }
    ]
  }

  # Service-account user entry. THIS is what actually grants the bootstrap
  # client's auto-created service-account user the 'manage-users' client
  # role on the built-in 'realm-management' client. Without this entry,
  # the JWT obtained via client_credentials carries no roles regardless
  # of clientScopeMappings, and Admin API calls return 403.
  #
  # Username convention is fixed by Keycloak: 'service-account-${clientId}'.
  # The 'serviceAccountClientId' field links this user record to the
  # auto-created service-account user during realm import so Keycloak
  # does not create a second, role-less user with the same username.
  #
  # Least-privilege guarantee: only 'realm-management.manage-users' is
  # mapped. The bootstrap client cannot manage realm settings, identity
  # providers, or other clients; cannot touch the master realm (different
  # realm); cannot escalate via 'manage-realm' or 'manage-clients'.
  realm_service_account_user = {
    username               = "service-account-${var.bootstrap_client_id}"
    enabled                = true
    serviceAccountClientId = var.bootstrap_client_id
    clientRoles = {
      "realm-management" = ["manage-users"]
    }
  }
}
