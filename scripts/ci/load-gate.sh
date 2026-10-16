#!/usr/bin/env bash
# Promotion gate on measured behaviour: k6 at baseline load against the freshly
# deployed digest. k6 thresholds (p95 < 400 ms, failed < 0.1%) decide pass/fail.
set -euo pipefail
source scripts/evidence/lib.sh
PROFILE=steady RATE="${RATE:-150}" DURATION="${DURATION:-60s}" bash scripts/run-k6.sh k6-gate
k6_wait k6-gate
summary=$(kubectl -n "$NS" logs job/k6-gate | grep K6_SUMMARY | sed 's/^K6_SUMMARY //')
echo "$summary"
echo "### Load gate: \`$summary\`" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "$summary" | python3 -c 'import json,sys; s=json.load(sys.stdin); sys.exit(0 if s["thresholds_passed"] else 1)'
