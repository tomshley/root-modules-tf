data "aws_iam_policy_document" "tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.secure.arn,
      "${aws_s3_bucket.secure.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket" "secure" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "secure" {
  bucket = aws_s3_bucket.secure.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure" {
  bucket = aws_s3_bucket.secure.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_id : null
    }

    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }
}

resource "aws_s3_bucket_versioning" "secure" {
  bucket = aws_s3_bucket.secure.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "secure" {
  count  = var.lifecycle_expiration_days > 0 || var.lifecycle_glacier_transition_days > 0 || var.lifecycle_deep_archive_transition_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.secure.id

  rule {
    id     = "lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    dynamic "transition" {
      for_each = var.lifecycle_glacier_transition_days > 0 ? [1] : []
      content {
        days          = var.lifecycle_glacier_transition_days
        storage_class = "GLACIER"
      }
    }

    dynamic "transition" {
      for_each = var.lifecycle_deep_archive_transition_days > 0 ? [1] : []
      content {
        days          = var.lifecycle_deep_archive_transition_days
        storage_class = "DEEP_ARCHIVE"
      }
    }
  }
}

resource "aws_s3_bucket_logging" "secure" {
  count         = var.logging_target_bucket != "" ? 1 : 0
  bucket        = aws_s3_bucket.secure.id
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}

resource "aws_s3_bucket_policy" "secure" {
  bucket = aws_s3_bucket.secure.id
  policy = data.aws_iam_policy_document.tls_only.json
}

resource "aws_iam_policy" "readwrite" {
  name = "${var.project_name_prefix}-s3-readwrite"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.secure.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.secure.arn}/*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-s3-readwrite"
  })
}

resource "aws_iam_policy" "readonly" {
  name = "${var.project_name_prefix}-s3-readonly"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.secure.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.secure.arn}/*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-s3-readonly"
  })
}
