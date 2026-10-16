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
