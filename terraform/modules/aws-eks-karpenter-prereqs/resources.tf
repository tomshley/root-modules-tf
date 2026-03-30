data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.project_name_prefix}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account_name}"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-controller"
  })
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.project_name_prefix}-karpenter-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Permissions"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Sid      = "SSM"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/*"
      },
      {
        Sid      = "Pricing"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "SQS"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      },
      {
        Sid      = "EKS"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid    = "InstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-controller-policy"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}

resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name_prefix}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-node"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.project_name_prefix}-karpenter-node"
  role = aws_iam_role.karpenter_node.name

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-node"
  })
}

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.project_name_prefix}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-interruption"
  })
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name = "${var.project_name_prefix}-karpenter-spot-interruption"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-spot-interruption"
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name = "${var.project_name_prefix}-karpenter-rebalance"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-rebalance"
  })
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule = aws_cloudwatch_event_rule.rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "health" {
  name = "${var.project_name_prefix}-karpenter-health"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-karpenter-health"
  })
}

resource "aws_cloudwatch_event_target" "health" {
  rule = aws_cloudwatch_event_rule.health.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
