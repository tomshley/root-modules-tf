###############################################################################
# AWS EKS Aurora — Event Store Example
#
# Write-optimized Aurora PostgreSQL cluster using the event-store preset.
# Matches the original aws-eks-event-journal-db tuning profile.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "event_store" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "event-journal"
  workload_preset            = "event-store"
  database_name              = "event_journal"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]
}

output "cluster_endpoint" {
  value = module.event_store.cluster_endpoint
}

output "master_secret_arn" {
  value = module.event_store.master_secret_arn
}
