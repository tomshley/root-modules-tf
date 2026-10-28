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

output "oidc_provider_arn" {
  value       = local.oidc_provider_arn
  description = "ARN of the IAM OIDC provider (existing or created)."
}

output "oidc_provider_created" {
  value       = local.create_oidc_provider
  description = "Whether this module created the provider (false when reusing an existing ARN)."
}

output "role_arn" {
  value       = aws_iam_role.ci.arn
  description = "ARN of the federated CI role."
}

output "role_name" {
  value       = aws_iam_role.ci.name
  description = "Name of the federated CI role."
}

output "issuer_host" {
  value       = module.trust.issuer_host
  description = "Normalized issuer host the trust conditions are keyed on."
}
