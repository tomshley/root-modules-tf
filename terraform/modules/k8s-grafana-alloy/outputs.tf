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

output "enabled" { value = local.release_ready }
output "namespace" { value = local.release_ready ? var.namespace : null }
output "release_name" { value = local.release_ready ? helm_release.k8s_monitoring[0].name : null }
output "credential_source" { value = local.release_ready ? (local.use_secret_ref ? "secret" : "inline") : "none" }
output "chart_version" { value = var.chart_version }
