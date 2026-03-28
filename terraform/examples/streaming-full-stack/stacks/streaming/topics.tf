locals {
  # Discover all catalog files: catalogs/streaming/services/<service>/<role>.yaml
  catalog_files = fileset("${path.module}/../../catalogs/streaming/services", "*/*.yaml")

  # Parse each file, annotate every topic with service and role from the path.
  catalog_entries = flatten([
    for f in local.catalog_files : [
      for t in try(yamldecode(file("${path.module}/../../catalogs/streaming/services/${f}")).topics, []) : merge(t, {
        service = dirname(f)
        role    = trimsuffix(basename(f), ".yaml")
      })
    ]
  ])

  # Load base overlay: deployments/<environment>/<profile>/base.yaml
  base_overlay_path = "${path.module}/../../catalogs/streaming/deployments/${var.environment}/${local.profile_short}/base.yaml"
  base_overlay      = yamldecode(file(local.base_overlay_path))

  # Load optional region exclusions: deployments/<environment>/<profile>/exclusions/<region>.yaml
  region_exclusions_path = "${path.module}/../../catalogs/streaming/deployments/${var.environment}/${local.profile_short}/exclusions/${var.aws_region}.yaml"
  region_exclusions      = fileexists(local.region_exclusions_path) ? yamldecode(file(local.region_exclusions_path)) : { exclude_topics = [] }

  # All topics as a flat list (for summaries/outputs).
  all_topics = local.catalog_entries
}

module "streaming_topics" {
  # DEV: local source — swap to git ref for release
  # Release: source = "github.com/tomshley/root-modules-tf//terraform/modules/confluent-streaming-topics?ref=v1.3.0"
  source   = "../../../../modules/confluent-streaming-topics"
  for_each = local.confluent_configured ? { default = true } : {}

  catalog_entries         = local.catalog_entries
  base_overlay            = local.base_overlay
  region_exclusions       = local.region_exclusions
  kafka_cluster_id        = var.confluent.kafka_cluster_id
  kafka_rest_endpoint     = var.confluent.kafka_rest_endpoint
  kafka_admin_credentials = var.confluent.kafka_admin_credentials
}
