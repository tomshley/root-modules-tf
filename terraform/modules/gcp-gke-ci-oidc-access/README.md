# GCP GKE CI OIDC Access

Provisions the full CI → GCP → GKE deploy path: creates a Workload Identity Pool and Provider for a CI platform, a GCP service account with federated access, and grants project-level roles for GKE deployment.

CI provider differences (GitHub Actions, GitLab CI, Bitbucket Pipelines) are expressed through the generic `oidc_issuer_url`, `attribute_mapping`, and `attribute_condition` inputs — not through module branching. See examples for provider-specific configurations.

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| project_id | GCP project ID | `string` | yes | — |
| pool_id | Workload Identity Pool ID | `string` | yes | — |
| pool_display_name | Display name for the pool | `string` | no | pool_id |
| provider_id | Workload Identity Provider ID | `string` | yes | — |
| provider_display_name | Display name for the provider | `string` | no | provider_id |
| oidc_issuer_url | OIDC issuer URL of the CI platform | `string` | yes | — |
| oidc_allowed_audiences | Allowed audiences | `list(string)` | no | `[]` (pool default) |
| attribute_mapping | Google attribute → OIDC assertion mapping | `map(string)` | yes | — |
| attribute_condition | CEL expression to restrict accepted tokens | `string` | yes | — |
| service_account_id | Service account ID to create | `string` | yes | — |
| service_account_display_name | Display name for the SA | `string` | no | service_account_id |
| project_roles | GCP roles to grant to the SA | `list(string)` | yes | — |

## Outputs

| Name | Description |
|---|---|
| workload_identity_pool_name | Full resource name of the pool (includes project number) |
| workload_identity_provider_name | Full resource name of the provider |
| service_account_email | Email of the created service account |
| service_account_id | Account ID of the created service account |

## Usage

```hcl
module "ci_deploy" {
  source = "./modules/gcp-gke-ci-oidc-access"

  project_id          = "my-gcp-project"
  pool_id             = "github-ci-pool"
  provider_id         = "github-oidc"
  oidc_issuer_url     = "https://token.actions.githubusercontent.com"
  service_account_id  = "github-ci-deploy"
  project_roles       = ["roles/container.developer"]

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == 'my-org/my-repo'"
}
```

## Notes

- The `attribute_condition` is a required CEL expression evaluated against OIDC token assertions. It is the primary scoping mechanism — the SA IAM binding grants `roles/iam.workloadIdentityUser` to all identities in the Workload Identity Pool, so the condition on the provider is what restricts access.
- `project_roles` should include at minimum `roles/container.developer` for GKE deploy access.
- Workload Identity pools and providers are global resources within a project.
