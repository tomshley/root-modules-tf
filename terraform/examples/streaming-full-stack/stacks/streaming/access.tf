module "workload_access" {
  # DEV: local source — swap to git ref for release
  # Release: source = "github.com/tomshley/root-modules-tf//terraform/modules/confluent-streaming-workload-access?ref=v1.3.0"
  source   = "../../../../modules/confluent-streaming-workload-access"
  for_each = local.active_workloads

  name                         = each.key
  environment_id               = var.confluent.environment_id
  environment_name             = var.confluent.environment_name
  kafka_cluster_id             = var.confluent.kafka_cluster_id
  kafka_rest_endpoint          = var.confluent.kafka_rest_endpoint
  kafka_admin_credentials      = var.confluent.kafka_admin_credentials
  service_account_display_name = each.value.service_account_display_name
  topic_permissions            = each.value.topic_permissions
  group_permissions            = each.value.group_permissions
  transactional_id_permissions = each.value.transactional_id_permissions
  cluster_permissions          = each.value.cluster_permissions
  schema_registry              = local.schema_registry_for_module
  schema_subject_permissions   = each.value.schema_subject_permissions
}
