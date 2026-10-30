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

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  type        = string
}

variable "karpenter_controller_role_arn" {
  description = "IAM role ARN for the Karpenter controller (from aws-eks-karpenter-prereqs)"
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for spot interruption events (from aws-eks-karpenter-prereqs)"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.1.0"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace for Karpenter controller"
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account_name" {
  description = "Kubernetes service account name for Karpenter controller"
  type        = string
  default     = "karpenter"
}

variable "controller_replicas" {
  description = "Controller replica count. Null keeps the chart's two; the chart's disruption budget already allows one unavailable pod, so a single replica can still be drained. Validated by karpenter-controller-contract."
  type        = number
  default     = null
}

variable "keep_controller_off_karpenter_nodes" {
  description = "Null or true keeps the chart's placement, which already keeps the controller off nodes Karpenter launched (required node affinity on karpenter.sh/nodepool DoesNotExist); true also renders that affinity explicitly. False removes it, letting the controller run on Karpenter's nodes. The same input on gcp-karpenter-controller-release adds the affinity the GKE chart lacks."
  type        = bool
  default     = null
}

variable "preference_policy" {
  description = "The controller's PREFERENCE_POLICY, \"Respect\" or \"Ignore\", rendered as the chart's settings.preferencePolicy. Null keeps the chart's setting, Respect, which the chart renders from 1.4.0. Ignore applies to the whole controller: Karpenter also stops weighing workloads' preferred spreads and affinities when it launches nodes, though the default scheduler still honours them when it places pods. Karpenter reads it from chart 1.4.0; set with a karpenter_version whose major and minor numbers do not read as 1.4 or later, the plan is refused. Validated by karpenter-controller-contract."
  type        = string
  default     = null
}

variable "controller_priority_class_name" {
  description = "PriorityClass for the controller's pods. Null keeps the chart's system-cluster-critical. The same input on gcp-karpenter-controller-release takes a class of the consumer's own, because GKE refuses that class outside its own namespaces. Validated by karpenter-controller-contract."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
