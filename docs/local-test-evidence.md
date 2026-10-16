# Local Kubernetes Test Evidence

Date: 2026-10-16
Environment: WSL2, Docker, kind, Kubernetes
Cluster: continuity (one control-plane node and two worker nodes)

## Completed and observed

| Test | Result | Evidence |
|---|---|---|
| Terraform formatting and validation | Passed | Earlier terminal output |
| Local Kubernetes cluster | Passed | Three nodes reported Ready |
| Manifest client-side dry run | Passed | Eight resources accepted |
| Synthetic API deployment | Passed | Two replicas became Ready |
| Synthetic worker process deployment | Passed | One process Running |
| Synthetic API health endpoint | Passed | GET /healthz returned HTTP 200 |
| Synthetic API readiness endpoint | Passed | GET /readyz returned HTTP 200 |
| Synthetic metrics endpoint | Passed | GET /metrics returned HTTP 200 |
| Rolling update to synthetic-v2 | Passed | Rollout completed and version endpoint returned synthetic-v2 |
| Rollback to synthetic-v1 | Passed | Rollout completed and version endpoint returned synthetic-v1 |
| Post-rollback readiness | Passed | Two replicas available; two service endpoints |

## Scope and limitations

The synthetic API and worker are test harnesses, not the assignment's actual application.
The worker does not consume Redis jobs.
No real PostgreSQL database, startup migration, or migration rollback was tested.
No 15x load test, autoscaling test, zero-downtime-under-load test, backup restore,
or cloud deployment was performed.
No AWS resources were provisioned.

Terraform validation does not mean the AWS infrastructure was deployed.
The current AWS Terraform configuration is incomplete and must not be described
as a fully deployable production platform.

The synthetic rollout test verifies Kubernetes Deployment revision behavior only.
It does not prove application compatibility, database safety, or the 99.9%/99.95%
availability objectives.
