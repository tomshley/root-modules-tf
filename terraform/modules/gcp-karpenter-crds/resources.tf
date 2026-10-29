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

locals {
  # Moves with gcp-karpenter-controller-release's chart version; the two
  # charts are released together and a controller expects its own CRDs.
  chart_version = "0.6.0"
}

# The karpenter-crd chart ships its CRDs as templates, so this release owns
# them: uninstalling it deletes every NodePool, NodeClaim, and GCENodeClass in
# the cluster. Keep it installed for as long as any of those should survive,
# including while the controller release is absent.
resource "helm_release" "crds" {
  name             = "karpenter-crd"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter-crd"
  version          = local.chart_version
  wait             = true
  timeout          = var.helm_timeout_seconds
}
