#!/usr/bin/env bash
# Evidence: a bad release (30% of requests fail) is detected by the canary
# analysis and aborted automatically; traffic returns to the stable version
# without human action. Then the bad change is reverted (the GitOps revert).
# Usage: bash scripts/evidence/canary-auto-rollback.sh | tee docs/evidence/canary-auto-rollback.log
set -euo pipefail
source "$(dirname "$0")/lib.sh"

RATE="${RATE:-300}"
STABLE=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.spec.template.spec.containers[0].env[1].value}')
BAD=synthetic-v3-bad
echo "== $(ts) setup: commit $(git rev-parse --short HEAD), image $(docker image inspect continuity-harness:local --format '{{.Id}}')"
echo "   stable release: $STABLE; bad release: $BAD with FAIL_RATE=0.3"
echo "   gate: canary 5xx ratio <= 1% (failureLimit 1) and canary p95 < 400 ms, every 15s"

PROFILE=steady RATE="$RATE" DURATION=4m bash scripts/run-k6.sh k6-canary-bad
sleep 30
released=$(date +%s)
echo "-- $(ts) releasing $BAD"
set_release "$BAD" 0.3
rollout_header
aborted=""
for _ in $(seq 30); do
  rollout_sample
  if [ "$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.abort}')" = true ]; then
    aborted=$(date +%s); echo "-- $(ts) rollout ABORTED automatically $((aborted - released))s after release"; break
  fi
  sleep 5
done
for _ in $(seq 6); do sleep 10; rollout_sample; done

echo
echo "== $(ts) canary analysis"
analysis_report
echo "   rollout message: $(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.message}')"

echo
echo "-- $(ts) reverting the release spec to $STABLE (what the GitOps revert commit does)"
set_release "$STABLE" 0
sleep 15
rollout_sample

k6_wait k6-canary-bad
echo
echo "== $(ts) k6 summary over the whole window (errors come only from the canary before abort;"
echo "   k6 thresholds fail here by design: they are the client-side view of the bad release)"
k6_summary k6-canary-bad
if [ -n "$aborted" ]; then
  echo "== RESULT: PASS — bad release aborted automatically after $((aborted - released))s; stable version kept serving"
else
  echo "== RESULT: FAIL — rollout was not aborted"; exit 1
fi
