# Implementation status — built vs. described

**[run]** executed, evidence in `docs/evidence/` · **[code]** in the repo and validated
(terraform validate / render / promtool / CI) but never applied to a cloud · **[design]** described
only · **[gap]** not addressed. "kind" = local cluster with the synthetic stand-in app
(`tests/harness`); the real application image is a black box that was not supplied.

## Items to cover (assignment PDF)

| Item | Status | Where / evidence |
|---|---|---|
| Provider layer separate from platform and app | [code] | `infra/providers/{aws,gcp}` same output interface; `platform/`; `platform/base` |
| AWS: network, EKS, RDS, ElastiCache, KMS, Secrets Manager, ECR | [code] | `infra/providers/aws/*.tf` — validated, **never planned or applied** (no account) |
| Two targets | [run] kind · [code] AWS | kind end to end; AWS validate only |
| What is not portable | [design] | `docs/architecture.md` §3 |
| Empty account → platform, no console steps | [code] | `infra/bootstrap` → `infra/live/<stack>` → `scripts/platform-addons.sh`; remaining manual: account creation, GitHub environment reviewers |
| Remote state | [code] | `infra/bootstrap` (S3 versioned, KMS, TLS-only), `backend.tf` (native lockfile) |
| Drift detection | [code] | `.github/workflows/drift.yml` — skipped until `AWS_DRIFT_ROLE_ARN` is set; **never run** |
| Secrets manager | [code] | Secrets Manager + External Secrets (IRSA), `platform/base/secrets.yaml`; RDS admin password managed by RDS |
| Build once, scan, sign, promote by digest dev → staging → prod | [run] GitHub Actions | `.github/workflows/ci.yml` — [run 38926195267](https://github.com/Bhavesh866/DevOps/actions/runs/38926195267) (commit `c7d5564`): build → Trivy → SBOM → cosign sign/attest → dev (verify, kind deploy, k6 gate) → staging tag → rings 0 → 1 → 2, all green. Production rings render digest-pinned GitOps overlays only; no production cluster exists |
| Gates based on real metrics | [run] kind · [code] CI | Canary analysis on Prometheus (`canary-*.log`); CI k6 gate `scripts/ci/load-gate.sh` |
| API strategy, steps, gate metrics, automatic rollback | [run] | `tests/harness/k8s/api-rollout.yaml`; `canary-under-load.log`, `canary-auto-rollback.log` |
| Worker strategy | [run] | rolling + drain: `worker-drain.log` |
| GitOps vs push; rollout order shared → rings → regions | [code] / [design] | ring matrix with halt in `ci.yml` (`fail_ring` input demonstrates halt); Argo CD itself not installed |
| Graceful shutdown, probes, PDBs | [run] | preStop + drain in harness; 0 failed requests through canary under load |
| Worker draining | [run] | `worker-drain.log` (graceful and force-kill, `lost=0`) |
| Expand/contract, rollback after a migration | [run] (SQL level) | `migration-expand-contract.log` — SQL issued by each app version, not the real app |
| 15x in < 5 min and back, no dropped jobs, queue depth | [run] | `autoscale-15x.log` — see its limits in `docs/evidence/README.md` |
| Capacity maths and DB limits | [design] | `docs/architecture.md` §6, `scripts/capacity-model.py` |
| One shared + dedicated stacks from one template | [code] | `tenants/*.yaml` → `scripts/tenant.py` → `infra/live/*`, `platform/tenants/*`; checked in CI |
| New tenant < 30 min by one reviewed change | [code] / [design] | one-file PR, CI `tenant.py check`; **onboarding time not measured** |
| Fleet rollout with halt on failure | [run] GitHub Actions | `promote-production` matrix (`max-parallel: 1`, `fail-fast`). [Run 38924053824](https://github.com/Bhavesh866/DevOps/actions/runs/38924053824): ring 0 failed, rings 1 and 2 cancelled before running. The failure was unintended (the `fail_ring` null-coercion bug fixed in `c7d5564`), but the halt behaviour is real. A deliberate `workflow_dispatch` with `fail_ring=1` has not been run |
| EU data never leaves the EU | [code] | `tenant.py` region allowlist, Terraform precondition, in-region backups, EU state bucket |
| SLOs and alerts | [run] rules loaded on kind · [code] | `platform/observability/slo-rules.yaml` (promtool-checked, healthy in kind Prometheus); no Alertmanager routing |
| Per-tenant visibility | [run] | `tenant`/`tier` labels on all series; SLO rules grouped by tenant |
| Runbooks | [design] | `docs/runbooks.md` |
| Backups and restore test | [run] kind · [code] RDS PITR | `restore-test.log` (pg_dump/pg_restore, checksum match); RDS restore not run |
| Cost estimate, 90-day roadmap | [design] | `docs/cost-model.md` (no calculator export), `docs/roadmap-90-days.md` |

## Deliverables

| Deliverable | Status |
|---|---|
| Repository with README, IaC, pipelines, scripts | done |
| Architecture document ≤ 5 pages: diagram, ≥ 5 decisions, top 5 risks | `docs/architecture.md` (Mermaid diagram, 9 decisions, 5 risks) |
| Evidence: deploy under load, automatic rollback, 15x, restore | [run] on kind — `docs/evidence/README.md` |
| Change request one-page addendum | `docs/change-request-us-west.md`; GCP root `infra/providers/gcp` [code, skeleton] |

## Known gaps (stated, not hidden)

- Nothing has been applied to AWS or GCP; cloud-specific behaviour (IAM, ALB, node provisioning
  time, RDS failover, ElastiCache failover) is unverified.
- The real application was not available: capacity per pod, DB time, drain support and
  migration behaviour of the real app are assumptions listed in architecture §1.
- CI supply-chain stages run green on GitHub Actions, but "production" there means rendering
  digest-pinned overlays per ring; nothing is synced to a real production cluster.
- Argo CD (GitOps controller), Alertmanager, Cluster Autoscaler/Karpenter and External Secrets
  Operator are designed into the platform but not installed on kind.
- Redis queue durability across a Redis failover is not tested; CR-001 cross-region job loss is open.
