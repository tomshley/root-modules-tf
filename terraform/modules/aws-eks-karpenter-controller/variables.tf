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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
