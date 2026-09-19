# GCP GKE Karpenter Controller

This pre-1.0 module installs the `cloudpilot-ai/karpenter-provider-gcp` CRD and controller charts at the exact `0.3.0` release. It creates the controller Google service account through `gcp-gke-workload-identity`; the Helm chart creates the Kubernetes ServiceAccount and receives the shared module's annotation. The identity module is the sole owner of all principal grants.

The custom project role lives in `gcp-karpenter-prereqs` and follows the provider's canonical controller role definition; see that module's README for the permission rationale. Node pool operations are covered by `container.clusters.get`/`update` because GCP maps them onto cluster permissions, and `iam.serviceAccounts.actAs` is bound on the node service account alone rather than project-wide.

`0.3.0` splits CRDs into `karpenter-crd`, so this module installs and waits for that chart before the controller release. The module pins the controller image tag to `v0.3.0`. The v0.3.0 chart exposes `controller.image.repository`, `controller.image.tag`, and `controller.image.pullPolicy`, but no image digest value; an image digest therefore cannot be pinned through supported chart values.

Karpenter v0.3.0 only applies the cluster-wide GKE node tag and `GCENodeClass.spec.networkTags`. Pass `node_network_tags` to this module and use `node_class_network_tags` verbatim in every NodeClass. The network-tag contract example verifies this wiring.
