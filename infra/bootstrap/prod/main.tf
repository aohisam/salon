data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "tfstate-${var.env}-${var.project}-${local.account_id}"
  lock_table  = "tf-lock-${var.env}-${var.project}"
  kms_alias   = "alias/tfstate-${var.env}-${var.project}"

  tags = {
    Project   = var.project
    Env       = var.env
    ManagedBy = "Terraform"
  }
}

# ---- KMS (SSE-KMS用) ----
resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform state (${var.env})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "tfstate" {
  name          = local.kms_alias
  target_key_id = aws_kms_key.tfstate.key_id
}

# ---- S3 bucket (Terraform state) ----
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
  }
}

# ---- S3 bucket policy: TLS必須 + SSE-KMS必須 ----
data "aws_iam_policy_document" "tfstate_bucket_policy" {
  # TLS必須
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # SSE-KMS必須（PutObject時に暗号化ヘッダがない/違う方式なら拒否）
  statement {
    sid     = "DenyIncorrectEncryptionHeader"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid     = "DenyUnEncryptedObjectUploads"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_bucket_policy.json
}

# ---- DynamoDB (Terraform lock) ----
resource "aws_dynamodb_table" "tf_lock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  tags         = local.tags

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---- outputs（後でbackend設定で使う） ----
output "tfstate_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "tf_lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

output "tfstate_kms_key_arn" {
  value = aws_kms_key.tfstate.arn
}
