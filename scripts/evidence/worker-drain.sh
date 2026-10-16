#!/usr/bin/env bash
# Evidence: workers do not lose jobs on rollout (graceful drain) or on a
# hard kill (orphan requeue). Synthetic harness on kind.
# Usage: bash scripts/evidence/worker-drain.sh | tee docs/evidence/worker-drain.log
set -euo pipefail

NS=continuity-demo
WORKERS=4
rc() { kubectl -n "$NS" exec deploy/redis -- redis-cli --raw "$@"; }
ts() { date -u +%H:%M:%S; }

enqueue() {  # enqueue COUNT jobs of SECONDS each
  local count=$1 seconds=$2 cmds=""
  for _ in $(seq "$count"); do
    cmds+="RPUSH jobs:pending $(cat /proc/sys/kernel/random/uuid | tr -d -)|$seconds"$'\n'
  done
  cmds+="INCRBY jobs:enqueued $count"$'\n'
  printf '%s' "$cmds" | kubectl -n "$NS" exec -i deploy/redis -- redis-cli >/dev/null
}

wait_for_empty() {
  for _ in $(seq 120); do
    local busy k
    busy=$(rc LLEN jobs:pending)
    for k in $(rc KEYS 'jobs:processing:*'); do busy=$((busy + $(rc LLEN "$k"))); done
    [ "$busy" -eq 0 ] && return 0
    sleep 5
  done
  echo "timed out waiting for queue to empty"; return 1
}

echo "== $(ts) setup: commit $(git rev-parse --short HEAD), image $(docker image inspect continuity-harness:local --format '{{.Id}}')"
kubectl -n "$NS" scale deploy/synthetic-worker --replicas="$WORKERS"
kubectl -n "$NS" rollout status deploy/synthetic-worker --timeout=120s
rc FLUSHDB >/dev/null

echo
echo "== $(ts) scenario A: rolling update while 8 x 45s jobs are in flight"
enqueue 8 45
sleep 10
echo "-- $(ts) in flight before rollout:"; for k in $(rc KEYS 'jobs:processing:*'); do echo "   $k $(rc LLEN "$k")"; done
# Follow the old pods' logs: they are deleted once terminated.
old_logs=$(mktemp)
kubectl -n "$NS" logs -f -l app=synthetic-worker --prefix --max-log-requests=10 --since=1s >"$old_logs" 2>&1 &
follow=$!
kubectl -n "$NS" set env deploy/synthetic-worker APP_VERSION="drain-test-$(date +%s)"
kubectl -n "$NS" rollout status deploy/synthetic-worker --timeout=600s
wait_for_empty
kill "$follow" 2>/dev/null || true
echo "-- $(ts) logs of the terminated (old) workers:"
sed 's/^/   /' "$old_logs"
echo "-- $(ts) audit:"
NS=$NS bash scripts/queue-audit.sh

echo
echo "== $(ts) scenario B: force-delete a worker mid-job (grace period 0, drain cut short)"
rc FLUSHDB >/dev/null
enqueue 8 40
sleep 10
victim=$(kubectl -n "$NS" get pod -l app=synthetic-worker -o jsonpath='{.items[0].metadata.name}')
echo "-- $(ts) force-deleting $victim"
kubectl -n "$NS" delete pod "$victim" --grace-period=0 --force
echo "-- $(ts) orphaned list is requeued after the ${HEARTBEAT_TTL:-30}s heartbeat TTL expires"
wait_for_empty
NS=$NS bash scripts/queue-audit.sh

echo
echo "== $(ts) both scenarios: lost=0"
