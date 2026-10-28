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

variable "project_name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN from EKS cluster module"
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL (without https://) from EKS cluster module"
}

variable "karpenter_namespace" {
  type    = string
  default = "kube-system"
}

variable "karpenter_service_account_name" {
  type    = string
  default = "karpenter"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
