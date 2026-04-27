# confluent-streaming-topics

Overlay-driven Kafka topic provisioning for Confluent Cloud. Receives pre-parsed catalog entries and deployment overlays, filters topics by service/role inclusion and exclusion rules, and creates `confluent_kafka_topic` resources for the active set.

---

## When to Use

Use this module when you manage Kafka topics declaratively via YAML service catalogs and deployment overlays. The consumer is responsible for file discovery, YAML parsing, and overlay loading — this module receives the pre-parsed data and handles filtering plus resource creation.

**Do not use this module** if you manage topics imperatively or outside of the overlay model.

---

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `catalog_entries` | `list(object)` | yes | — | Pre-parsed topic entries. Each entry: `name`, `partitions`, `retention_ms`, `cleanup_policy`, `service`, `role`; optional `delete_retention_ms`, `min_compaction_lag_ms`. |
| `base_overlay` | `object` | yes | — | Deployment overlay with `include` (list of `{service, roles}`) and `exclude_topics` (list of topic names). |
| `region_exclusions` | `object` | no | `{ exclude_topics = [] }` | Optional region-specific topic exclusions. |
| `kafka_cluster_id` | `string` | yes | — | Confluent Kafka cluster ID. Must start with `lkc-`. |
| `kafka_rest_endpoint` | `string` | yes | — | Confluent Kafka REST endpoint. Must start with `https://`. |
| `kafka_admin_credentials` | `object` | yes | — | `{ api_key, api_secret }` for Kafka admin operations. **Sensitive.** |

### `catalog_entries` shape

```hcl
list(object({
  name                  = string
  partitions            = number
  retention_ms          = number
  cleanup_policy        = string
  service               = string
  role                  = string
  delete_retention_ms   = optional(number)
  min_compaction_lag_ms = optional(number)
}))
```

Additional fields (`owner`, `notes`) may be present in the consumer's YAML but are not used by this module.

#### Optional compaction-tuning fields

`delete_retention_ms` and `min_compaction_lag_ms` are optional knobs only meaningful on topics whose `cleanup_policy` includes `"compact"` (i.e. `"compact"` or `"compact,delete"`). When non-null they emit Kafka's `delete.retention.ms` and `min.compaction.lag.ms` config keys; when null they are omitted and Kafka's defaults apply (24h tombstone retention, 0ms minimum compaction lag).

A common combination is `cleanup_policy = "compact,delete"` + `delete_retention_ms = 604800000` (7 days), which keeps tombstones long enough that change-log readers / CDC sinks can pause for up to a week without missing delete markers — Kafka's 24h default is often too short for those workloads. Plan-time validation rejects either field on a pure `cleanup_policy = "delete"` topic, since the broker silently ignores both there.

### `base_overlay` shape

```hcl
object({
  include = list(object({
    service = string
    roles   = list(string)
  }))
  exclude_topics = list(string)
})
```

### Filtering pipeline

1. **Include** — build `"service:role"` keys from `base_overlay.include`; keep only catalog entries that match
2. **Exclude** — merge `base_overlay.exclude_topics` + `region_exclusions.exclude_topics`; remove matched topic names
3. **Result** — `active_topics` map used as `for_each` for `confluent_kafka_topic.managed`

---

## Outputs

| Name | Description |
|------|-------------|
| `active_topics` | Map of active topic name → attributes after overlay filtering. |
| `active_topic_summary` | Summary object: `by_role`, `by_service`, `total`, `names`. |
| `catalog_summary` | Summary of all input catalog entries (before filtering): `by_role`, `by_service`, `total`, `names`. |

---

## Usage

```hcl
module "streaming_topics" {
  # DEV: local source — swap to git ref for release
  # Release: git::https://github.com/tomshley/root-modules-tf.git//terraform/modules/confluent-streaming-topics?ref=v1.3.0
  source   = "../../../../tomshley-oss-dependencies/root-modules-tf/terraform/modules/confluent-streaming-topics"
  for_each = local.confluent_configured ? { default = true } : {}

  catalog_entries         = local.catalog_entries
  base_overlay            = local.base_overlay
  region_exclusions       = local.region_exclusions
  kafka_cluster_id        = var.confluent.kafka_cluster_id
  kafka_rest_endpoint     = var.confluent.kafka_rest_endpoint
  kafka_admin_credentials = var.confluent.kafka_admin_credentials
}
```

Wire outputs with `try()` for the conditional case:

```hcl
output "active_topic_summary" {
  value = try(module.streaming_topics["default"].active_topic_summary, {
    total = 0, names = [], by_role = {}, by_service = {}
  })
}
```

---

## Topic Lifecycle: `prevent_destroy = true`

This module sets `lifecycle { prevent_destroy = true }` on all managed topics. This is **intentional policy**, not just a safety toggle.

- **Overlays control creation** — adding a service/role to a base overlay creates topics on the next apply.
- **Topic removal requires explicit operator action** — removing a service/role from an overlay will plan a destroy, but `prevent_destroy` blocks the apply. The operator must:
  1. Temporarily remove `prevent_destroy` from the module source
  2. Apply the destroy
  3. Restore `prevent_destroy`
- This is the correct safety posture for HIPAA/production Kafka topics where accidental deletion could cause data loss.

---

## Known Limitations

- **File I/O stays in the consumer** — Terraform `fileset()` and `file()` resolve relative to `path.module`. This module cannot read YAML files from the consumer's directory tree. The consumer must parse catalogs and overlays before passing them in.
- **`prevent_destroy` cannot be toggled via variable** — Terraform requires `prevent_destroy` to be a literal boolean. There is no way to make it conditional per-environment without forking the module.
- **Topic names must be unique across services** — the `active_topics` map is keyed by topic name. Duplicate names across different services will collide.
- **Region exclusions are additive only** — they can exclude topics but cannot add topics beyond what `base_overlay.include` selects.
