# ImmverseAI Senior DevOps Assignment

**Status: partially implemented; see `docs/IMPLEMENTATION_STATUS.md`.**

AWS is the intended cloud target, and kind is the local Kubernetes validation target. The assignment's actual API/worker source and image were not available in the working directory. A separate synthetic harness was created for local Kubernetes deployment, endpoint, rolling-update, and rollback demonstrations. It is not the actual assignment application.

## Assignment targets

- API on port 8080 with `/healthz`, `/readyz`, and `/metrics`.
- Stateless worker consumes Redis jobs of up to 60 seconds.
- PostgreSQL migrations may be non-backward-compatible.
- 150 requests/second baseline; 2,250 requests/second peak.
- 20,000 jobs/hour; p95 latency below 400 ms.
- Availability targets: 99.9% shared and 99.95% dedicated.
- EU tenant data must remain in the EU.
- Budget envelope: $9,000/month steady state and $16,000/month peak.

These are assignment requirements, not demonstrated production results.

## Repository layout

- `infra/providers/aws`: Terraform network foundation (VPC, subnets, IGW, per-AZ NAT, routes); no compute or data services yet.
- `platform/base`: Kubernetes API/worker templates, probes, PDBs, and HPA.
- `platform/overlays/local`: kind configuration and local Kustomize overlay.
- `.github/workflows/ci.yml`: CI that validates Terraform/manifests and gates the harness image on a Trivy scan.
- `scripts`: manifest/network validation, image evidence generation, and a first-order capacity model.
- `tests/harness`: synthetic HTTP API and worker process used for local demonstrations.
- `tests/harness/k8s`: isolated Kubernetes manifests for the synthetic demonstration.
- `docs`: architecture, decisions, cost model, roadmap, evidence checklist, and test evidence.
- `docs/evidence`: scan/SBOM evidence; see `docs/evidence/README.md` for which files are current.

## Local validation performed

Environment: WSL2, Docker, kind, and Kubernetes.

Observed results:
- A three-node kind cluster was created; all nodes reported `Ready`.
- Terraform formatting, initialization without backend, and validation succeeded for the current Terraform starter. No AWS resources were provisioned.
- The original local Kustomize template rendered and passed a client-side dry run.
- The synthetic API was deployed with two replicas and the synthetic worker process with one replica.
- Synthetic `/healthz`, `/readyz`, `/metrics`, and `/` returned HTTP 200.
- A rolling update from `synthetic-v1` to `synthetic-v2` completed.
- A rollback to `synthetic-v1` completed; the version endpoint returned HTTP 200 and two API replicas were available.

These tests validate local Kubernetes mechanics and the synthetic harness only. They do not validate the actual application, real Redis job processing, PostgreSQL migrations, performance, or production availability.

For detailed evidence and limitations, see `docs/local-test-evidence.md` and `docs/IMPLEMENTATION_STATUS.md`.

## Original template workflow

The manifests under `platform/` are templates, not a production-ready deployment. Before using them with the real application:

1. Obtain the actual application image and contract.
2. Replace image placeholders and confirm supported probes, environment variables, and shutdown behavior.
3. Provision and configure PostgreSQL and Redis, including credentials and persistence/recovery settings.
4. Replace the template secret setup with the intended secret-management integration.
5. Validate the rendered manifests and run application-specific tests before deployment.

Do not apply the original templates expecting a complete application stack: the database, queue, actual image, and full cloud infrastructure are not provided.

## Intended design

Build once, scan, generate an SBOM, sign, publish, and promote the same image digest through dev/staging/production. Use a reviewed GitOps change for production. An API canary can progress from 5% to 25%, 50%, and 100%, gated by p95 latency, 5xx rate, readiness, and saturation. Worker rollout requires application-supported SIGTERM/draining and compatible message formats.

Roll out shared tenants first, then dedicated tenants in rings, then regions. EU tenant compute, data, backups, logs, and snapshots must remain in approved EU regions.

**Critical:** Kubernetes rollback does not undo a database migration. Use expand/contract migrations and do not claim zero downtime for a destructive migration without an explicit compatibility plan.

## Submission integrity

Clearly label unimplemented work and unexecuted tests. Do not present synthetic harness results as evidence for the actual application or claim that AWS infrastructure has been deployed.
