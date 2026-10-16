# Implementation status and evidence ledger

## Implemented in the repository

- Architecture and decision records, top risks, cost envelope, and 90-day roadmap.
- Kubernetes API/worker Deployment, Service, HPA, and PDB templates.
- kind configuration and Kustomize overlays.
- AWS Terraform starter for VPC/subnets.
- GitHub Actions example for Terraform, manifest, and Trivy validation.
- Capacity calculator and evidence checklist.
- Separate synthetic API/worker-process harness and isolated Kubernetes demo manifests.
- Local test evidence report in `docs/local-test-evidence.md`.

## Executed and observed

- Terraform formatting check passed.
- `terraform init -backend=false` succeeded.
- `terraform validate` succeeded for the current Terraform starter.
- Original local Kustomize overlay rendered.
- Client-side dry-run accepted the original rendered Kubernetes resources.
- Three-node kind cluster created; all nodes reported Ready.
- Synthetic API deployed with two Ready replicas.
- Synthetic worker process deployed and Running.
- Synthetic `/healthz`, `/readyz`, `/metrics`, and `/` endpoints returned HTTP 200.
- Synthetic rolling update from `synthetic-v1` to `synthetic-v2` completed.
- Synthetic rollback to `synthetic-v1` completed.
- After rollback, `/` returned HTTP 200 with `synthetic-v1`; two API replicas were available and registered as Service endpoints.

## Not executed or not proven

- No AWS account provisioning or Terraform apply.
- AWS Terraform is incomplete and currently only establishes a VPC/subnet foundation; it is not a deployable end-to-end platform.
- No actual assignment application source/image was available.
- The synthetic worker does not connect to Redis or process jobs.
- No real PostgreSQL instance, startup migration, migration rollback, or schema compatibility test.
- No 15x load test, measured autoscaling test, or proof of p95 below 400 ms.
- No zero-downtime-under-load test.
- No image signing, SBOM attestation, digest-based promotion, or metric-gated production rollout was demonstrated end to end.
- No backup restore, regional failover, or tenant residency test.
- No real provider pricing query; costs are planning estimates, not a quote.
- No SLO or availability target has been proven.

## Required before production

1. Obtain the real application image and document its API, worker, probe, and shutdown contracts.
2. Configure encrypted remote Terraform state, locking, recovery, and drift detection.
3. Complete private networking, routes, egress, endpoints, IAM/IRSA, EKS, RDS, ElastiCache, ECR, KMS, Secrets Manager, and observability.
4. Validate the database connection budget, queue semantics, idempotency, retry/dead-letter behavior, and graceful worker drain.
5. Serialize migrations where required; use expand/contract and test rollback/forward recovery.
6. Implement build-once CI/CD with scanning, SBOM, signing, digest promotion, and metric-based gates.
7. Run representative load, autoscaling, rollback, worker-drain, backup-restore, regional failover, and residency tests; retain raw evidence.
8. Complete the requested second dedicated stack on another cloud in US-West with US-East failover and the one-page change-request addendum.
