# Decisions and rejected alternatives

1. **Kubernetes + kind/EKS.** Shared deployment contract across local and AWS. Rejected separate ECS and Kubernetes definitions for app portability. Trade-off: Kubernetes complexity and provider-specific ingress/autoscaling remain.
2. **Terraform provider roots.** Keep AWS network/IAM/managed services separate from app manifests. Rejected claiming a single generic module makes managed services portable. Trade-off: provider-specific code/tests.
3. **GitOps pull for production.** CI builds/scans/signs; reviewed config promotes digest; cluster reconciles. Rejected direct pipeline push due to credential blast radius. Trade-off: GitOps controller operations.
4. **API canary, worker controlled rolling.** Canary limits API exposure; worker drain protects in-flight jobs. Rejected blind rolling for API and blue/green everywhere due to capacity cost and queue/schema complexity.
5. **Expand/contract migrations.** Add schema, deploy compatible code, backfill, switch, contract later. Rejected destructive startup migrations because mixed-version replicas can fail. Trade-off: longer process and temporary schema complexity.
6. **Queue-based worker scaling.** Use depth and oldest-message age. Rejected CPU-only HPA as lagging signal. Requires KEDA/custom metrics.
7. **Managed AWS data services.** RDS and ElastiCache reduce patching/recovery burden. Rejected self-managed DB/cache on Kubernetes for production. Trade-off: cost and lock-in.
8. **Explicit EU region policy.** Policy gates region and covers backups/logs/snapshots. Rejected manual naming conventions. Trade-off: regional duplication and operational complexity.
