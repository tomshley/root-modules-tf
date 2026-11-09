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
  value = var.name
  precondition {
    condition     = var.resources_requests_cpu == null || var.resources_limits_cpu == null ? true : try(local.gateway_quantity_nanos["requests_cpu"] <= local.gateway_quantity_nanos["limits_cpu"], false)
    error_message = "resources_requests_cpu must not exceed resources_limits_cpu."
  }
  precondition {
    condition     = var.resources_requests_memory == null || var.resources_limits_memory == null ? true : try(local.gateway_quantity_nanos["requests_memory"] <= local.gateway_quantity_nanos["limits_memory"], false)
    error_message = "resources_requests_memory must not exceed resources_limits_memory."
  }
}
output "gateway_namespace" { value = var.namespace }
output "gateway_class_name" { value = local.class_name }
output "service_name" { value = local.service_name }
output "listener_names" { value = keys(var.listeners) }
output "load_balancer_hostname" {
  value = var.service_type == "NodePort" ? null : try(compact([for address in data.kubernetes_service_v1.proxy[0].status[0].load_balancer[0].ingress : address.hostname])[0], null)
}
output "load_balancer_ip" {
  value = var.service_type == "NodePort" ? null : try(compact([for address in data.kubernetes_service_v1.proxy[0].status[0].load_balancer[0].ingress : address.ip])[0], null)
}
