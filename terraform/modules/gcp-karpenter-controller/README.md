# GCP Karpenter Controller

This pre-1.0 module installs the exact `cloudpilot-ai/karpenter-provider-gcp` `0.3.0` CRD and controller charts. Apply `gcp-karpenter-prereqs` first. That module creates the controller Google service account and delegates every Workload Identity and project IAM principal grant to `gcp-gke-workload-identity`; this module only annotates the Helm-managed Kubernetes ServiceAccount with its resulting Google service-account email.

The controller image tag is pinned to `v0.3.0`. The v0.3.0 chart exposes repository, tag, and pull-policy values but no image-digest value, so an image digest cannot be pinned through its supported chart interface.

Karpenter v0.3.0 uses only the cluster-wide GKE node tag and each `GCENodeClass.spec.networkTags`. Pass `node_network_tags` through to every NodeClass unchanged.
