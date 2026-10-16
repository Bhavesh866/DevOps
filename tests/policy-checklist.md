# Security and reliability gates

Automated where marked; the rest are review items for a production change.

- [x] Image scanned (Trivy, HIGH/CRITICAL with fix fails) — CI `build`
- [x] Image signed (cosign keyless) and SBOM attested; every deploy verifies — CI `scripts/ci/verify-image.sh`
- [x] Production overlays pinned by digest — CI `promote-production`
- [x] Non-root, read-only root FS, dropped capabilities, no privilege escalation — all manifests; Trivy config scan in CI
- [x] Restricted Pod Security on the app namespace; default-deny NetworkPolicies — `platform/base`
- [x] No plaintext secrets in git: Secrets Manager + External Secrets; RDS admin password managed by RDS
- [x] EU residency policy: tenant validation + Terraform precondition — CI `tenant.py check`
- [x] No public database or cache endpoints — `publicly_accessible = false`, private subnets, SG from nodes only
- [ ] Admission control enforcing signed images in-cluster (policy-controller/Kyverno) — roadmap
- [ ] HPA targets from measured real-app capacity — needs the real image
- [ ] Real worker drain and idempotency verified — needs the real image
- [ ] `terraform plan` reviewed in a real account
