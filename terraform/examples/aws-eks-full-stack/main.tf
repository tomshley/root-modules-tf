###############################################################################
# AWS EKS Full Stack — Reference Composition
#
# Demonstrates output-only wiring between modules.
# Zero depends_on. Zero data source lookups for intra-module dependencies.
# Availability zones are explicit — no auto-detection.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

variable "cluster_name" {
  type    = string
  default = "example-eks-cluster"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["203.0.113.0/24"]
}

# --- VPC ---

module "vpc" {
  source = "../../modules/aws-eks-vpc"

  project_name_prefix  = var.project_name_prefix
  cluster_name         = var.cluster_name
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

# --- EKS Cluster ---

module "cluster" {
  source = "../../modules/aws-eks-cluster"

  project_name_prefix = var.project_name_prefix
  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids = concat(
    module.vpc.private_subnet_ids,
    module.vpc.public_subnet_ids
  )
  public_access_cidrs = var.public_access_cidrs
}

# --- System Node Group (ON_DEMAND) ---

module "system_nodes" {
  source = "../../modules/aws-eks-nodegroup"

  project_name_prefix = var.project_name_prefix
  cluster_name        = module.cluster.cluster_name
  subnet_ids          = module.vpc.private_subnet_ids
  node_group_name     = "system"

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  min_size       = 1
  max_size       = 3
  desired_size   = 1

  labels = {
    "role" = "system"
  }

  taints = [
    {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  ]
}

# --- Workload Node Group (SPOT) ---

module "workload_nodes" {
  source = "../../modules/aws-eks-nodegroup"

  project_name_prefix = var.project_name_prefix
  cluster_name        = module.cluster.cluster_name
  subnet_ids          = module.vpc.private_subnet_ids
  node_group_name     = "workload"

  instance_types = ["t3.medium", "t3a.medium", "t3.large"]
  capacity_type  = "SPOT"
  min_size       = 0
  max_size       = 10
  desired_size   = 2

  labels = {
    "role" = "workload"
  }
}

# --- Karpenter Prerequisites ---

module "karpenter_prereqs" {
  source = "../../modules/aws-eks-karpenter-prereqs"

  project_name_prefix = var.project_name_prefix
  cluster_name        = module.cluster.cluster_name
  oidc_provider_arn   = module.cluster.oidc_provider_arn
  oidc_provider_url   = module.cluster.oidc_provider_url
}

# --- Karpenter Controller (Helm) ---

module "karpenter_controller" {
  source = "../../modules/aws-eks-karpenter-controller"

  cluster_name                      = module.cluster.cluster_name
  cluster_endpoint                  = module.cluster.cluster_endpoint
  karpenter_controller_role_arn     = module.karpenter_prereqs.controller_role_arn
  karpenter_interruption_queue_name = module.karpenter_prereqs.sqs_queue_name
}

# --- Sample IRSA Role (e.g., for external-dns) ---

module "irsa_external_dns" {
  source = "../../modules/aws-eks-irsa"

  project_name_prefix  = var.project_name_prefix
  role_name_suffix     = "external-dns"
  oidc_provider_arn    = module.cluster.oidc_provider_arn
  oidc_provider_url    = module.cluster.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "external-dns"
  policy_arns          = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
}
