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

variable "public_hostname" {
  type    = string
  default = "auth.example.test"
}
variable "project_id" {
  type    = string
  default = "example-project"
}
variable "db_endpoint" {
  type    = string
  default = "postgres.database.svc.cluster.local"
}
variable "zone_id" {
  type    = string
  default = "00000000000000000000000000000000"
}
variable "kube_config_path" {
  type    = string
  default = "~/.kube/config"
}
