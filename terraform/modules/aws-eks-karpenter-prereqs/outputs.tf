output "controller_role_arn" {
  value = aws_iam_role.karpenter_controller.arn
}

output "node_role_arn" {
  value = aws_iam_role.karpenter_node.arn
}

output "node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.karpenter_node.name
}

output "sqs_queue_name" {
  value = aws_sqs_queue.karpenter_interruption.name
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.karpenter_interruption.arn
}
