# Architecture

## Requirements and assumptions
The application is a black box: stateless API on port 8080 with `/healthz`, `/readyz`, `/metrics`; stateless worker consumes Redis jobs up to 60 seconds; PostgreSQL migrations run on startup and some are not backward-compatible. Load is 150 req/s baseline, 2,250 req/s peak and 20,000 jobs/hour. Targets: p95 <400ms, shared availability 99.9%, dedicated 99.95%, EU tenant data remains in EU. Budget envelopes: $9,000/month steady and $16,000/month peak.

Validate request mix, DB query profile, job duration distribution, queue delivery guarantees/idempotency, tenant isolation, RPO/RTO and whether startup migrations can be separated. Without these, capacity and cost remain hypotheses.

## Layered architecture
**Provider layer:** AWS Terraform provisions the network today (implemented, validated, never applied); EKS, RDS PostgreSQL, ElastiCache Redis, ECR, KMS and Secrets Manager are designed but not yet coded. Local kind validates Kubernetes resources, but cannot prove cloud networking, managed-service HA, IAM or provider SLA. Keep provider-specific outputs behind explicit interfaces.

**Platform layer:** Kubernetes namespaces, service accounts, deployments, services, probes, autoscaling, PDBs, network policies, observability and release reconciliation. Use IRSA/workload identity on EKS. Use GitOps pull-based delivery to keep production cluster credentials out of CI.

**Application layer:** API and worker use immutable image digests and secret references. Readiness means able to serve; liveness checks process health. Worker must stop claiming jobs on SIGTERM, finish or safely release in-flight work, then exit. Queue delivery may be at-least-once: jobs must be idempotent or deduplicated.

**Data layer:** RDS PostgreSQL Multi-AZ, encryption, PITR, retention, connection pooling and tested restore. ElastiCache replication/failover and TLS/authentication should be configured according to selected engine/version and queue durability needs. Dedicated tenants get isolated stacks from the same template. EU compute, DB, cache, backups, logs and snapshots stay in approved EU regions.

## Deployment
Build once; test, scan dependencies/image, generate SBOM, sign and publish image; promote the exact digest through dev, staging and production. Do not rebuild between environments. Production config changes are reviewed and reconciled through GitOps.

API canary: 5%, 25%, 50%, 100%, with at least 10 minutes per step or longer if traffic volume is insufficient. Gate on p95 <400ms, 5xx rate relative to baseline, readiness, saturation and smoke checks. Roll back if error rate materially exceeds baseline, p95 breaches the SLO for two consecutive windows, or critical health checks fail. Calibrate thresholds using baseline noise.

Worker: controlled rolling update, `maxUnavailable: 0`, modest `maxSurge`, long enough termination grace period and application-supported drain. Gate on queue depth/age, job failure rate, completion latency and duplicate/lost-job checks. Mixed worker versions require backward-compatible message formats.

Rollout order: shared platform first, dedicated tenants in small rings, then regions; halt the fleet after a failed ring. Never route EU tenant data to non-EU resources.

## Zero downtime and migrations
A Kubernetes rollback does not reverse a database schema change. Use expand/contract: add compatible schema, deploy code supporting old and new schema, backfill in bounded batches, switch reads/writes, verify, then contract only after old code and rollback window are gone. If a migration is inherently breaking, use a coordinated compatibility/maintenance plan; do not claim zero downtime by default. Confirm whether startup migrations can be disabled or safely serialized.

## Autoscaling and capacity
Scale API on CPU plus request/concurrency metrics; CPU alone can miss saturation. Scale workers on queue depth and oldest-message age, not CPU alone. HPA scales pods; Cluster Autoscaler/Karpenter adds nodes. Keep warm headroom because cold node provisioning, image pulls and DB warm-up can exceed five minutes.

API replicas = `ceil(2250 / measured sustainable req/s per pod)` plus N+1 and rollout headroom. DB connection budget = `API replicas × API pool size + worker connections + migrations + admin reserve`; keep below DB limit with reserve. Consider PgBouncer/RDS Proxy only after compatibility testing.

20,000 jobs/hour averages 5.56 jobs/sec. At 60 seconds/job, conservative concurrency is about 334 slots; 1.5x planning factor gives about 501 worker slots. Actual requirement depends on duration distribution and job parallelism; benchmark it.

## Portability limits
Portable: Kubernetes workloads, Kustomize, container images, probes, PDBs, metrics and rollout concepts. Not fully portable: VPC/VPC endpoints, IAM/IRSA, EKS add-ons, ECR, RDS, ElastiCache, KMS, Secrets Manager, load balancers, storage classes, autoscaler integration, managed-service failover, DNS/certificates, service availability and pricing.

## SLOs and operations
99.9% permits ~43.8 minutes downtime per 30-day month; 99.95% permits ~21.6 minutes. Define SLIs from externally observed successful requests and latency, not pod health alone. Alert on error-budget burn, p95/5xx, saturation, queue age/depth, job failures, DB connections/storage/replication, Redis memory/evictions/failover and backup failures. Dashboards and logs must preserve tenant boundaries.

Backups require encrypted DB backups/PITR, defined retention, a Redis durability decision, and recurring restore drills in isolated environments. A backup is not proven until restore and consistency checks pass.

## Top five risks
1. Non-backward-compatible startup migrations undermine zero-downtime deployment and rollback.
2. Unknown application performance makes 15x scaling and cost unproven.
3. DB connection exhaustion/slow queries dominate latency despite pod scaling.
4. Queue semantics and 60-second jobs create duplicate/lost-work risks during termination.
5. Multi-cloud parity, EU residency and dedicated isolation may exceed budget or cause drift.
