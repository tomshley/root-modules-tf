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

output "workload_identity_pool_name" {
  value = google_iam_workload_identity_pool.ci.name
}

output "workload_identity_provider_name" {
  value = google_iam_workload_identity_pool_provider.ci.name
}

output "service_account_email" {
  value = google_service_account.ci_deploy.email
}

output "service_account_id" {
  value = google_service_account.ci_deploy.account_id
}

output "kubernetes_rbac_admin_role_name" {
  value = try(google_project_iam_custom_role.kubernetes_rbac_admin[0].name, null)
}
