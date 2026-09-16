# GCP Karpenter Prerequisites

This pre-1.0 module creates the least-privilege custom role reviewed against signed `cloudpilot-ai/karpenter-provider-gcp` `v0.3.0` source and grants it through `gcp-gke-workload-identity`. The shared identity module is the only resource that creates the controller Google service account or principal grants. Apply this module before `gcp-karpenter-controller`.
