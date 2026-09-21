# GCP Karpenter Prerequisites

This pre-1.0 module creates the least-privilege custom role for `cloudpilot-ai/karpenter-provider-gcp` and grants it through `gcp-gke-workload-identity`. The shared identity module is the only resource that creates the controller Google service account or project-level principal grants. Apply this module before `gcp-karpenter-controller`.

The custom role's permission set follows the provider's maintained canonical role definition (`deploy/iam/karpenter-controller-role.yaml`), which tracks what the controller's code paths actually call:

- GCP refuses several plausible permissions in custom roles. Node pool operations map onto cluster permissions (`container.nodePools.get` is covered by `container.clusters.get`; node pool create/delete map to `container.clusters.update`), and regional instance templates use the `compute.instanceTemplates.*` namespace, so `compute.regionInstanceTemplates.*` does not exist as a grantable permission.
- `compute.projects.get` is called at startup to discover the Compute Engine default service account, and `container.clusters.list` backs release-channel image resolution.
- `compute.networks.get` and `compute.subnetworks.get` are strictly needed only for Shared VPC, where the controller service account lives in a service project and the network lives in a host project; they are retained for that case.
- `compute.instances.setMetadata`, `compute.instances.setServiceAccount`, `compute.instances.setTags`, and `compute.subnetworks.useExternalIp` are confirmed-required by upstream end-to-end testing.

`iam.serviceAccounts.actAs` is deliberately absent from the project-level role. The controller needs it only to launch nodes that run as the cluster's node service account, so the module binds `roles/iam.serviceAccountUser` on that service account alone. A project-level `actAs` would let the controller impersonate every service account in the project.

The permission set is upstream's current canonical definition while the sibling `gcp-karpenter-controller` module pins chart `0.6.0`. A superset of what the pinned chart calls is safe; the chart pin is the value to revisit when tracking newer upstream releases, not this role.
