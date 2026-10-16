# 90-day roadmap

**Starting point (this repository):** platform mechanics proven on kind with a synthetic app —
canary with automatic rollback, zero-error rollout under load, 15x HPA, queue-based worker scaling
with drain, restore and expand/contract tests. AWS and GCP provider code, tenant template and
pipeline are written and validated but have never run against a cloud account.

## Days 1–30: first real environment
- Obtain the real image and confirm its contract: drain on SIGTERM, idempotent jobs, queue key,
  migrate-only mode or advisory lock, per-pod DB pool size.
- Apply `infra/bootstrap`, then the shared stack in a non-production account; migrate bootstrap
  state into the bucket. Add Karpenter or Cluster Autoscaler, External Secrets store, Argo CD.
- First green end-to-end pipeline run against EKS (today the dev gate runs on kind in CI).
- Benchmark the real app: req/s per pod at p95 < 400 ms, DB time per request, job duration
  distribution. Replace the planning numbers in architecture §6 and the cost model.
- **Exit:** reproducible non-prod stack from an empty account; measured capacity; threat model.

## Days 31–60: reliability on the real app
- Repeat the kind evidence on EKS: canary auto-rollback, deploy under load, 15x including node
  provisioning time, worker drain with the real worker.
- Migration review gate in CI (lint for destructive DDL); first expand/contract release.
- RDS Proxy/PgBouncer compatibility test if the connection budget exceeds ~500.
- Alertmanager routing, on-call rotation, dashboards per tenant; nightly drift workflow enabled.
- **Exit:** p95 and availability SLIs measured for 30 days in staging; rollback drill passed.

## Days 61–90: fleet and DR
- Production shared stack (ring 0); first dedicated tenant through the tenant file workflow,
  timing the onboarding against the 30-minute target.
- Monthly restore drill automated; first quarterly regional game day for CR-001 (GCP) if approved.
- Policy as code: admission control requiring signed digests (Sigstore policy-controller/Kyverno).
- Cost review against the planning envelope with a pricing calculator export and 30 days of bills.
- **Exit:** SLO review, restore/DR evidence on the cloud, security sign-off, operations handover.
