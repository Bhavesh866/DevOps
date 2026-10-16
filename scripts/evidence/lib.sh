# Shared helpers for evidence scripts. Source, do not execute.
NS="${NS:-continuity-demo}"

ts() { date -u +%H:%M:%S; }

# Instant Prometheus query -> first value rounded, or "-" when empty/NaN.
promq() {
  kubectl -n monitoring exec deploy/prometheus -- wget -qO- \
    "http://localhost:9090/api/v1/query?query=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1")" \
    | python3 -c '
import json, math, sys
r = json.load(sys.stdin)["data"]["result"]
v = float(r[0]["value"][1]) if r else float("nan")
print("-" if math.isnan(v) else (f"{v:.3f}" if abs(v) < 10 else f"{v:.0f}"))'
}

Q_RPS='sum(rate(http_requests_total{namespace="continuity-demo",path="/"}[30s]))'
Q_ERR='sum(rate(http_requests_total{namespace="continuity-demo",path="/",code=~"5.."}[30s])) or vector(0)'
Q_P95_MS='1000 * histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="continuity-demo"}[30s])))'
Q_OUTSTANDING='sum(jobs_outstanding{namespace="continuity-demo"})'
Q_OLDEST='max(jobs_oldest_pending_age_seconds{namespace="continuity-demo"})'

sample_header() {
  printf '%-8s %8s %9s %8s %8s %8s %8s %11s %9s\n' \
    time api_want api_ready api_cpu rps err_rps p95_ms outstanding workers
}

sample() {
  local want ready cpu workers
  want=$(kubectl -n "$NS" get hpa synthetic-api -o jsonpath='{.status.desiredReplicas}')
  ready=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.availableReplicas}')
  cpu=$(kubectl -n "$NS" get hpa synthetic-api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')
  workers=$(kubectl -n "$NS" get deploy synthetic-worker -o jsonpath='{.status.readyReplicas}')
  printf '%-8s %8s %9s %7s%% %8s %8s %8s %11s %9s\n' \
    "$(ts)" "$want" "$ready" "${cpu:--}" "$(promq "$Q_RPS")" "$(promq "$Q_ERR")" \
    "$(promq "$Q_P95_MS")" "$(promq "$Q_OUTSTANDING")" "${workers:-0}"
}

# Set the API Rollout's APP_VERSION and FAIL_RATE (env indexes 1 and 3), which
# is what a GitOps commit changing the release would do.
set_release() {
  kubectl -n "$NS" patch rollout synthetic-api --type=json -p "[
    {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/1/value\",\"value\":\"$1\"},
    {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/3/value\",\"value\":\"$2\"}]" >/dev/null
}

rollout_header() {
  printf '%-8s %-12s %4s %7s %-12s %8s %8s %8s %s\n' \
    time phase step pods analysis rps err_rps p95_ms versions
}

# Samples must never abort the evidence script: missing objects (no AnalysisRun
# before the first analysed step) print "-" instead.
rollout_sample() {
  local phase step pods ar versions
  phase=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.phase}' || true)
  step=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.currentStepIndex}' || true)
  pods=$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.availableReplicas}' || true)
  ar=$(kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1:].status.phase}' 2>/dev/null || true)
  versions=$(kubectl -n monitoring exec deploy/prometheus -- wget -qO- \
    'http://localhost:9090/api/v1/query?query=count%20by%20(version)%20(app_info%7Bnamespace%3D%22continuity-demo%22%7D)' \
    | python3 -c 'import json,sys; print(",".join(r["metric"]["version"] + "=" + r["value"][1] for r in json.load(sys.stdin)["data"]["result"]))' || true)
  printf '%-8s %-12s %4s %7s %-12s %8s %8s %8s %s\n' \
    "$(ts)" "$phase" "${step:--}" "$pods" "${ar:--}" "$(promq "$Q_RPS")" "$(promq "$Q_ERR")" "$(promq "$Q_P95_MS")" "$versions"
}

analysis_report() {
  kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp -o json | python3 -c '
import json, sys
run = json.load(sys.stdin)["items"][-1]
status = run["status"]
print("   analysisrun %s: phase=%s %s" % (run["metadata"]["name"], status["phase"], status.get("message", "")))
for m in status.get("metricResults", []):
    vals = [x.get("value", "-") for x in m.get("measurements", [])]
    print("   - %s: phase=%s successful=%s failed=%s last values=%s"
          % (m["name"], m["phase"], m.get("successful", 0), m.get("failed", 0), vals[-6:]))'
}

# Wait for a k6 Job to finish either way: a Job whose thresholds fail ends
# Failed, never Complete (expected for the bad-release test).
k6_wait() {
  for _ in $(seq 120); do
    kubectl -n "$NS" get job "$1" -o jsonpath='{.status.conditions[*].type}' | grep -qE 'Complete|Failed' && return 0
    sleep 5
  done
  echo "k6 job $1 did not finish"; return 1
}

k6_summary() { kubectl -n "$NS" logs "job/$1" | grep K6_SUMMARY | sed 's/^K6_SUMMARY //'; }
