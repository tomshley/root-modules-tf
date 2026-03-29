###############################################################################
# Metrics Server — Helm Release
#
# Installs the Kubernetes Metrics Server into an existing EKS cluster.
# Required for HorizontalPodAutoscaler CPU/memory metrics.
#
# Consumers must configure the Helm provider with EKS cluster credentials
# before calling this module.
###############################################################################

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = var.metrics_server_namespace
  create_namespace = false
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_version

  values = [
    yamlencode({
      args = [
        "--kubelet-preferred-address-types=InternalIP"
      ]
    })
  ]

  wait = true
}
