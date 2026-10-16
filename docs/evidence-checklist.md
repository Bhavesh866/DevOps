# Evidence checklist

"kind" = local cluster with the synthetic stand-in app. Details and limits per item:
`docs/evidence/README.md`.

## Required by the assignment

- [x] Deploy under load with no errors — kind: `canary-under-load.log` (90,001 requests, 0 failed)
- [x] Automatic rollback of a bad release — kind: `canary-auto-rollback.log` (aborted after 42 s)
- [x] 15x load test — kind: `autoscale-15x.log` (2,250 req/s held 5 min, 0 failed, scale up and back)
- [x] Restore test — kind: `restore-test.log` (checksums identical)

## Additional

- [x] Worker drain and orphan recovery, no lost jobs — `worker-drain.log`
- [x] Expand/contract migration with app rollback — `migration-expand-contract.log`
- [x] Image scan (all severities) and SBOM tied to one image ID — `docs/evidence/final/`
- [x] Terraform fmt/validate (AWS, GCP, bootstrap), manifest render, tenant policy, promtool, Trivy config — local; CI on push
- [x] SLO rules loaded and healthy in a running Prometheus — kind
- [x] CI push → sign → verify → promote by digest — GitHub Actions run 38926195267, all 8 jobs green (prod rings render overlays; no prod cluster)
- [x] Ring rollout halts on failure — run 38924053824: ring 0 failed, rings 1–2 cancelled (unintended failure from a since-fixed bug)
- [ ] Deliberate halt demo — `workflow_dispatch` with `fail_ring=1` (ring 0 passes, ring 1 fails, ring 2 cancelled)
- [ ] Any cloud deployment (AWS/GCP plan or apply)
- [ ] Real application image: capacity, p95, drain, migrations
- [ ] RDS PITR restore, Redis failover, regional failover game day
- [ ] Tenant onboarding timed end to end
- [ ] Pricing calculator export
