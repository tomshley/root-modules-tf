# GCP GKE Karpenter Controller

This pre-1.0 module installs the `cloudpilot-ai/karpenter-provider-gcp` CRD and controller charts at the exact `0.6.0` release. It creates the controller Google service account through `gcp-gke-workload-identity`; the Helm chart creates the Kubernetes ServiceAccount and receives the shared module's annotation. The identity module is the sole owner of all principal grants.

The custom project role lives in `gcp-karpenter-prereqs` and follows the provider's canonical controller role definition; see that module's README for the permission rationale. Node pool operations are covered by `container.clusters.get`/`update` because GCP maps them onto cluster permissions, and `iam.serviceAccounts.actAs` is bound on the node service account alone rather than project-wide.

CRDs ship in a separate `karpenter-crd` chart, so this module installs and waits for that chart before the controller release. The module pins the controller image tag to `v0.6.0`. The v0.6.0 chart exposes `controller.image.repository`, `controller.image.tag`, and `controller.image.pullPolicy`, but no image digest value; an image digest therefore cannot be pinned through supported chart values.

Karpenter applies the generic `gke-<cluster>-node` tag and, since provider v0.4.0, the cluster-id-bearing `gke-<cluster>-<cluster-id[:8]>-node` tag that GKE's auto-created firewall rules target. `GCENodeClass.spec.networkTags` is appended after the derived tags, never replacing them. Pass `node_network_tags` to this module and use `node_class_network_tags` verbatim in every NodeClass. The network-tag contract example verifies this wiring.

## Cluster location contract

`cluster_location` feeds instance-type discovery and accepts a region or a zone. `node_location` is the exact location used to address the cluster in the provider's GKE node-pool API paths and should normally be omitted — the controller defaults it to `cluster_location`, which is correct for a regional cluster and for a zonal cluster whose `cluster_location` is already its zone. Set it only when `cluster_location` is a region but the cluster itself is zonal. A zone against a regional cluster makes every node-pool existence check and creation miss with 404 and the controller retries indefinitely while NodeClasses still admit cleanly. See the `gcp-karpenter-controller` README for the full contract.

An advisory `check` block reads the cluster at the effective node location and asserts `cluster_location` resolves to the same region the cluster lives in. The read itself surfaces a wrong node location at plan time; a principal lacking `container.clusters.get` gets a warning, never a broken plan.

From provider v0.4.0 the controller no longer creates its own template node pools; it bootstraps nodes from the instance template of an existing RUNNING pool. Discovery is `default-pool`, then the first RUNNING pool alphabetically, then a created `karpenter-fallback`. Alphabetical ordering is incidental, not a contract — pass `bootstrap_node_pool_name` to pin the source pool deterministically. Legacy `karpenter-*` pools left over from older provider versions are unused and can be deleted.
