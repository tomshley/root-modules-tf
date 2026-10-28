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


output "google_project_id" {
  value = module.gcp-project.project_id
}

output "project_name_prefix" {
  value = var.project_name_prefix
}

output "google_project_org_id" {
  value = var.google_organization_id
}

output "google_project_billing_account" {
  value = var.google_billing_account
}

