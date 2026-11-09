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

output "gateway_name" {
  value = module.gateway.gateway_name
  precondition {
    condition     = var.resources_requests_cpu == null || var.resources_limits_cpu == null ? true : try(local.gateway_quantity_nanos["requests_cpu"] <= local.gateway_quantity_nanos["limits_cpu"], false)
    error_message = "resources_requests_cpu must not exceed resources_limits_cpu."
  }
  precondition {
    condition     = var.resources_requests_memory == null || var.resources_limits_memory == null ? true : try(local.gateway_quantity_nanos["requests_memory"] <= local.gateway_quantity_nanos["limits_memory"], false)
    error_message = "resources_requests_memory must not exceed resources_limits_memory."
  }
}
output "gateway_namespace" { value = module.gateway.gateway_namespace }
output "gateway_class_name" { value = module.gateway.gateway_class_name }
output "service_name" { value = module.gateway.service_name }
output "load_balancer_hostname" { value = module.gateway.load_balancer_hostname }
output "load_balancer_ip" { value = module.gateway.load_balancer_ip }
output "listener_names" { value = module.gateway.listener_names }
