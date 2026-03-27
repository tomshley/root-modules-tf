# Confluent Streaming Workload Access

Provisions governed Confluent Cloud streaming workload access — service account, API keys, Kafka ACLs, and optional Schema Registry credentials + RBAC.

## When to use this module

Use this module when infra-managed Kafka ACLs are worth making Terraform/OpenTofu state a secret-bearing system — i.e., when you have an encrypted remote state backend with access controls, and centralized ACL provisioning is preferable to manual or out-of-band ACL management.

## When NOT to use this module

Do not use this module if your security posture prohibits storing Kafka admin credentials in Terraform state, or if your environment requires that ACL management happen outside of Terraform (e.g., via Confluent CLI, CI-driven scripts, or a dedicated secrets manager). In those cases, provision service accounts and API keys through other means and manage ACLs separately.

## Secret Handling

**This module makes Terraform/OpenTofu state a secret-bearing system.** The following secrets are stored in state:

- Workload Kafka API secret (`confluent_api_key.kafka.secret`)
- Workload Schema Registry API secret (when SR enabled)
- Admin Kafka API key/secret in ACL resource state (inherent to provider Option 1)

**Requirements**:
- Remote encrypted state backend is **required**
- State access controls must treat state as a credential store

## Inputs

| Name | Description | Type | Required | Default |
|---|---|---|---|---|
| name | Workload name, used in resource naming | `string` | yes | — |
| environment_id | Confluent Cloud environment ID (e.g. `env-abc123`) | `string` | yes | — |
| environment_name | Logical name (e.g. staging) for display names | `string` | yes | — |
| kafka_cluster_id | Kafka cluster ID (e.g. `lkc-abc123`) | `string` | yes | — |
| kafka_rest_endpoint | Kafka REST endpoint URL for ACL management | `string` | yes | — |
| kafka_admin_credentials | Admin Kafka API key with ACL management permission | `object({ api_key, api_secret })` | yes | — |
| service_account_display_name | Display name for the service account | `string` | yes | — |
| topic_permissions | Topic-level Kafka ACL permissions | `list(object)` | yes (can be `[]`) | `[]` |
| group_permissions | Consumer group-level Kafka ACL permissions | `list(object)` | no | `[]` |
| transactional_id_permissions | Transactional ID Kafka ACL permissions for transactional/exactly-once-style producers | `list(object)` | no | `[]` |
| cluster_permissions | Cluster-level Kafka ACL permissions (e.g., `IDEMPOTENT_WRITE`) | `object({ operations = set(string) })` | no | `{ operations = [] }` |
| schema_registry | Schema Registry cluster configuration | `object({ cluster_id, resource_name })` | no | `null` |
| schema_subject_permissions | Schema Registry subject-level RBAC permissions | `list(object)` | no | `[]` |

### Permission Models

**Topic permissions**:
```hcl
topic_permissions = [
  {
    topic        = string      # topic name or prefix
    pattern_type = string      # "LITERAL" or "PREFIXED"
    operations   = set(string) # READ, WRITE, CREATE, DELETE, ALTER, DESCRIBE, DESCRIBE_CONFIGS, ALTER_CONFIGS
  }
]
```

**Group permissions**:
```hcl
group_permissions = [
  {
    group        = string
    pattern_type = string      # "LITERAL" or "PREFIXED"
    operations   = set(string) # READ, DESCRIBE, DELETE
  }
]
```

**Transactional ID permissions**:
```hcl
transactional_id_permissions = [
  {
    transactional_id = string
    pattern_type     = string      # "LITERAL" or "PREFIXED"
    operations       = set(string) # DESCRIBE, WRITE
  }
]
```

**Cluster permissions**:
```hcl
cluster_permissions = {
  operations = set(string) # IDEMPOTENT_WRITE, DESCRIBE, ALTER, ALTER_CONFIGS, DESCRIBE_CONFIGS, CLUSTER_ACTION, CREATE
}
```

Transactional ID ACLs are necessary for transactional or exactly-once-style producers that use Kafka `transactional.id` values. They do **not** by themselves provide full exactly-once semantics. Cluster-scoped `IDEMPOTENT_WRITE` remains separate and belongs in `cluster_permissions`.

**Schema subject permissions** (requires `schema_registry`):
```hcl
schema_subject_permissions = [
  {
    subject = string  # "*", "topic-value", "prefix*"
    role    = string  # "DeveloperRead", "DeveloperWrite", "ResourceOwner"
  }
]
```

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| service_account_id | Service account ID (e.g. `sa-abc123`) | no |
| kafka_api_key_id | Kafka API key ID | no |
| kafka_api_secret | Kafka API key secret | **yes** |
| schema_registry_api_key_id | Schema Registry API key ID (null when SR disabled) | no |
| schema_registry_api_secret | Schema Registry API key secret (null when SR disabled) | **yes** |

**Note**: Schema Registry outputs are `null` when `schema_registry = null`. Downstream consumers must treat these as nullable values.

## Usage

```hcl
module "example_workload" {
  source = "./modules/confluent-streaming-workload-access"

  name                        = "example-ingest-service"
  environment_id             = "env-abc123"
  environment_name           = "staging"
  kafka_cluster_id           = "lkc-abc123"
  kafka_rest_endpoint        = "https://pkc-abc123.us-east-1.aws.confluent.cloud"
  kafka_admin_credentials    = {
    api_key    = var.admin_kafka_api_key
    api_secret = var.admin_kafka_api_secret
  }
  service_account_display_name = "Example Ingest Service"

  topic_permissions = [
    {
      topic        = "example-events"
      pattern_type = "LITERAL"
      operations   = ["READ", "WRITE"]
    }
  ]

  group_permissions = [
    {
      group        = "example-consumer-group"
      pattern_type = "LITERAL"
      operations   = ["READ"]
    }
  ]

  transactional_id_permissions = [
    {
      transactional_id = "example-ingest-"
      pattern_type     = "PREFIXED"
      operations       = ["DESCRIBE", "WRITE"]
    }
  ]

  cluster_permissions = {
    operations = ["IDEMPOTENT_WRITE"]
  }

  schema_registry = {
    cluster_id    = "lsrc-abc123"
    resource_name = "crn://confluent.cloud/organization=abc123/environment=env-abc123/schema-registry=lsrc-abc123"
  }

  schema_subject_permissions = [
    {
      subject = "example-events-value"
      role    = "DeveloperWrite"
    }
  ]
}
```

## Known Limitations

1. **Hardcoded API metadata**: `cmk/v2`, `srcm/v2`, `Cluster` are hardcoded in locals. If Confluent changes API versioning, these must be updated.
2. **Admin credentials in state**: Inherent to provider Option 1. This is documented in the "When NOT to use" section above.
3. **SR role binding propagation delay**: Confluent docs warn that role bindings may take time to propagate. The module does not add `time_sleep` resources — caller handles timing if needed.
4. **No `prevent_destroy` lifecycle**: The module does not add lifecycle rules on API keys. Caller can wrap with lifecycle rules in their root module if needed.
5. **Transactional ID ACLs**: The module supports Transactional ID ACLs, but note that Confluent's Exactly-Once Semantics (EOS) requires additional configuration and setup outside of this module.
