resource "google_project_iam_custom_role" "karpenter" {
  project     = var.project_id
  role_id     = "karpenterController"
  title       = "Karpenter GKE Controller"
  description = "Permissions used by cloudpilot-ai/karpenter-provider-gcp v0.3.0."

  permissions = [
    "compute.disks.create",
    "compute.disks.delete",
    "compute.images.get",
    "compute.images.list",
    "compute.images.useReadOnly",
    "compute.instanceGroupManagers.get",
    "compute.instanceGroups.get",
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setLabels",
    "compute.machineTypes.get",
    "compute.machineTypes.list",
    "compute.networks.use",
    "compute.subnetworks.use",
    "compute.zoneOperations.get",
    "compute.zones.list",
    "container.clusters.get",
    "container.nodePools.create",
    "container.nodePools.get",
    "iam.serviceAccounts.actAs",
  ]
}

module "workload_identity" {
  source = "../gcp-gke-workload-identity"

  project_id                      = var.project_id
  service_account_id              = var.google_service_account_id
  namespace                       = var.namespace
  kubernetes_service_account_name = var.kubernetes_service_account_name
  project_roles                   = [google_project_iam_custom_role.karpenter.name]
}
