###############################################################################
# Karpenter Controller — Helm Release
#
# Installs the Karpenter controller into an existing EKS cluster.
# Requires aws-eks-karpenter-prereqs to be applied first (IAM roles, SQS queue).
#
# Consumers must configure the Helm provider with EKS cluster credentials
# before calling this module.
###############################################################################

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = false
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = var.karpenter_interruption_queue_name
      }
      serviceAccount = {
        name = var.karpenter_service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = var.karpenter_controller_role_arn
        }
      }
    })
  ]

  wait = true
}
