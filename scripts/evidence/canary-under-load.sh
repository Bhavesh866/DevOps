#!/usr/bin/env bash
# Evidence: a good release progresses through canary steps 25% -> 50% -> 100%
# under constant load with zero failed requests; the analysis gate passes.
# Usage: bash scripts/evidence/canary-under-load.sh | tee docs/evidence/canary-under-load.log
set -euo pipefail
source "$(dirname "$0")/lib.sh"

RATE="${RATE:-300}"
NEW_VERSION="${NEW_VERSION:-synthetic-v2}"
if [ "$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.phase}')" != Healthy ]; then
  echo "rollout is not Healthy; finish or abort the current release first"; exit 1
fi
echo "== $(ts) setup: commit $(git rev-parse --short HEAD), image $(docker image inspect continuity-harness:local --format '{{.Id}}')"
echo "   current release: $(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.spec.template.spec.containers[0].env[1].value}'); new release: $NEW_VERSION"
echo "   load: constant $RATE req/s (2x baseline) for the whole rollout"

PROFILE=steady RATE="$RATE" DURATION=5m bash scripts/run-k6.sh k6-canary-good
sleep 30
echo "-- $(ts) releasing $NEW_VERSION"
set_release "$NEW_VERSION" 0
rollout_header
while ! kubectl -n "$NS" get job k6-canary-good -o jsonpath='{.status.conditions[*].type}' | grep -qE 'Complete|Failed'; do
  rollout_sample
  sleep 10
done
rollout_sample

echo
echo "== $(ts) canary analysis"
analysis_report
echo
echo "== $(ts) k6 summary (failed_requests must be 0)"
summary=$(k6_summary k6-canary-good)
echo "$summary"
phase=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.phase}')
failed=$(echo "$summary" | python3 -c 'import json,sys; print(json.load(sys.stdin)["failed_requests"])')
if [ "$phase" = Healthy ] && [ "$failed" = 0 ]; then
  echo "== RESULT: PASS — rollout Healthy on $NEW_VERSION, 0 failed requests during the rollout"
else
  echo "== RESULT: FAIL — phase=$phase failed_requests=$failed"; exit 1
fi
