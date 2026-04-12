###############################################################################
# AWS EKS Aurora — Generic Example
#
# Aurora PostgreSQL cluster with no workload-specific tuning.
# Uses Aurora defaults for all parameters. Individual overrides shown.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "generic_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "appdata"
  workload_preset            = "generic"
  database_name              = "appdata"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]

  # Individual override example — set random_page_cost even though generic preset omits it
  random_page_cost = "1.1"
}

output "cluster_endpoint" {
  value = module.generic_db.cluster_endpoint
}

output "master_secret_arn" {
  value = module.generic_db.master_secret_arn
}
