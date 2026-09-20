# GCP Karpenter Controller

This pre-1.0 module installs the exact `cloudpilot-ai/karpenter-provider-gcp` `0.3.0` CRD and controller charts. Apply `gcp-karpenter-prereqs` first. That module creates the controller Google service account and delegates every Workload Identity and project IAM principal grant to `gcp-gke-workload-identity`; this module only annotates the Helm-managed Kubernetes ServiceAccount with its resulting Google service-account email.

The controller image tag is pinned to `v0.3.0`. The v0.3.0 chart exposes repository, tag, and pull-policy values but no image-digest value, so an image digest cannot be pinned through its supported chart interface.

Karpenter v0.3.0 uses only the cluster-wide GKE node tag and each `GCENodeClass.spec.networkTags`. Pass `node_network_tags` through to every NodeClass unchanged.

## Cluster location contract

The controller takes two location settings with different meanings. `cluster_location` feeds instance-type discovery and accepts a region or a zone — the controller derives the compute region from it. `node_location` is the exact location used to address the cluster in the provider's GKE node-pool API paths, for both the existence check and pool creation; when unset, the controller defaults it to `cluster_location`. The default is correct for a regional cluster (whose location is its region) and for a zonal cluster whose `cluster_location` is already its zone, so `node_location` should normally be omitted — set it only when `cluster_location` is a region but the cluster itself is zonal. A zone against a regional cluster makes every node-pool existence check and creation miss with 404 and the controller retries indefinitely while NodeClasses still admit cleanly.

The controller creates its own template node pools — `karpenter-default` and `karpenter-ubuntu` are required, `karpenter-cos-arm64` and `karpenter-ubuntu-arm64` are best-effort — using the node service account passed as `node_service_account_email`. No Terraform-managed template node pool is needed.
