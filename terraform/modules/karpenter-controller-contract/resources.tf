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
  normalized = {
    replicas                 = var.contract.replicas
    keep_off_karpenter_nodes = var.contract.keep_off_karpenter_nodes
    preference_policy        = var.contract.preference_policy
    priority_class_name      = var.contract.priority_class_name
  }

  # Each adapter renders this verbatim, so keeping the controller off
  # Karpenter's nodes means the same thing on every cloud.
  node_affinity_off_karpenter_nodes = {
    requiredDuringSchedulingIgnoredDuringExecution = {
      nodeSelectorTerms = [{
        matchExpressions = [{ key = "karpenter.sh/nodepool", operator = "DoesNotExist" }]
      }]
    }
  }
}
