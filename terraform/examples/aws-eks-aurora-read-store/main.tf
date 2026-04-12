###############################################################################
# AWS EKS Aurora — Read Store Example
#
# Read-optimized Aurora PostgreSQL cluster using the read-store preset.
# Includes one reader instance for read scaling.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "read_store" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "readmodel"
  workload_preset            = "read-store"
  database_name              = "readmodel"
  reader_instance_count      = 1
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]
}

output "cluster_endpoint" {
  value = module.read_store.cluster_endpoint
}

output "reader_endpoint" {
  value = module.read_store.reader_endpoint
}

output "master_secret_arn" {
  value = module.read_store.master_secret_arn
}
