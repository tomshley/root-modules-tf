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

resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = coalesce(var.display_name, var.service_account_id)
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.kubernetes_service_account_name}]"
}

resource "google_project_iam_member" "workload" {
  count = length(var.project_roles)

  project = var.project_id
  role    = var.project_roles[count.index]
  member  = "serviceAccount:${google_service_account.workload.email}"
}

resource "google_storage_bucket_iam_member" "workload" {
  for_each = { for descriptor in var.resource_iam_members : "${descriptor.resource_name}|${descriptor.role}" => descriptor }

  bucket = each.value.resource_name
  role   = each.value.role
  member = "serviceAccount:${google_service_account.workload.email}"
}
