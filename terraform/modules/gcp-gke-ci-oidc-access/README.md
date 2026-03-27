# GCP GKE CI OIDC Access

Provisions the full CI → GCP → GKE deploy path: creates a Workload Identity Pool and Provider for a CI platform, a GCP service account with federated access, and grants project-level roles for GKE deployment.

CI provider differences (GitHub Actions, GitLab CI, Bitbucket Pipelines) are expressed through the generic `oidc_issuer_url`, `attribute_mapping`, `attribute_condition`, `repository_selector`, and `repository_attribute` inputs — not through module branching. See examples for provider-specific configurations.

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
| repository_selector | Repository or namespace selector for explicit IAM binding | `string` | yes | — |
| repository_attribute | Mapped attribute name for the IAM binding principal set | `string` | no | attribute.repository |
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
  repository_selector = "my-org/my-repo"
  repository_attribute = "attribute.repository"
  project_roles       = ["roles/container.developer"]

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == 'my-org/my-repo'"
}
```

## Notes

- The service account IAM binding is scoped explicitly to `repository_selector` using the configurable `repository_attribute` (e.g., `attribute.repository` for GitHub, `attribute.namespace_path` for GitLab), creating a narrow, visible security boundary. The `attribute_condition` on the provider provides defense-in-depth.
- `repository_selector` must match the value of the attribute mapped in `attribute_mapping` (e.g., repository name for GitHub, group name for GitLab, UUID for Bitbucket).
- `repository_attribute` must match the key in `attribute_mapping` exactly, including the `attribute.` prefix.
- `project_roles` should include at minimum `roles/container.developer` for GKE deploy access.
- Workload Identity pools and providers are global resources within a project.
