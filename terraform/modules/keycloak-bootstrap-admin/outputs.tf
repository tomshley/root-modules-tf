###############################################################################
# keycloak-bootstrap-admin — Outputs
#
# All outputs are designed to be consumed in two places:
#   1. The consumer's secret backend wiring (Secrets Manager / Vault / etc.)
#   2. The consumer's realm-import templating (jsondecode + merge into realm)
#
# Sensitive values (bootstrap_client_secret) are flagged so they don't leak
# into plan output or Terraform state-output dumps.
###############################################################################

# --- Bootstrap client identity ---

output "bootstrap_client_id" {
  description = "Keycloak clientId for the bootstrap service-account client (the value of var.bootstrap_client_id, surfaced as an output for downstream wiring)."
  value       = var.bootstrap_client_id
}

output "bootstrap_client_secret" {
  description = "Generated client_secret for the bootstrap service-account client. Store this in your secret backend; the bootstrap mechanism reads it to obtain a JWT via client_credentials grant. Stable across Terraform applies; rotate by tainting random_password.bootstrap_client_secret."
  value       = random_password.bootstrap_client_secret.result
  sensitive   = true
}

# --- Admin user identity tuple ---
#
# These six outputs (id, email, firstname, lastname, role, required_actions)
# together describe the deterministic admin user the bootstrap mechanism
# creates in Keycloak. They MUST be stored together in the consumer's secret
# backend so the bootstrap mechanism can read them as one tuple — splitting
# them across stores risks drift between the realm role grant and the user
# record itself.

output "admin_user_id" {
  description = "Deterministic UUID for the admin user. This becomes the Keycloak user 'id' field at creation time, which means it is also the value of the 'sub' claim in every JWT the user receives. Surfaced so downstream applications can pre-seed a User record with the same UUID, ensuring the JWT-to-application-user bridge is stable from day zero."
  value       = random_uuid.admin_user_id.result
}

output "admin_user_email" {
  description = "Admin user email address (same as var.admin_user_email)."
  value       = var.admin_user_email
}

output "admin_user_firstname" {
  description = "Admin user first name (same as var.admin_user_firstname)."
  value       = var.admin_user_firstname
}

output "admin_user_lastname" {
  description = "Admin user last name (same as var.admin_user_lastname)."
  value       = var.admin_user_lastname
}

output "admin_user_role" {
  description = "Realm role assigned to the admin user (same as var.admin_user_role)."
  value       = var.admin_user_role
}

output "admin_user_required_actions" {
  description = "Required actions assigned to the admin user at creation time. The bootstrap mechanism should pass these through to the Keycloak Admin API user-create payload AND to the executeActionsEmail call so the user receives a single onboarding email covering all actions."
  value       = var.admin_user_required_actions
}

# --- Realm JSON snippets ---
#
# All three outputs are JSON STRINGS so consumers using either Terraform's
# templatefile() or jsondecode() patterns can compose them into their realm
# JSON without coupling to Terraform's HCL representation.

output "realm_client_json" {
  description = "JSON-encoded client object ready to splice into the 'clients' array of a Keycloak realm JSON. The object encodes the bootstrap service-account client with client_credentials grant only — no browser flow, no password grant, no refresh tokens, fullScopeAllowed=false. Splice via jsondecode() in your realm-import templating."
  value       = jsonencode(local.realm_client)
  sensitive   = true # contains the client secret
}

output "realm_role_mapping_json" {
  description = "JSON-encoded clientScopeMappings entry ready to merge into a Keycloak realm JSON. Declares that JWTs issued for the bootstrap client may carry the 'realm-management.manage-users' role IF the underlying user holds it; this is a scope setting, not a role assignment. Load-bearing because the bootstrap client is configured with fullScopeAllowed=false — without this entry the JWT would carry no roles even after realm_service_account_user_json grants the role to the user. Splice via jsondecode() + merge() into 'clientScopeMappings' in your realm-import templating."
  value       = jsonencode(local.realm_role_mapping)
}

output "realm_service_account_user_json" {
  description = "JSON-encoded user entry ready to splice into the 'users' array of a Keycloak realm JSON. THIS is the load-bearing role grant for the bootstrap mechanism: it assigns 'realm-management.manage-users' to the auto-created service-account user 'service-account-$${bootstrap_client_id}'. Without this entry the JWT obtained via client_credentials grant carries no roles and Admin API calls return 403. Splice via jsondecode() in your realm-import templating."
  value       = jsonencode(local.realm_service_account_user)
}

# --- Discovery output ---
#
# Useful for caller-side validation that the module was instantiated with the
# expected realm/role combination, especially when multiple instances of this
# module exist in the same root module (e.g. one per realm).

output "summary" {
  description = "Non-sensitive summary of the bootstrap configuration. Useful in 'terraform output' for human verification: which realm, which role, which client, which user."
  value = {
    realm               = var.realm_name
    bootstrap_client_id = var.bootstrap_client_id
    admin_user_id       = random_uuid.admin_user_id.result
    admin_user_email    = var.admin_user_email
    admin_user_role     = var.admin_user_role
    required_actions    = var.admin_user_required_actions
    secret_length       = var.bootstrap_client_secret_length
  }
}
