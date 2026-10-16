# 90-day roadmap

## Days 1–30: foundations
Confirm application contract, queue semantics, migrations and SLOs. Configure accounts, remote Terraform state, CI OIDC and least privilege. Provision private networking, EKS, ECR, encrypted RDS/ElastiCache and secret references in non-prod. Add scan/SBOM/signing and digest promotion. Establish baseline traffic and DB metrics.
**Exit:** repeatable non-prod deploy, reproducible plan, smoke checks and threat model.

## Days 31–60: reliability
Implement GitOps, canary gates, worker drain/rollback, safe migration workflow, queue-based autoscaling and warm capacity. Add SLO dashboards, alerts, runbooks and per-tenant dimensions. Run staged load tests and tune DB/cache.
**Exit:** rollback drill, measured scale-up, tested migration compatibility and p95 evidence.

## Days 61–90: tenant fleet and DR
Complete dedicated tenant template and reviewed onboarding under 30 minutes. Enforce EU policy for compute/data/backups/logs. Test restore and regional recovery; agree RPO/RTO. Run 15x load and failure-injection tests. Validate costs and security controls. Roll out shared → dedicated rings → regions.
**Exit:** SLO/cost review, restore/DR evidence, security sign-off and operations handover.
