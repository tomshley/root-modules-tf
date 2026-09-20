resource "helm_release" "crds" {
  name             = "karpenter-crd"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter-crd"
  version          = "0.3.0"
  wait             = true
  timeout          = var.helm_timeout_seconds
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter"
  version          = "0.3.0"

  values = concat([yamlencode({
    credentials = { enabled = false }
    serviceAccount = {
      create = true
      name   = var.kubernetes_service_account_name
      annotations = {
        "iam.gke.io/gcp-service-account" = var.controller_google_service_account_email
      }
    }
    controller = {
      image = {
        repository = "public.ecr.aws/cloudpilotai/gcp/karpenter"
        tag        = "v0.3.0"
      }
      env = [{ name = "DEFAULT_NODEPOOL_SERVICE_ACCOUNT", value = var.node_service_account_email }]
      settings = merge({
        projectID       = var.project_id
        clusterName     = var.cluster_name
        clusterLocation = var.cluster_location
        }, var.node_location == null ? {} : {
        nodeLocation = var.node_location
      })
    }
  })], var.extra_helm_values)

  depends_on = [helm_release.crds]
  wait       = true
  timeout    = var.helm_timeout_seconds
}
