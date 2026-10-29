# GCP Karpenter CRDs

This pre-1.0 module installs the exact `cloudpilot-ai/karpenter-provider-gcp` `0.6.0` `karpenter-crd` chart: the `NodePool`, `NodeClaim`, `NodeOverlay`, and `GCENodeClass` CRDs. Compose it with `gcp-karpenter-controller-release`, or use `gcp-karpenter-controller`, which composes both.

The chart ships its CRDs as templates, so this release owns them. Uninstalling it deletes every custom resource of those kinds in the cluster, including NodePools and NodeClasses that workloads apply for themselves. Keep it installed for as long as any of them should survive.

The chart version moves with `gcp-karpenter-controller-release`; the two are always released at the same version.
