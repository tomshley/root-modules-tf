# GCP Karpenter Controller Release

This pre-1.0 module installs the exact `cloudpilot-ai/karpenter-provider-gcp` `0.6.0` `karpenter` controller chart without its CRDs. It takes the same inputs and gives the same outputs as `gcp-karpenter-controller`, which composes it with `gcp-karpenter-crds`; see that module's README for the identity, image, dual-stack, and cluster-location contracts.

Install `gcp-karpenter-crds` first and order this module after it (`depends_on`). The controller chart carries copies of the CRDs in its `crds/` directory; this release sets `skip_crds`, so Helm never installs them and the CRDs stay owned by the CRD release. Without `gcp-karpenter-crds`, the controller has no CRDs to act on.

Releases installed before `skip_crds` was set plan one in-place update for it, which changes nothing in the cluster: Helm only reads `crds/` on install.

A consumer that composes this module separately can leave it out while keeping the CRD release. Removing the release removes the controller, its RBAC, and its disruption budget; every `NodePool`, `NodeClaim`, and `GCENodeClass` stays, with no controller acting on them. Nodes the controller launched are not drained or deleted when it goes, so leave it out only when no `NodeClaim` exists.
