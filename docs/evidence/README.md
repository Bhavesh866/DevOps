# Evidence index

All image evidence is for the **synthetic test harness** (`tests/harness`), not the assignment application.
Historical files are kept for traceability; only `final/` describes the current image.

## Current (post-remediation) — `final/`

Regenerate with `bash scripts/generate-image-evidence.sh`. The script builds once and runs every
scan against that one local image ID, which is recorded in `final/provenance.txt`.

| File | Content |
|---|---|
| `final/provenance.txt` | Image ID, UTC timestamp, git commit, Trivy version |
| `final/trivy-all-severities.json` | Full Trivy vulnerability report, all severities, unfixed included |
| `final/trivy-gate-high-critical.txt` | The CI gate: HIGH/CRITICAL with available fix, `--exit-code 1` |
| `final/sbom.cdx.json` | CycloneDX SBOM of the same image ID |

Result at generation time: 0 findings at any severity. This is a point-in-time result against the
Trivy DB of that day; new CVEs will appear over time, which is why CI rescans on every build.

## Platform behaviour tests (kind, synthetic harness)

Environment: kind v1.37 cluster `continuity` (1 control plane + 2 workers) on one WSL2 machine
(16 vCPU, 7 GB). Add-ons from `scripts/platform-addons.sh`. All logs reproducible with
`bash scripts/evidence/run-all.sh`. Each log header records the git commit and image ID; the
commit shown is the last commit *before* these changes (the scripts were uncommitted at run time).

| File | Assignment item | Result | Does not show |
|---|---|---|---|
| `autoscale-15x.log` | 15x load test; autoscale up and back; queue-depth worker scaling without dropping jobs | k6 150 → 2,250 req/s (ramp 60 s, hold 5 min): **800,998 requests, 0 failed, 0 dropped, p95 6 ms**. API HPA 4 → 8 pods, peak served ~36 s after the ramp reached 2,250, back to 4 pods within about a minute of the load returning to baseline. Jobs at 20,000/h: KEDA 2 → 60 → ~38 → 2 workers; **2,807 jobs, lost=0, duplicates=0**. | Real app capacity (harness does ~5 ms of work, so 15x traffic needed only 2x pods); node provisioning (nodes pre-existed); job durations scaled 10x down (3–9 s). |
| `autoscale-15x-attempt1-generator-limited.log` | (history) | First attempt: k6 opened a new TCP connection per request and exhausted its own ports — 298,521 dropped iterations, peak ~1,800 req/s, 0 server errors. Fixed by connection reuse + server-side `Connection: close` every 100 requests (rebalances after scale-out). Kept for transparency. | — |
| `canary-under-load.log` | Deploy under load with no errors | Release v1 → v3 at constant 300 req/s through canary steps 25 % → 50 % → 100 %: **90,001 requests, 0 failed**; analysis 10/10 successful on both metrics (canary 5xx ratio, canary p95). | Exact traffic percentages (no traffic router on kind: weight = replica ratio). |
| `canary-auto-rollback.log` | Automatic rollback of a bad release | Release with 30 % failing requests at 300 req/s: canary 5xx ratio measured 0.27–0.28 vs. limit 0.01 → **rollout aborted automatically 42 s after release**, stable served 100 % again ~15 s later. Blast radius over the 4-min window: 1,104 of 72,001 requests failed (1.5 %), all from the canary before abort. k6 thresholds fail in this run by design. | Faster detection or smaller first step: on EKS a traffic router allows a 5 % first step. |
| `restore-test.log` | Restore test | 500,000-row database: `pg_dump` → pod (and data) destroyed → 0 tables → `pg_restore` → **row counts and content MD5 identical**, smoke query passes. Backup 1 s, restore 1 s. | RDS PITR/snapshot restore (managed-service path is in `docs/runbooks.md`, not run); restore time at production data size. |
| `migration-expand-contract.log` | Safe migrations, rollback after a migration | Naive rename breaks v1 immediately. Expand (additive columns + sync trigger + batched backfill) keeps v1 and v2 working together; **v1 still works after an app rollback** post-migration; contract drops `full_name` only in a later release. | The real app's migrations (SQL issued per app version is simulated with psql). |
| `worker-drain.log` | Worker draining | A: rolling update with 4 jobs in flight — every terminating worker finished its job, then exited; `lost=0`, `duplicates=0`. B: worker force-deleted mid-job — its job was requeued after heartbeat expiry and completed; `requeued_orphans=1`, `lost=0`. | Real job semantics or idempotency of the real worker; Redis failure (Redis here is a single ephemeral pod). |

**Defect found and fixed during these runs:** the first canary attempt's error-rate query returned an
empty vector when there were zero 5xx responses, every measurement errored, and Argo aborted the
release after 5 consecutive errors. The gate failed closed (safe), but would have blocked every good
release. Fixed with `or vector(0)` in `tests/harness/k8s/api-rollout.yaml`.

## Historical (pre-remediation) — do not cite as current

| File | Image ID | Scanned (UTC) | Findings | Note |
|---|---|---|---|---|
| `harness-image-trivy-before-remediation.json` | `sha256:677311ac…` | 2026-10-16 08:53 | 4 HIGH, 3 MEDIUM | Base image still shipped pip and its vendored msgpack/setuptools/urllib3. This image (tag `v1`) was used for the first kind rollout/rollback test. |
| `harness-image-trivy.json` | `sha256:c8b64dde…` | 2026-10-16 09:52 | 4 HIGH, 3 MEDIUM | Same findings; pip still present. |
| `harness-image-trivy-detailed.json` | `sha256:c8b64dde…` | 2026-10-16 09:59 | 4 HIGH, 3 MEDIUM | Duplicate scan of the previous image. |
| `harness-image-sbom.json` | not recorded (tag `continuity-harness:ci`) | 2026-10-16 09:58 | 49 components incl. pip | SBOM of the pre-remediation image. |
| `harness-image-trivy-final.json` | `sha256:7fb2ece7…` | 2026-10-16 11:02 | 0 HIGH/CRITICAL | After pip removal. Filtered to HIGH/CRITICAL; an all-severity rescan found MEDIUM zlib CVE-2026-85091, fixed by adding `apk upgrade` to the Dockerfile. Superseded by `final/`. |

## Remediation history

1. pip removed from the runtime image: cleared the 4 HIGH findings in pip-vendored Python packages.
2. `apk upgrade --no-cache` at build time: cleared MEDIUM zlib CVE-2026-85091 (1.3.2-r0 → 1.3.2-r1).

Trade-off of step 2: the build picks up whatever Alpine publishes on build day, so two builds of the
same commit can differ. That is acceptable only because the pipeline builds once and promotes the
resulting digest; it would not be acceptable if environments rebuilt independently.
