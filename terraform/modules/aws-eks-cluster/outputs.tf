output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_ca_certificate" {
  value     = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  sensitive = true
}

output "cluster_security_group_id" {
  # EKS-managed SG — automatically attached to both control plane and node groups.
  # The custom additional SG (eks_cluster_sg) is only on the control plane, so
  # downstream consumers (RDS, ElastiCache, etc.) must reference this managed SG
  # to allow traffic from pods running on nodes.
  value = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks_oidc.arn
}

output "oidc_provider_url" {
  value = replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")
}

output "cluster_iam_role_arn" {
  value = aws_iam_role.eks_cluster_role.arn
}
