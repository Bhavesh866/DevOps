# Secrets: AWS Secrets Manager is the source of truth; External Secrets
# Operator (platform layer) syncs <tenant>/<env>/app-secrets into the cluster
# using IRSA, so no credentials live in git, CI variables or images.
#
# Two credentials, two treatments:
# - RDS master (admin) password: generated and rotated by RDS
#   (manage_master_user_password); never in Terraform state, never given to the cluster.
# - Application DB role and Redis token: generated here, so they are in
#   Terraform state; state is KMS-encrypted and access-restricted (infra/bootstrap).
#   The application role is created in PostgreSQL by a one-off bootstrap job
#   using the admin secret (designed, not implemented in this repository).

resource "random_password" "app_db" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name       = "${var.tenant}/${var.environment}/app-secrets"
  kms_key_id = aws_kms_key.data.arn
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    DATABASE_URL   = "postgres://app:${random_password.app_db.result}@${aws_db_instance.this.address}:5432/app?sslmode=require"
    REDIS_URL      = "rediss://:${random_password.redis_auth.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/0"
    REDIS_ADDRESS  = "${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
    REDIS_PASSWORD = random_password.redis_auth.result
  })
}

# IRSA role for External Secrets Operator: read exactly this one secret.
data "aws_iam_policy_document" "eso_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.tenant}-${var.environment}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
}

data "aws_iam_policy_document" "eso_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "eso_read" {
  name   = "read-app-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

# Immutable tags: a pushed digest can never be replaced under the same tag.
resource "aws_ecr_repository" "app" {
  name                 = "${var.tenant}/continuity-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data.arn
  }
}
