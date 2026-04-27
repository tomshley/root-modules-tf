locals {
  resolved_sg_description = var.security_group_description != null ? var.security_group_description : "Redis access for ${var.workload_name} workloads"
  resolved_pg_description = var.parameter_group_description != null ? var.parameter_group_description : "Redis parameter group for ${var.workload_name}"
  resolved_rg_description = var.replication_group_description != null ? var.replication_group_description : "Redis cluster for ${var.workload_name}"

  # num_cache_clusters >= 2 is both necessary and sufficient for Multi-AZ +
  # automatic failover on a cluster-mode-disabled replication group.
  # Deriving these flags removes an entire class of
  # "multi_az_enabled = true but num_cache_clusters = 1" misconfigurations
  # that would otherwise fail at apply with a cryptic AWS error.
  ha_enabled = var.num_cache_clusters >= 2
}
