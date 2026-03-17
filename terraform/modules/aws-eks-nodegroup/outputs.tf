output "node_group_arn" {
  value = aws_eks_node_group.node_group.arn
}

output "node_group_status" {
  value = aws_eks_node_group.node_group.status
}

output "node_role_arn" {
  value = aws_iam_role.node_role.arn
}
