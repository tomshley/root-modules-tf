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

variable "contract" {
  type = object({
    replicas                 = number
    keep_off_karpenter_nodes = bool
    preference_policy        = string
    priority_class_name      = string
  })
  nullable    = false
  description = "Provider-independent Karpenter controller placement and scheduling intent. Every field is required; a null field leaves the chart's own setting in place."

  validation {
    condition     = var.contract.replicas == null || try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)
    error_message = "replicas must be null or a whole number of controller replicas, 1 or more."
  }

  validation {
    condition     = var.contract.preference_policy == null ? true : contains(["Respect", "Ignore"], var.contract.preference_policy)
    error_message = "preference_policy must be null, \"Respect\", or \"Ignore\"."
  }

  validation {
    condition     = var.contract.priority_class_name == null || try(length(var.contract.priority_class_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.contract.priority_class_name)), false)
    error_message = "priority_class_name must be null or a PriorityClass name: at most 253 characters of dot-separated labels, each of lowercase letters, digits, and '-', starting and ending with a letter or digit."
  }
}
