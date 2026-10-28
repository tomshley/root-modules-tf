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

output "enabled" {
  value = module.alloy.enabled
}

output "namespace" {
  value = module.alloy.namespace
}

output "release_name" {
  value = module.alloy.release_name
}

output "credential_source" {
  value = module.alloy.credential_source
}

output "chart_version" {
  value = module.alloy.chart_version
}
