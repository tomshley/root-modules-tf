module "metrics_server" {
  source = "../k8s-metrics-server"

  namespace     = var.namespace
  chart_version = var.chart_version
}
