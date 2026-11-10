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
  gateway_dns_subdomain_pattern  = "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$"
  gateway_qualified_name_pattern = "^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$"
  gateway_label_value_pattern    = "^([A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?)?$"
  gateway_quantity_pattern       = "^(?P<amount>[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+))(?P<suffix>[numkMGTPE]|[KMGTPE]i|[eE][+-]?[0-9]+)?$"
  gateway_decimal_exponents      = { "" = 0, n = -9, u = -6, m = -3, k = 3, M = 6, G = 9, T = 12, P = 15, E = 18 }
  gateway_binary_factors         = { Ki = 1024, Mi = 1048576, Gi = 1073741824, Ti = 1099511627776, Pi = 1125899906842624, Ei = 1152921504606846976 }
  gateway_quantity_parts = {
    for key, value in {
      requests_cpu = var.resources_requests_cpu, requests_memory = var.resources_requests_memory,
      limits_cpu   = var.resources_limits_cpu, limits_memory = var.resources_limits_memory
    } : key => value == null ? null : try(regex(local.gateway_quantity_pattern, value), null)
  }
  gateway_quantity_raw_nanos = {
    for key, parts in local.gateway_quantity_parts : key => parts == null ? null : try(
      tonumber("${parts.amount}e${9 + (can(regex("^[eE][+-]?[0-9]+$", parts.suffix)) ? tonumber(substr(parts.suffix, 1, -1)) : lookup(local.gateway_decimal_exponents, parts.suffix == null ? "" : parts.suffix, 0))}") *
      lookup(local.gateway_binary_factors, parts.suffix == null ? "" : parts.suffix, 1), null
    )
  }
  gateway_quantity_nanos = {
    for key, value in local.gateway_quantity_raw_nanos : key => value == null ? null : ceil(
      contains(keys(local.gateway_binary_factors), local.gateway_quantity_parts[key].suffix == null ? "" : local.gateway_quantity_parts[key].suffix) ? min(value, 9223372036854775807000000000) : value
    )
  }
  gateway_reserved_labels = [
    "app.kubernetes.io/name", "app.kubernetes.io/component", "app.kubernetes.io/managed-by",
    "gateway.envoyproxy.io/owning-gateway-name", "gateway.envoyproxy.io/owning-gateway-namespace",
    "gateway.envoyproxy.io/owning-gatewayclass", "gateway.networking.k8s.io/gateway-name", "gateway-instance", "app.kubernetes.io/part-of",
    "app.kubernetes.io/instance", "app.kubernetes.io/version", "helm.sh/chart", "control-plane"
  ]
}

