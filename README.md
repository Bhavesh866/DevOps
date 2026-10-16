# Continuity platform — cloud-agnostic, zero-downtime deployment

ImmverseAI DevOps assessment. The application is a black box that was not supplied, so a
synthetic stand-in (`tests/harness`) implements its contract (API on :8080 with
`/healthz` `/readyz` `/metrics`, Redis-queue worker with jobs up to 60 s) to exercise the platform.

**What is real:** every evidence log was produced on a local kind cluster (the second target).
**What is not:** nothing was applied to a cloud account. AWS and GCP Terraform is validated
but never planned. Full ledger: [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

## Evidence (kind, synthetic app) — [`docs/evidence/README.md`](docs/evidence/README.md)

| Required evidence | Result |
|---|---|
| Deploy under load, no errors | canary 25 → 50 → 100 % at 300 req/s: 90,001 requests, **0 failed** |
| Automatic rollback of a bad release | 30 %-failing release **aborted by metric analysis in 42 s** |
| 15x load test | 150 → 2,250 req/s held 5 min: 800,998 requests, **0 failed**, p95 6 ms; HPA and KEDA up and back, 2,807 jobs, **0 lost** |
| Restore test | 500k rows destroyed and restored, **checksums identical** |
| Also | worker drain + force-kill recovery (0 lost jobs); expand/contract migration with app rollback |

## Documents

- [`docs/architecture.md`](docs/architecture.md) — architecture (diagram, flows, scaling maths, 9 decisions, top 5 risks)
- [`docs/change-request-us-west.md`](docs/change-request-us-west.md) — CR-001 addendum: dedicated tenant on GCP, US-West + US-East failover
- [`docs/runbooks.md`](docs/runbooks.md) · [`docs/cost-model.md`](docs/cost-model.md) · [`docs/roadmap-90-days.md`](docs/roadmap-90-days.md)

## Layout

| Path | Layer | Contents |
|---|---|---|
| `infra/bootstrap` | provider | state bucket (versioned, KMS) and GitHub OIDC roles |
| `infra/providers/aws` | provider | VPC, EKS, RDS PostgreSQL, ElastiCache, KMS, Secrets Manager, ECR |
| `infra/providers/gcp` | provider | CR-001 skeleton: GKE ×2 regions, Cloud SQL + cross-region replica, Memorystore |
| `infra/live/<stack>` | provider | rendered per-stack tfvars and state backend (generated) |
| `tenants/*.yaml` | fleet | one file per stack: the single reviewed change for onboarding |
| `platform/base`, `platform/overlays`, `platform/tenants` | app | API/worker manifests, per-target and per-tenant overlays (generated) |
| `platform/observability` | platform | Prometheus config and SLO/burn-rate rules |
| `tests/harness` | test | stand-in app, kind manifests (Argo Rollouts canary, HPA, KEDA, Redis, Postgres) |
| `tests/load` | test | k6 profiles |
| `scripts/` | all | add-ons, tenant tool, evidence scripts, CI helpers, validators |
| `.github/workflows` | pipeline | `ci.yml` (build once → sign → promote by digest, ring rollout), `drift.yml` |

## Reproduce

```bash
# Prerequisites: docker, kind, kubectl, python3 (+ pyyaml), terraform >= 1.10
bash scripts/evidence/run-all.sh                   # kind cluster, add-ons, all evidence (~35 min)

python3 scripts/tenant.py check                    # tenant policy + rendered stacks up to date
bash scripts/validate-manifests.sh                 # render every overlay
terraform -chdir=infra/providers/aws init -backend=false && terraform -chdir=infra/providers/aws validate
bash scripts/generate-image-evidence.sh            # image scan + SBOM for one image ID
```

## Onboarding a tenant

1. Add `tenants/<name>.yaml` (tier, cloud, region, residency, ring, CIDR, sizing).
2. `python3 scripts/tenant.py render` and commit the generated `infra/live/<name>` and `platform/tenants/<name>`.
3. Open a PR: CI rejects residency/region mismatches, overlapping CIDRs, undersized stacks or stale renders.
4. After review and merge, apply `infra/live/<name>` and let GitOps sync the overlay; the tenant joins its ring.
