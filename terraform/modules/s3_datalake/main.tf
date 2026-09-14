resource "aws_s3_bucket" "datalake" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket                  = aws_s3_bucket.datalake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  rule {
    id     = "archive-bronze-after-30-days"
    status = "Enabled"

    filter { prefix = "bronze/" }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "clean-athena-results"
    status = "Enabled"

    filter { prefix = "athena-results/" }

    expiration {
      days = 7
    }
  }
}

variable "bucket_name" {
  type = string
}

output "bucket_name" {
  value = aws_s3_bucket.datalake.id
}

output "bucket_arn" {
  value = aws_s3_bucket.datalake.arn
}