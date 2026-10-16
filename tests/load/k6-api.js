// k6 load profiles for the synthetic API, run in-cluster by scripts/run-k6.sh.
//   PROFILE=steady  constant RATE req/s for DURATION (deploy-under-load tests)
//   PROFILE=peak15x 150 req/s -> 2,250 req/s in 60s, hold 5m, back to 150
// Connections are reused; the API closes each connection after
// MAX_REQUESTS_PER_CONN requests, so clients reconnect and kube-proxy spreads
// them over newly scaled pods. (A first run with noConnectionReuse exhausted
// the load generator's ephemeral ports and dropped ~60% of iterations.)
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET || 'http://synthetic-api.continuity-demo:8080/';
const PROFILE = __ENV.PROFILE || 'steady';
const RATE = parseInt(__ENV.RATE || '150');
const DURATION = __ENV.DURATION || '5m';

const profiles = {
  steady: {
    executor: 'constant-arrival-rate',
    rate: RATE,
    timeUnit: '1s',
    duration: DURATION,
    preAllocatedVUs: 100,
    maxVUs: 1000,
  },
  peak15x: {
    executor: 'ramping-arrival-rate',
    startRate: 150,
    timeUnit: '1s',
    preAllocatedVUs: 300,
    maxVUs: 3000,
    stages: [
      { target: 150, duration: '60s' },
      { target: 2250, duration: '60s' },
      { target: 2250, duration: '5m' },
      { target: 150, duration: '30s' },
      { target: 150, duration: '60s' },
    ],
  },
};

export const options = {
  discardResponseBodies: true,
  scenarios: { load: profiles[PROFILE] },
  thresholds: {
    http_req_failed: ['rate<0.001'],
    http_req_duration: ['p(95)<400'],
    // If the generator cannot keep up, the run must fail rather than pass at a lower rate.
    dropped_iterations: ['count<1000'],
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const res = http.get(TARGET, { timeout: '10s' });
  check(res, { 'status is 200': (r) => r.status === 200 });
}

export function handleSummary(data) {
  const m = data.metrics;
  const out = {
    profile: PROFILE,
    requests: m.http_reqs.values.count,
    avg_rps: Number(m.http_reqs.values.rate.toFixed(1)),
    failed_requests: m.http_req_failed.values.passes,
    failed_rate: m.http_req_failed.values.rate,
    p50_ms: Number(m.http_req_duration.values['p(50)'].toFixed(1)),
    p95_ms: Number(m.http_req_duration.values['p(95)'].toFixed(1)),
    p99_ms: Number(m.http_req_duration.values['p(99)'].toFixed(1)),
    max_ms: Number(m.http_req_duration.values.max.toFixed(1)),
    dropped_iterations: m.dropped_iterations ? m.dropped_iterations.values.count : 0,
    thresholds_passed: Object.values(m).every((x) => !x.thresholds ||
      Object.values(x.thresholds).every((t) => t.ok)),
  };
  return { stdout: 'K6_SUMMARY ' + JSON.stringify(out) + '\n' };
}
