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

locals {
  normalized = {
    host                 = var.binding.host
    port                 = var.binding.port
    database_name        = var.binding.database_name
    tls_required         = var.binding.tls_required
    ca_secret_name       = var.binding.ca_secret_name
    username_secret_name = var.binding.username_secret_name
    password_secret_name = var.binding.password_secret_name
    reader_host          = var.binding.reader_host
    reader_capable       = var.binding.reader_capable
  }
}
