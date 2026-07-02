output "bucket_name" {
  description = "Name of the S3 bucket for images."
  value       = aws_s3_bucket.images.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.images.arn
}

output "rekognition_role_arn" {
  description = "ARN of the IAM role to assume for Rekognition access. Set this as REKOGNITION_ROLE_ARN in the agent runtime environment."
  value       = aws_iam_role.rekognition_access.arn
}
