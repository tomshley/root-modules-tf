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

output "release_name" { value = module.keycloak.release_name }
output "release_namespace" { value = module.keycloak.release_namespace }
output "release_version" { value = module.keycloak.release_version }
output "release_status" { value = module.keycloak.release_status }
output "keycloak_service_name" { value = module.keycloak.keycloak_service_name }
output "keycloak_service_port" { value = module.keycloak.keycloak_service_port }
output "base_url" { value = module.keycloak.base_url }
output "jwks_uri_template" { value = module.keycloak.jwks_uri_template }
output "admin_console_url" { value = module.keycloak.admin_console_url }
