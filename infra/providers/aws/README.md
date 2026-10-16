# AWS Terraform starter — not production-complete

This root creates only a VPC and public/private subnets. It does **not** create EKS, RDS, ElastiCache, NAT, route tables, security groups, IAM, ECR, KMS, Secrets Manager, observability or DNS. Do not apply to production as-is.

Before apply: configure encrypted/locked remote state and recovery; validate CIDRs/AZs; add routes, controlled egress, endpoints and flow logs; add EKS with IRSA/private endpoint/logging/encryption; add RDS Multi-AZ/PITR/deletion protection; add Redis replication/TLS/auth; add ECR/KMS/Secrets Manager and least-privilege policies. Run fmt, init, validate and reviewed plan in a non-production account.
