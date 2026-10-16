# Data layer: PostgreSQL (RDS Multi-AZ) and Redis (ElastiCache, replicated).
# Both are private, reachable only from EKS nodes, encrypted at rest with a
# stack-specific KMS key and in transit. Backups and snapshots stay in
# var.aws_region (EU residency: no cross-region copies are configured).

resource "aws_kms_key" "data" {
  description         = "${var.tenant}-${var.environment} data encryption"
  enable_key_rotation = true
}

# ---------------------------------------------------------------- PostgreSQL

resource "aws_db_subnet_group" "this" {
  name       = "${var.tenant}-${var.environment}-db"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "db" {
  name        = "${var.tenant}-${var.environment}-db"
  description = "PostgreSQL reachable from EKS nodes only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.tenant}-${var.environment}-pg17"
  family = "postgres17"

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
  # Fail fast on lock contention so a migration cannot stall live traffic.
  parameter {
    name  = "lock_timeout"
    value = "5000"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.tenant}-${var.environment}"
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  db_name  = "app"
  username = "app_admin"
  # RDS generates the password and stores/rotates it in Secrets Manager;
  # it never appears in Terraform state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.data.arn

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_allocated_storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.data.arn

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period   = var.db_backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.tenant}-${var.environment}-final"

  iam_database_authentication_enabled = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.data.arn
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  auto_minor_version_upgrade          = true
}

# --------------------------------------------------------------------- Redis

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.tenant}-${var.environment}-redis"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "redis" {
  name        = "${var.tenant}-${var.environment}-redis"
  description = "Redis reachable from EKS nodes only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from EKS nodes"
}

resource "random_password" "redis_auth" {
  length  = 48
  special = false
}

# Replication is asynchronous: a primary failover can lose the last writes,
# i.e. recently enqueued or completed jobs. The worker's reliable-queue
# pattern handles worker loss, not Redis data loss; see risks in architecture.md.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.tenant}-${var.environment}"
  description          = "Job queue for ${var.tenant}-${var.environment}"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  port                 = 6379

  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.data.arn
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  snapshot_retention_limit = 3
  snapshot_window          = "01:00-02:00"
}
