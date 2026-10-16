# Provider-layer interface. Every provider root (aws today, a second cloud for
# the change request) must expose the same logical outputs so the platform
# and application layers do not depend on which cloud they run on.
output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "workload_identity_provider" { value = module.eks.oidc_provider_arn }

output "postgres_endpoint" { value = aws_db_instance.this.address }
output "postgres_admin_secret" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
output "app_secrets" { value = aws_secretsmanager_secret.app.name }
output "secret_reader_role" { value = aws_iam_role.eso.arn }
output "image_repository" { value = aws_ecr_repository.app.repository_url }
