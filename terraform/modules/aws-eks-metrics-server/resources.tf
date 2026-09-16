module "metrics_server" {
  source = "../k8s-metrics-server"

  chart_version = var.metrics_server_version
  namespace     = var.metrics_server_namespace
}
