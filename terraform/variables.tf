variable "aws_region" {
  description = "AWS region for the S3 bucket and Rekognition service."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket that will hold images for Rekognition."
  type        = string
}

variable "runtime_account_id" {
  description = "AWS account ID where the AgentCore runtime (and AgentCoreRuntimeRole) lives. This account is trusted to assume the Rekognition access role."
  type        = string
}

variable "runtime_role_name" {
  description = "Name of the IAM role in the runtime account that will assume the Rekognition access role."
  type        = string
  default     = "AgentCoreRuntimeRole"
}

variable "rekognition_role_name" {
  description = "Name of the IAM role created in this account to grant Rekognition and S3 access."
  type        = string
  default     = "RekognitionAccessRole"
}
