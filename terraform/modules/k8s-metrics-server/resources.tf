resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = var.namespace
  create_namespace = false
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.chart_version

  values = [yamlencode({
    args = ["--kubelet-preferred-address-types=InternalIP"]
  })]

  wait = true
}
