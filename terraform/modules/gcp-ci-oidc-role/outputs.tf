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
  value       = google_iam_workload_identity_pool.ci.name
  description = "Fully qualified name of the Workload Identity Pool (projects/{n}/locations/global/workloadIdentityPools/{id})."
}

output "workload_identity_provider_name" {
  value       = google_iam_workload_identity_pool_provider.ci.name
  description = "Fully qualified name of the OIDC workload identity provider — the value a CI platform uses for Workload Identity Federation."
}

output "service_account_email" {
  value       = google_service_account.ci_deploy.email
  description = "Email of the federated CI service account — the identity a pipeline impersonates."
}

output "service_account_id" {
  value       = google_service_account.ci_deploy.account_id
  description = "ID of the federated CI service account ({project_name_prefix}-ci-{role_name_suffix})."
}

output "issuer_host" {
  value       = module.trust.issuer_host
  description = "Normalized issuer host the trust conditions are keyed on."
}