variable "name" {
  type     = string
  nullable = false
  validation {
    condition     = length(var.name) <= 53 && can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be a DNS-1035 label of at most 53 characters."
  }
}
variable "namespace" {
  type     = string
  nullable = false
  validation {
    condition     = length(var.namespace) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS label."
  }
}
variable "create_namespace" {
  type    = bool
  default = false
}
variable "chart_version" {
  type     = string
  nullable = false
  validation {
    condition     = var.chart_version == "v1.9.3"
    error_message = "chart_version must be v1.9.3, matching the verified images and CRD bootstrap."
  }
}
variable "listeners" {
  type = map(object({
    hostname        = string
    port            = optional(number, 443)
    protocol        = optional(string, "HTTPS")
    tls_secret_name = optional(string)
    tls_issuer = optional(object({
      name = string
      kind = optional(string, "ClusterIssuer")
    }))
    allowed_route_namespaces = optional(string, "Same")
    allowed_route_selector   = optional(map(string))
  }))
  nullable = false
  validation {
    condition     = length(var.listeners) >= 1 && length(var.listeners) <= 64
    error_message = "listeners must contain between 1 and 64 entries."
  }
  validation {
    condition     = alltrue([for name in keys(var.listeners) : length(name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name))])
    error_message = "Listener names must be DNS labels."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : try(length(listener.hostname) <= 253 && can(regex("^(\\*\\.)?[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", listener.hostname)), false)])
    error_message = "Listener hostnames must be valid DNS hostnames."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : !can(cidrhost("${listener.hostname}/32", 0))])
    error_message = "Listener hostnames must not be IP literals."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : contains(["HTTPS", "HTTP", "TLS"], listener.protocol)])
    error_message = "Listener protocol must be HTTPS, HTTP or TLS."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.port >= 1 && listener.port <= 65535 && floor(listener.port) == listener.port])
    error_message = "Listener ports must be integers between 1 and 65535."
  }
  validation {
    condition     = length(distinct([for listener in values(var.listeners) : listener.port < 1024 ? listener.port + 10000 : listener.port])) == length(distinct([for listener in values(var.listeners) : listener.port]))
    error_message = "Listener ports must not collide after Envoy's privileged-port translation."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : !contains([19000, 19001, 19002, 19003], listener.port < 1024 ? listener.port + 10000 : listener.port)])
    error_message = "Listener ports must not use Envoy's reserved pod ports 19000, 19001, 19002 or 19003."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.protocol != "HTTPS" ? true : (listener.tls_secret_name != null) != (listener.tls_issuer != null)])
    error_message = "HTTPS listeners require exactly one of tls_secret_name or tls_issuer."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.protocol == "HTTPS" ? true : listener.tls_secret_name == null && listener.tls_issuer == null])
    error_message = "Only HTTPS listeners may specify termination credentials."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.tls_secret_name == null ? true : try(alltrue([length(listener.tls_secret_name) <= 253, can(regex(local.gateway_dns_subdomain_pattern, listener.tls_secret_name))]), false)])
    error_message = "tls_secret_name must be a DNS-1123 subdomain of at most 253 characters."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.tls_issuer == null ? true : try(trimspace(listener.tls_issuer.name) != "" && contains(["ClusterIssuer", "Issuer"], listener.tls_issuer.kind), false)])
    error_message = "tls_issuer needs a non-empty name and kind ClusterIssuer or Issuer."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.tls_issuer == null ? true : try(alltrue([length(listener.tls_issuer.name) <= 253, can(regex(local.gateway_dns_subdomain_pattern, listener.tls_issuer.name))]), false)])
    error_message = "tls_issuer.name must be a DNS-1123 subdomain of at most 253 characters."
  }
  validation {
    condition     = !anytrue([for listener in values(var.listeners) : listener.tls_issuer != null]) || alltrue([for listener in values(var.listeners) : listener.protocol != "HTTPS" || listener.tls_issuer != null])
    error_message = "When any listener uses tls_issuer, every HTTPS listener must use tls_issuer, not tls_secret_name."
  }
  validation {
    condition     = length(distinct([for listener in values(var.listeners) : jsonencode([listener.port, listener.protocol, listener.hostname])])) == length(var.listeners)
    error_message = "Listener port, protocol and hostname combinations must be unique."
  }
  validation {
    condition     = length(distinct([for listener in values(var.listeners) : jsonencode([listener.port, listener.protocol])])) == length(distinct([for listener in values(var.listeners) : listener.port]))
    error_message = "Listeners on a shared port must use the same protocol."
  }
  validation {
    condition     = length(distinct([for listener in values(var.listeners) : jsonencode(listener.tls_issuer) if listener.tls_issuer != null])) <= 1
    error_message = "All issuer-backed listeners must use the same issuer name and kind."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : contains(["Same", "All", "Selector"], listener.allowed_route_namespaces)])
    error_message = "allowed_route_namespaces must be Same, All or Selector."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.allowed_route_namespaces == "Selector" ? try(length(listener.allowed_route_selector) > 0, false) : listener.allowed_route_selector == null])
    error_message = "Selector requires a non-empty allowed_route_selector; other namespace modes must omit it."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.allowed_route_selector == null ? true : alltrue([for key in keys(listener.allowed_route_selector) : alltrue([length(split("/", key)[0]) <= 253, length(reverse(split("/", key))[0]) <= 63, can(regex(local.gateway_qualified_name_pattern, key))])])])
    error_message = "allowed_route_selector keys must be Kubernetes qualified names."
  }
  validation {
    condition     = alltrue([for listener in values(var.listeners) : listener.allowed_route_selector == null ? true : alltrue([for value in values(listener.allowed_route_selector) : try(alltrue([length(value) <= 63, can(regex(local.gateway_label_value_pattern, value))]), false)])])
    error_message = "allowed_route_selector values must be Kubernetes label values of at most 63 characters."
  }
  validation {
    condition     = !var.network_policy_enabled || alltrue([for listener in values(var.listeners) : listener.allowed_route_namespaces != "All"])
    error_message = "network_policy_enabled cannot be combined with All route namespaces."
  }
}
variable "service_type" {
  type    = string
  default = "LoadBalancer"
  validation {
    condition     = contains(["LoadBalancer", "NodePort"], var.service_type)
    error_message = "service_type must be LoadBalancer or NodePort."
  }
}
variable "service_annotations" {
  type    = map(string)
  default = {}
  validation {
    condition     = var.service_annotations == null ? true : alltrue([for key in keys(var.service_annotations) : alltrue([length(split("/", key)[0]) <= 253, length(reverse(split("/", key))[0]) <= 63, can(regex(local.gateway_qualified_name_pattern, lower(key)))])])
    error_message = "service_annotations keys must be Kubernetes qualified names."
  }
}
variable "replicas" {
  type    = number
  default = 2
  validation {
    condition     = var.replicas >= 1 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a positive integer."
  }
}
variable "pdb_min_available" {
  type    = number
  default = 1
  validation {
    condition     = var.pdb_min_available >= 0 && floor(var.pdb_min_available) == var.pdb_min_available && var.pdb_min_available < var.replicas
    error_message = "pdb_min_available must be a non-negative integer smaller than replicas."
  }
}
variable "resources_requests_cpu" {
  type    = string
  default = null
  validation {
    condition     = var.resources_requests_cpu == null ? true : can(regex(local.gateway_quantity_pattern, var.resources_requests_cpu))
    error_message = "resources_requests_cpu must be null or use Kubernetes Quantity syntax."
  }
  validation {
    condition     = var.resources_requests_cpu == null ? true : try(tonumber(regex(local.gateway_quantity_pattern, var.resources_requests_cpu).amount) >= 0, true)
    error_message = "resources_requests_cpu must not be negative."
  }
}
variable "resources_requests_memory" {
  type    = string
  default = null
  validation {
    condition     = var.resources_requests_memory == null ? true : can(regex(local.gateway_quantity_pattern, var.resources_requests_memory))
    error_message = "resources_requests_memory must be null or use Kubernetes Quantity syntax."
  }
  validation {
    condition     = var.resources_requests_memory == null ? true : try(tonumber(regex(local.gateway_quantity_pattern, var.resources_requests_memory).amount) >= 0, true)
    error_message = "resources_requests_memory must not be negative."
  }
}
variable "resources_limits_cpu" {
  type    = string
  default = null
  validation {
    condition     = var.resources_limits_cpu == null ? true : can(regex(local.gateway_quantity_pattern, var.resources_limits_cpu))
    error_message = "resources_limits_cpu must be null or use Kubernetes Quantity syntax."
  }
  validation {
    condition     = var.resources_limits_cpu == null ? true : try(tonumber(regex(local.gateway_quantity_pattern, var.resources_limits_cpu).amount) >= 0, true)
    error_message = "resources_limits_cpu must not be negative."
  }
}
variable "resources_limits_memory" {
  type    = string
  default = null
  validation {
    condition     = var.resources_limits_memory == null ? true : can(regex(local.gateway_quantity_pattern, var.resources_limits_memory))
    error_message = "resources_limits_memory must be null or use Kubernetes Quantity syntax."
  }
  validation {
    condition     = var.resources_limits_memory == null ? true : try(tonumber(regex(local.gateway_quantity_pattern, var.resources_limits_memory).amount) >= 0, true)
    error_message = "resources_limits_memory must not be negative."
  }
}
variable "network_policy_enabled" {
  type    = bool
  default = false
}
variable "labels" {
  type    = map(string)
  default = {}
  validation {
    condition     = var.labels == null ? true : alltrue([for key in keys(var.labels) : !contains(local.gateway_reserved_labels, key)])
    error_message = "labels must not override reserved Envoy selector, ownership, controller chart or gateway-instance labels."
  }
  validation {
    condition     = var.labels == null ? true : alltrue([for key in keys(var.labels) : alltrue([length(split("/", key)[0]) <= 253, length(reverse(split("/", key))[0]) <= 63, can(regex(local.gateway_qualified_name_pattern, key))])])
    error_message = "labels keys must be Kubernetes qualified names."
  }
  validation {
    condition     = var.labels == null ? true : alltrue([for value in values(var.labels) : try(alltrue([length(value) <= 63, can(regex(local.gateway_label_value_pattern, value))]), false)])
    error_message = "labels values must be Kubernetes label values of at most 63 characters."
  }
}
variable "helm_timeout" {
  type    = number
  default = 600
  validation {
    condition     = var.helm_timeout >= 2 && floor(var.helm_timeout) == var.helm_timeout
    error_message = "helm_timeout must be an integer of at least 2 seconds."
  }
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
}
variable "load_balancer_ip" {
  type    = string
  default = null
  validation {
    condition     = var.load_balancer_ip == null ? true : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.load_balancer_ip))
    error_message = "load_balancer_ip must name a reserved GCP address resource, not an IP literal."
  }
  validation {
    condition     = var.load_balancer_ip == null ? true : var.internal == true
    error_message = "load_balancer_ip requires internal = true; external Services do not support this annotation without loadBalancerClass."
  }
}
variable "internal" {
  type    = bool
  default = null
}
