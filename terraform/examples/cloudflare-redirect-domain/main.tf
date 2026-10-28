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

variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
}

module "cloudflare_redirect_domain" {
  source = "../../modules/cloudflare-redirect-domain"

  zone_name       = "legacy-example.com"
  account_id      = var.account_id
  redirect_target = "example.com"
  redirect_code   = 301
  preserve_path   = true
  preserve_query  = true
}
