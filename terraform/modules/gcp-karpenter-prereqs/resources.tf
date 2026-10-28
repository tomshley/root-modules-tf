# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "google_project_iam_custom_role" "karpenter" {
  project     = var.project_id
  role_id     = "karpenterController"
  title       = "Karpenter GKE Controller"
  description = "Canonical controller permissions for cloudpilot-ai/karpenter-provider-gcp."

  # Canonical grant set from the provider's maintained
  # deploy/iam/karpenter-controller-role.yaml, which tracks the IAM roles the
  # controller's code paths actually exercise. Several operations the module
  # previously listed are not grantable in custom roles at all:
  #  - container.nodePools.* — GCP maps node pool operations onto cluster
  #    permissions: reads are covered by container.clusters.get and
  #    create/delete by container.clusters.update.
  #  - compute.regionInstanceTemplates.* — regional templates use the same
  #    compute.instanceTemplates.* namespace.
  #  - iam.serviceAccounts.actAs — deliberately not a project-level grant;
  #    it is bound on the node service account alone, below.
  # Notes on less-obvious entries:
  #  - compute.projects.get is called at startup to discover the Compute
  #    Engine default service account.
  #  - container.clusters.list backs release-channel image resolution.
  #  - compute.networks.get / compute.subnetworks.get are strictly needed
  #    for Shared VPC (controller in a service project, network in a host
  #    project) and are retained for that case.
  #  - setMetadata, setServiceAccount, setTags, and
  #    subnetworks.useExternalIp are confirmed-required by upstream
  #    end-to-end testing.
  permissions = [
    "compute.disks.create",
    "compute.images.get",
    "compute.images.list",
    "compute.instanceGroupManagers.get",
    "compute.instanceTemplates.get",
    "compute.instanceTemplates.list",
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.setTags",
    "compute.machineTypes.list",
    "compute.networks.get",
    "compute.projects.get",
    "compute.regions.get",
    "compute.subnetworks.get",
    "compute.subnetworks.use",
    "compute.subnetworks.useExternalIp",
    "compute.zoneOperations.get",
    "compute.zones.list",
    "container.clusters.get",
    "container.clusters.list",
    "container.clusters.update",
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

# The controller launches nodes that run as the cluster's node service
# account, so it needs iam.serviceAccounts.actAs on that account. Bind it on
# the service account itself rather than at project level: the controller can
# act as the node identity but gains no rights over any other service account
# in the project.
resource "google_service_account_iam_member" "node_service_account_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.node_service_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.workload_identity.google_service_account_email}"
}
