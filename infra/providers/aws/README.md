# AWS provider layer — network foundation only

## What this root creates

- VPC with DNS support and hostnames.
- Public and private subnets, one pair per AZ (at least two AZs), with EKS load-balancer discovery tags.
- Internet gateway and a public route table.
- One NAT gateway per AZ and a private route table per AZ (no cross-AZ NAT dependency).
- Optional `eu_region_guard` precondition that fails plan/apply outside an approved EU region list.

## What it does not create

EKS, RDS PostgreSQL, ElastiCache Redis, security groups, IAM/IRSA, ECR, KMS, Secrets Manager,
VPC endpoints, flow logs, observability, DNS, or a remote state backend. Do not apply to production as-is.

## Verification status

`fmt -check`, `init -backend=false` and `validate` run locally and in CI.
No `plan` or `apply` has been run: there is no AWS account in scope for this assessment.

## Before any apply

Configure encrypted, locked remote state; validate CIDRs/AZs against the target account; add VPC
endpoints and flow logs; add EKS (private endpoint, IRSA, control-plane logging, secrets encryption),
RDS Multi-AZ with PITR and deletion protection, Redis with replication/TLS/auth, ECR, KMS and
Secrets Manager with least-privilege policies. Run a reviewed `plan` in a non-production account first.
