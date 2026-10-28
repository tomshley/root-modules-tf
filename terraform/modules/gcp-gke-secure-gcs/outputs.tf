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

output "bucket_name" {
  value = module.secure_gcs.bucket_name
}

output "bucket_arn" {
  value = module.secure_gcs.bucket_arn
}

output "bucket_id" {
  value = module.secure_gcs.bucket_id
}

output "readwrite_policy_arn" {
  value = module.secure_gcs.readwrite_policy_arn
}

output "readonly_policy_arn" {
  value = module.secure_gcs.readonly_policy_arn
}
