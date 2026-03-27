# AWS EKS CI OIDC Access

Provisions the full CI → AWS → EKS deploy path: creates an AWS OIDC identity provider for a CI platform, a federated IAM role with configurable trust conditions, attaches deploy policies, and registers an EKS access entry for Kubernetes API access.

CI provider differences (GitHub Actions, GitLab CI, Bitbucket Pipelines) are expressed through the generic `oidc_issuer_url`, `trust_conditions`, and `oidc_audiences` inputs — not through module branching. See examples for provider-specific configurations.

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| project_name_prefix | Project name prefix for resource naming | `string` | yes | — |
| role_name_suffix | Suffix for the IAM role name | `string` | yes | — |
| oidc_provider_arn | Existing OIDC provider ARN. When null, creates a new provider | `string` | no | `null` |
| oidc_issuer_url | OIDC issuer URL of the CI platform. Required when creating a new provider | `string` | no | — |
| oidc_audiences | Allowed audiences for the OIDC provider | `list(string)` | no | `["sts.amazonaws.com"]` |
| oidc_thumbprints | TLS certificate thumbprints | `list(string)` | no | `[]` |
| trust_conditions | IAM trust policy conditions (test/claim/values) | `list(object)` | yes | — |
| policy_arns | IAM policy ARNs to attach | `list(string)` | no | `[]` |
| eks_cluster_name | Target EKS cluster name | `string` | yes | — |
| eks_access_policy_arn | EKS access policy ARN | `string` | no | `AmazonEKSClusterAdminPolicy` |
| eks_access_scope_type | Access scope: `cluster` or `namespace` | `string` | no | `cluster` |
| eks_access_scope_namespaces | Namespaces for namespace-scoped access | `list(string)` | no | `[]` |
| tags | Additional tags | `map(string)` | no | `{}` |

## Outputs

| Name | Description |
|---|---|
| oidc_provider_arn | ARN of the OIDC identity provider (existing or created) |
| oidc_provider_created | Boolean indicating if a new provider was created |
| role_arn | ARN of the federated IAM role |
| role_name | Name of the federated IAM role |

## Usage

```hcl
module "ci_deploy" {
  source = "./modules/aws-eks-ci-oidc-access"

  project_name_prefix = "my-project"
  role_name_suffix    = "github-deploy"
  oidc_issuer_url     = "https://token.actions.githubusercontent.com"
  eks_cluster_name    = "my-eks-cluster"

  trust_conditions = [
    { test = "StringEquals", claim = "aud", values = ["sts.amazonaws.com"] },
    { test = "StringLike",   claim = "sub", values = ["repo:my-org/my-repo:*"] }
  ]
}
```

## Notes

- Only one OIDC provider per issuer URL per AWS account. If the provider already exists, pass its ARN via `oidc_provider_arn`.
- The trust policy is constructed from `trust_conditions` — each condition's `claim` is automatically prefixed with the OIDC issuer host.
- `oidc_thumbprints` can be left empty for providers using a trusted CA (GitHub, GitLab.com).
- EKS access entries require EKS v1.23+ with the API authentication mode enabled.
- When using an existing provider, `oidc_issuer_url` is not required. The issuer host is extracted from the provider ARN.
