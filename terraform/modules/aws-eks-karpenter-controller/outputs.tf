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

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.karpenter.name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.karpenter.namespace
}

output "release_version" {
  description = "Chart version of the Helm release"
  value       = helm_release.karpenter.version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.karpenter.status
}
