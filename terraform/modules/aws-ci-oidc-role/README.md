# AWS CI OIDC Role

AWS implementation of the [ci-oidc-trust](../ci-oidc-trust/README.md)
contract: registers (or reuses) the IAM OIDC identity provider for a CI
platform and mints a federated IAM role from the normalized trust object —
`exact` conditions become `StringEquals`, `wildcard` conditions become
`StringLike`, keyed on `{issuer_host}:{claim}`. IAM's native combination
semantics match the contract's: all conditions must hold (AND), values within
a condition are alternatives (OR).

This module carries **no Kubernetes coupling**. It is the role for pipelines
that exist before, or independent of, any cluster — infrastructure
provisioning being the canonical case (the pipeline that *creates* the
cluster cannot depend on one). Where a pipeline also needs Kubernetes API
access, compose a cluster-binding module on top (on EKS:
[aws-eks-ci-oidc-access](../aws-eks-ci-oidc-access/README.md)).

AWS allows one OIDC provider per issuer URL per account: pass
`oidc_provider_arn` wherever a provider already exists (the issuer is then
derived from the ARN and `issuer_url` may stay null).

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| project_name_prefix | Project name prefix for resource naming | `string` | yes | — |
| role_name_suffix | Role name suffix; final name `{prefix}-ci-{suffix}` | `string` | yes | — |
| oidc_provider_arn | Existing provider ARN to reuse; null creates one | `string` | no | `null` |
| issuer_url | CI platform issuer URL; required when creating the provider | `string` | no | `null` |
| audiences | Allowed audiences for the provider | `list(string)` | no | `["sts.amazonaws.com"]` |
| thumbprints | Provider TLS thumbprints; empty is valid for trusted-CA issuers | `list(string)` | no | `[]` |
| conditions | Trust conditions in the ci-oidc-trust shape (`claim`, `match = "exact"\|"wildcard"`, `values`) | `list(object)` | yes | — |
| policy_arns | IAM policy ARNs attached to the role | `list(string)` | no | `[]` |
| max_session_duration | Role session ceiling in seconds (3600–43200) | `number` | no | `3600` |
| tags | Additional tags | `map(string)` | no | `{}` |

## Outputs

| Name | Description |
|---|---|
| oidc_provider_arn | ARN of the OIDC provider (existing or created) |
| oidc_provider_created | Whether this module created the provider |
| role_arn | ARN of the federated CI role |
| role_name | Name of the federated CI role |
| issuer_host | Normalized issuer host the trust conditions are keyed on |

## Usage

```hcl
module "infrastructure_deploy" {
  source = "./modules/aws-ci-oidc-role"

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

  policy_arns = [
    aws_iam_policy.infrastructure_deploy.arn,
  ]
}
```

The permissions the role carries come only from `policy_arns` — trust
restricts who can assume it, never what it can do. Scope the attached
policies to the services the pipeline manages rather than an administrative
wildcard.
