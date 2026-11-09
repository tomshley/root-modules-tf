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
  controller_name  = "eg-controller-${substr(sha256("${var.namespace}/${var.name}"), 0, 20)}"
  class_name       = "eg-${substr(sha256("${var.namespace}/${var.name}"), 0, 20)}"
  config_name      = "${substr(var.name, 0, 30)}-${substr(sha256(var.name), 0, 8)}-config"
  service_name     = "${var.name}-proxy"
  controller_image = "docker.io/envoyproxy/gateway@sha256:192fc9bdadb6d2462e8cf7bd702ce3dd9648f3310c6038787448a1f509b7cd9f"
  proxy_image      = "docker.io/envoyproxy/envoy@sha256:9d84a586119a27b50437dbb01eccd4722832741539b1ed53c8e9d6da6067a6e0"
  wait_image       = "registry.k8s.io/kubectl@sha256:59bafa07ff3a6d4b417e7633ddb9d79a9606ca98bf64bac080b3e65748669250"
  proxy_labels = merge(var.labels, {
    "gateway-instance"          = var.name
    "app.kubernetes.io/part-of" = var.name
  })
  metadata = { name = var.name, namespace = var.namespace, labels = var.labels }
  issuers  = distinct([for listener in values(var.listeners) : jsonencode(listener.tls_issuer) if listener.tls_issuer != null])
  issuer   = length(local.issuers) == 0 ? null : jsondecode(local.issuers[0])
  issuer_annotations = local.issuer == null ? {} : {
    (local.issuer.kind == "Issuer" ? "cert-manager.io/issuer" : "cert-manager.io/cluster-issuer") = local.issuer.name
  }
  listeners = [for name, listener in var.listeners : merge({
    name = name, hostname = listener.hostname, port = listener.port, protocol = listener.protocol
    allowedRoutes = { namespaces = merge(
      { from = listener.allowed_route_namespaces },
      listener.allowed_route_namespaces == "Selector" ? { selector = { matchLabels = listener.allowed_route_selector } } : {}
    ) }
    }, { for key, value in {
      tls = merge(
        { mode = listener.protocol == "TLS" ? "Passthrough" : "Terminate" },
        { for key, value in {
          certificateRefs = [{ group = "", kind = "Secret", name = listener.tls_secret_name != null ? listener.tls_secret_name : "${var.name}-${name}-tls" }]
        } : key => value if listener.protocol == "HTTPS" }
      )
  } : key => value if listener.protocol != "HTTP" })]
  resources = { for key, value in {
    requests = { for key, value in { cpu = var.resources_requests_cpu, memory = var.resources_requests_memory } : key => value if value != null }
    limits   = { for key, value in { cpu = var.resources_limits_cpu, memory = var.resources_limits_memory } : key => value if value != null }
  } : key => value if length(value) > 0 }
  controller_values = {
    crds                = { enabled = false }
    commonLabels        = var.labels
    global              = { images = { envoyGateway = { image = local.controller_image } } }
    deployment          = { replicas = 2 }
    podDisruptionBudget = { minAvailable = 1 }
    config = { envoyGateway = {
      gateway  = { controllerName = "gateway.envoyproxy.io/${local.class_name}" }
      provider = { type = "Kubernetes", kubernetes = { shutdownManager = { image = local.controller_image } } }
    } }
  }
  objects = [
    {
      apiVersion = "gateway.networking.k8s.io/v1", kind = "GatewayClass"
      metadata   = { name = local.class_name, labels = var.labels }
      spec = {
        controllerName = "gateway.envoyproxy.io/${local.class_name}"
        parametersRef  = { group = "gateway.envoyproxy.io", kind = "EnvoyProxy", name = var.name, namespace = var.namespace }
      }
    },
    {
      apiVersion = "gateway.envoyproxy.io/v1alpha1", kind = "EnvoyProxy"
      metadata   = local.metadata
      spec = { provider = { type = "Kubernetes", kubernetes = {
        envoyService = { name = local.service_name, type = var.service_type, annotations = var.service_annotations, labels = var.labels }
        envoyPDB     = { minAvailable = var.pdb_min_available }
        envoyDeployment = {
          replicas = var.replicas
          pod = { labels = local.proxy_labels, securityContext = {
            runAsNonRoot = true, runAsUser = 65532, runAsGroup = 65532, seccompProfile = { type = "RuntimeDefault" }
          } }
          container = merge({
            image = local.proxy_image
            securityContext = {
              runAsNonRoot = true, allowPrivilegeEscalation = false
              capabilities = { drop = ["ALL"] }
            }
          }, length(local.resources) == 0 ? {} : { resources = local.resources })
        }
      } } }
    },
    {
      apiVersion = "gateway.networking.k8s.io/v1", kind = "Gateway"
      metadata   = merge(local.metadata, { annotations = local.issuer_annotations })
      spec       = { gatewayClassName = local.class_name, listeners = local.listeners }
    },
    {
      apiVersion = "gateway.envoyproxy.io/v1alpha1", kind = "ClientTrafficPolicy"
      metadata   = local.metadata
      spec       = { targetRefs = [{ group = "gateway.networking.k8s.io", kind = "Gateway", name = var.name }], tls = { minVersion = "1.2" } }
    }
  ]
  namespace_peers = distinct([for listener in values(var.listeners) : jsonencode({
    namespaceSelector = {
      matchLabels = listener.allowed_route_namespaces == "Selector" ? listener.allowed_route_selector : { "kubernetes.io/metadata.name" = var.namespace }
    }
  })])
  policy = {
    apiVersion = "networking.k8s.io/v1", kind = "NetworkPolicy", metadata = local.metadata
    spec = {
      podSelector = { matchLabels = { "gateway-instance" = var.name } }
      policyTypes = ["Ingress", "Egress"]
      ingress = [{
        ports = [for port in sort(distinct([for listener in values(var.listeners) : tostring(listener.port < 1024 ? listener.port + 10000 : listener.port)])) : { protocol = "TCP", port = tonumber(port) }]
      }]
      egress = [
        {
          to    = [{ namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = "kube-system" } }, podSelector = { matchLabels = { "k8s-app" = "kube-dns" } } }]
          ports = [{ protocol = "UDP", port = 53 }, { protocol = "TCP", port = 53 }]
        },
        {
          to    = [{ namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = var.namespace } }, podSelector = { matchLabels = { "control-plane" = "envoy-gateway" } } }]
          ports = [{ protocol = "TCP", port = 18000 }]
        },
        { to = [for peer in local.namespace_peers : jsondecode(peer)] }
      ]
    }
  }
}

resource "helm_release" "controller" {
  name             = local.controller_name
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.chart_version
  skip_crds        = true
  wait             = true
  timeout          = var.helm_timeout
  values           = concat([jsonencode(local.controller_values)], var.extra_helm_values)
}

resource "helm_release" "configuration" {
  name          = local.config_name
  namespace     = var.namespace
  chart         = "${path.module}/chart"
  wait          = true
  wait_for_jobs = true
  timeout       = var.helm_timeout
  values = [jsonencode({
    objects   = concat(local.objects, var.network_policy_enabled ? [local.policy] : [])
    waitName  = local.config_name
    gateway   = var.name
    waitImage = local.wait_image
    timeout   = max(1, var.helm_timeout - 30)
    labels    = var.labels
  })]
  depends_on = [helm_release.controller]
}

data "kubernetes_service_v1" "proxy" {
  count = var.service_type == "LoadBalancer" ? 1 : 0
  metadata {
    name      = local.service_name
    namespace = var.namespace
  }
  depends_on = [helm_release.configuration]
}
