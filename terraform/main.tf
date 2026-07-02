terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── S3 Bucket ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "images" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Rekognition needs s3:GetObject on the bucket to read images directly.
# This bucket policy enforces that only the Rekognition access role can read objects.
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRekognitionRoleListBucket"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.rekognition_access.arn
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.images.arn
      },
      {
        Sid    = "AllowRekognitionRoleGetObject"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.rekognition_access.arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })
}

# ─── IAM Role (in this account, assumed by the runtime) ──────────────────────

data "aws_iam_policy_document" "assume_role_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${var.runtime_account_id}:role/${var.runtime_role_name}"
      ]
    }
  }
}

resource "aws_iam_role" "rekognition_access" {
  name               = var.rekognition_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_trust.json
}

data "aws_iam_policy_document" "rekognition_access" {
  statement {
    sid    = "AllowDetectText"
    effect = "Allow"
    actions = [
      "rekognition:DetectText",
    ]
    resources = ["*"] # Rekognition DetectText has no resource-level restriction
  }

  statement {
    sid    = "AllowS3Access"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [
      aws_s3_bucket.images.arn,
      "${aws_s3_bucket.images.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "rekognition_access" {
  name   = "rekognition-and-s3-access"
  role   = aws_iam_role.rekognition_access.id
  policy = data.aws_iam_policy_document.rekognition_access.json
}
