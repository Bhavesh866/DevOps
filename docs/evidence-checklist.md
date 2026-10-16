# Evidence checklist

Only record evidence from real runs with timestamp, commit, environment, command and raw output; redact secrets.
"Synthetic" means the test ran against `tests/harness`, not the assignment application.

## Done

- [x] Terraform `fmt -check` / `init -backend=false` / `validate` — local and CI. No `plan`/`apply` run.
- [x] Kubernetes manifest render + client-side dry run (`scripts/validate-manifests.sh`) — local and CI.
- [x] CI image vulnerability gate (Trivy HIGH/CRITICAL) and config scan — GitHub Actions run on `40866de`.
- [x] Image SBOM and all-severity scan tied to one image ID — `docs/evidence/final/` (synthetic image).
- [x] Synthetic deploy/readiness, rolling update and rollback on kind — `docs/local-test-evidence.md` (no raw logs retained; pre-remediation image).

## Not done

- [ ] Image signature and SBOM attestation verified; same digest promoted across environments.
- [ ] Deployment/readiness with the real application image.
- [ ] 150 req/s baseline: p95, errors, resource and DB metrics.
- [ ] 2,250 req/s: scale-up under five minutes.
- [ ] Bad canary triggers automatic rollback.
- [ ] Worker drain with 60-second in-flight job; no dropped job.
- [ ] Migration compatibility and application rollback.
- [ ] Database restore with consistency/smoke checks.
- [ ] Tenant ring halts on failure.
- [ ] EU policy covers data, backups, logs and snapshots.
- [ ] Actual pricing calculator export.

The assignment asks for evidence of deployment under load, rollback, 15x load and restore.
None of those is complete for the real application; items above are updated as work lands.
