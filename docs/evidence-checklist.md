# Evidence checklist

Only record evidence from real runs with timestamp, commit, environment, command and raw output; redact secrets.
- [ ] Terraform fmt/validate/plan (do not imply apply unless run).
- [ ] CI checks, SBOM, image scan and signature verification.
- [ ] Deployment/readiness with real application image.
- [ ] 150 req/s baseline: p95, errors, resource and DB metrics.
- [ ] 2,250 req/s: scale-up under five minutes.
- [ ] Bad canary triggers automatic rollback.
- [ ] Worker drain with 60-second in-flight job; no dropped job.
- [ ] Migration compatibility and application rollback.
- [ ] Database restore with consistency/smoke checks.
- [ ] Tenant ring halts on failure.
- [ ] EU policy covers data, backups, logs and snapshots.
- [ ] Actual pricing calculator export.
The assignment requires evidence for deployment under load, rollback, 15x load and restore. None is claimed complete by this repository.
