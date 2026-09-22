locals {
  chart_version = "0.6.0"

  upstream_controller_image = {
    repository = "public.ecr.aws/cloudpilotai/gcp/karpenter"
    tag        = "v0.6.0"
  }
  # Vendored build of the same provider carrying the dual-stack NIC patch;
  # tags track the chart version so a chart bump implies the matching patch
  # build rather than a stale controller.
  vendored_dual_stack_image = {
    repository = "registry.gitlab.com/tomshley/brands/global/tware/tech/products/provisioning/vendored/karpenter-provider-gcp/karpenter"
    tag        = "v${local.chart_version}-dualstack"
  }

  controller_image = coalesce(
    var.controller_image,
    var.use_patched_dual_stack_image ? local.vendored_dual_stack_image : null,
    local.upstream_controller_image,
  )
}

resource "helm_release" "crds" {
  name             = "karpenter-crd"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter-crd"
  version          = local.chart_version
  wait             = true
  timeout          = var.helm_timeout_seconds
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter"
  version          = local.chart_version

  values = concat([yamlencode(merge({
    credentials = { enabled = false }
    serviceAccount = {
      create = true
      name   = var.kubernetes_service_account_name
      annotations = {
        "iam.gke.io/gcp-service-account" = var.controller_google_service_account_email
      }
    }
    controller = {
      image = local.controller_image
      env   = [{ name = "DEFAULT_NODEPOOL_SERVICE_ACCOUNT", value = var.node_service_account_email }]
      settings = merge({
        projectID       = var.project_id
        clusterName     = var.cluster_name
        clusterLocation = var.cluster_location
        }, var.node_location == null ? {} : {
        nodeLocation = var.node_location
        }, var.bootstrap_node_pool_name == null ? {} : {
        defaultNodePoolTemplateName = var.bootstrap_node_pool_name
      })
    }
  }, length(var.image_pull_secrets) > 0 ? { imagePullSecrets = var.image_pull_secrets } : {}))], var.extra_helm_values)

  depends_on = [helm_release.crds]
  wait       = true
  timeout    = var.helm_timeout_seconds
}
