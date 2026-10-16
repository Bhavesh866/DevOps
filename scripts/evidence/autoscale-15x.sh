#!/usr/bin/env bash
# Evidence: API scales for 150 -> 2,250 req/s (15x) and back; workers scale on
# outstanding jobs at 20,000 jobs/hour and back without losing jobs.
# Synthetic harness on kind (one machine), see limitations in docs/evidence/README.md.
# Usage: bash scripts/evidence/autoscale-15x.sh | tee docs/evidence/autoscale-15x.log
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "== $(ts) setup: commit $(git rev-parse --short HEAD), image $(docker image inspect continuity-harness:local --format '{{.Id}}')"
echo "   load: k6 peak15x = 150 rps 60s -> ramp to 2,250 rps over 60s -> hold 5m -> 150 rps"
echo "   jobs: 5.56 jobs/s (20,000/hour); durations 3-9s, scaled down 10x from 5-60s so the"
echo "         worker pod count fits one laptop. Mechanism is the same; absolute counts are not."
kubectl -n "$NS" exec deploy/redis -- redis-cli FLUSHDB >/dev/null
kubectl -n "$NS" set env deploy/synthetic-producer JOBS_PER_SECOND=5.56 JOB_SECONDS_MIN=3 JOB_SECONDS_MAX=9 >/dev/null
kubectl -n "$NS" scale deploy/synthetic-producer --replicas=1 >/dev/null

PROFILE=peak15x bash scripts/run-k6.sh k6-peak15x
start=$(date +%s)
sample_header
while ! kubectl -n "$NS" get job k6-peak15x -o jsonpath='{.status.conditions[*].type}' | grep -qE 'Complete|Failed'; do
  sample
  sleep 10
done
echo "-- $(ts) k6 finished after $(( $(date +%s) - start ))s; stopping producer"
kubectl -n "$NS" scale deploy/synthetic-producer --replicas=0 >/dev/null

echo "-- $(ts) waiting for scale-in (api -> 4, workers -> 2)"
for _ in $(seq 40); do
  sample
  api=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.availableReplicas}')
  wk=$(kubectl -n "$NS" get deploy synthetic-worker -o jsonpath='{.status.replicas}')
  [ "$api" -le 4 ] && [ "$wk" -le 2 ] && break
  sleep 15
done

echo
echo "== $(ts) k6 summary"
k6_summary k6-peak15x
echo
echo "== $(ts) job audit after scale-in"
NS=$NS bash scripts/queue-audit.sh
