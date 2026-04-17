project           = "myproject"
environment       = "staging"
aws_region        = "us-east-1"
streaming_profile = "commercial_managed"

tags = {}

# ── Confluent Cloud configuration (non-sensitive) ─────────────────────
# Credentials are injected via TF_VAR_kafka_admin_api_key and
# TF_VAR_kafka_admin_api_secret from the .env secure file.
confluent_config = {
  environment_id          = "env-abc123"
  environment_name        = "staging"
  kafka_cluster_id        = "lkc-abc123"
  kafka_rest_endpoint     = "https://pkc-abc123.us-east-1.aws.confluent.cloud:443"
  kafka_bootstrap_servers = "pkc-abc123.us-east-1.aws.confluent.cloud:9092"
  schema_registry = {
    cluster_id    = "lsrc-abc123"
    resource_name = "crn://confluent.cloud/organization=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/environment=env-abc123/schema-registry=lsrc-abc123"
    url           = "https://psrc-abc123.us-east-1.aws.confluent.cloud"
  }
}

# ── Workload service accounts and permissions ─────────────────────────
workloads = {
  "service-a" = {
    service_account_display_name = "myproject-staging-service-a"
    topic_permissions = [
      {
        topic        = "events-a"
        pattern_type = "LITERAL"
        operations   = ["CREATE", "WRITE"]
      }
    ]
    group_permissions            = []
    transactional_id_permissions = []
    cluster_permissions          = { operations = [] }
    schema_subject_permissions = [
      {
        subject = "events-a-value"
        role    = "DeveloperWrite"
      }
    ]
  }
}
