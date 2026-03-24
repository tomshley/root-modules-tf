output "bucket_name" {
  value = aws_s3_bucket.secure.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.secure.arn
}

output "bucket_id" {
  value = aws_s3_bucket.secure.id
}

output "readwrite_policy_arn" {
  value = aws_iam_policy.readwrite.arn
}

output "readonly_policy_arn" {
  value = aws_iam_policy.readonly.arn
}
