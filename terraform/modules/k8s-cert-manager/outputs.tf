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

output "issuer_name" {
  description = "ClusterIssuer name, available after its Helm release is installed."
  value       = var.issuer.name
  depends_on  = [helm_release.configuration]
}

output "issuer_kind" {
  description = "Issuer reference kind."
  value       = "ClusterIssuer"
  depends_on  = [helm_release.configuration]
}

output "namespace" {
  description = "Namespace for cert-manager and the existing DNS credential Secret."
  value       = helm_release.controller.namespace
}

output "release_status" {
  description = "cert-manager controller Helm release status, not issuer or certificate readiness."
  value       = helm_release.controller.status
}
