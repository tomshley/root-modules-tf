# GCP GKE Karpenter Controller

This pre-1.0 module installs the `cloudpilot-ai/karpenter-provider-gcp` CRD and controller charts at the exact `0.3.0` release. It creates the controller Google service account through `gcp-gke-workload-identity`; the Helm chart creates the Kubernetes ServiceAccount and receives the shared module's annotation. The identity module is the sole owner of all principal grants.

The custom project role is limited to the calls reviewed in the signed `v0.3.0` source: Compute Engine instance, image, machine-type, zone, operation, and managed-instance-group reads plus instance create/delete/label writes; GKE cluster and node-pool reads/create; and `iam.serviceAccounts.actAs` for node identities. `container.clusters.get` is required by the v0.3.0 network discovery path.

`0.3.0` splits CRDs into `karpenter-crd`, so this module installs and waits for that chart before the controller release. The module pins the controller image tag to `v0.3.0`. The v0.3.0 chart exposes `controller.image.repository`, `controller.image.tag`, and `controller.image.pullPolicy`, but no image digest value; an image digest therefore cannot be pinned through supported chart values.

Karpenter v0.3.0 only applies the cluster-wide GKE node tag and `GCENodeClass.spec.networkTags`. Pass `node_network_tags` to this module and use `node_class_network_tags` verbatim in every NodeClass. The network-tag contract example verifies this wiring.
