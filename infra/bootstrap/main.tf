# One-time bootstrap per AWS account: remote state bucket, its KMS key, and the
# GitHub OIDC trust used by CI. This root starts with local state (nothing
# exists yet to hold it); after the first apply, migrate it into the bucket it
# created with `terraform init -migrate-state -backend-config=...`.
# NOT APPLIED in this assessment (no AWS account in scope).

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "continuity-platform", ManagedBy = "Terraform", Layer = "bootstrap" }
  }
}

variable "aws_region" { type = string }
variable "state_bucket_name" { type = string }
variable "github_repository" {
  type        = string
  description = "owner/repo allowed to assume the CI roles, e.g. Bhavesh866/DevOps"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "state" {
  description         = "Terraform state encryption"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" } # recover from a corrupted/overwritten state
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
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
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

# GitHub Actions OIDC: CI gets short-lived credentials, no stored AWS keys.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "drift_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/master"]
    }
  }
}

# Read-only role for scheduled drift detection (terraform plan, never apply).
resource "aws_iam_role" "drift" {
  name               = "continuity-terraform-drift"
  assume_role_policy = data.aws_iam_policy_document.drift_trust.json
}

resource "aws_iam_role_policy_attachment" "drift_readonly" {
  role       = aws_iam_role.drift.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "drift_state" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "drift_state" {
  name   = "state-read"
  role   = aws_iam_role.drift.id
  policy = data.aws_iam_policy_document.drift_state.json
}

output "state_bucket" { value = aws_s3_bucket.state.id }
output "state_kms_key_arn" { value = aws_kms_key.state.arn }
output "drift_role_arn" { value = aws_iam_role.drift.arn }
output "account_id" { value = data.aws_caller_identity.current.account_id }
