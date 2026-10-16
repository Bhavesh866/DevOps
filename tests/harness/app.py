"""Synthetic stand-in for the black-box assignment application.

It implements only the contract the platform depends on, so platform
mechanics (probes, rollouts, autoscaling, draining) can be exercised:

  ROLE=api             HTTP on :8080 with /healthz, /readyz, /metrics and /
  ROLE=worker          consumes jobs from a Redis list, drains on SIGTERM
  ROLE=producer        enqueues jobs at a fixed rate
  ROLE=queue-exporter  exposes queue depth, in-flight and oldest-job age

It is test scaffolding, not the assignment application.
"""
import os
import random
import signal
import socket
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLE = os.getenv("ROLE", "api")
VERSION = os.getenv("APP_VERSION", "synthetic-v1")
STOP = threading.Event()


def _on_term(signum, frame):
    STOP.set()


signal.signal(signal.SIGTERM, _on_term)
signal.signal(signal.SIGINT, _on_term)


# --------------------------------------------------------------------- API

# Fraction of "/" requests answered with HTTP 500; used to build a bad release.
FAIL_RATE = float(os.getenv("FAIL_RATE", "0"))
# Simulated work per "/" request.
LATENCY_MS = float(os.getenv("LATENCY_MS", "5"))
# Upper bound on waiting for in-flight requests after SIGTERM.
DRAIN_SECONDS = float(os.getenv("DRAIN_SECONDS", "20"))
# Close keep-alive connections after this many requests so clients reconnect
# and kube-proxy spreads them over newly scaled pods (cf. nginx keepalive_requests).
MAX_REQUESTS_PER_CONN = int(os.getenv("MAX_REQUESTS_PER_CONN", "100"))

BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.4, 0.5, 1.0, 2.5)
KNOWN_PATHS = {"/", "/healthz", "/readyz", "/metrics"}


class Metrics:
    def __init__(self):
        self.lock = threading.Lock()
        self.requests = {}  # (path, code) -> count
        self.buckets = [0] * len(BUCKETS)
        self.count = 0
        self.total = 0.0
        self.in_flight = 0

    def observe(self, path, code, seconds):
        with self.lock:
            key = (path, str(code))
            self.requests[key] = self.requests.get(key, 0) + 1
            if path == "/":
                self.count += 1
                self.total += seconds
                for i, bound in enumerate(BUCKETS):
                    if seconds <= bound:
                        self.buckets[i] += 1

    def render(self):
        with self.lock:
            lines = [
                "# HELP app_info Build information.",
                "# TYPE app_info gauge",
                f'app_info{{version="{VERSION}"}} 1',
                "# HELP http_requests_total HTTP requests by path and status code.",
                "# TYPE http_requests_total counter",
            ]
            for (path, code), n in sorted(self.requests.items()):
                lines.append(f'http_requests_total{{path="{path}",code="{code}"}} {n}')
            lines += [
                "# HELP http_request_duration_seconds Latency of / requests.",
                "# TYPE http_request_duration_seconds histogram",
            ]
            for bound, n in zip(BUCKETS, self.buckets):
                lines.append(f'http_request_duration_seconds_bucket{{le="{bound}"}} {n}')
            lines += [
                f'http_request_duration_seconds_bucket{{le="+Inf"}} {self.count}',
                f"http_request_duration_seconds_sum {self.total:.6f}",
                f"http_request_duration_seconds_count {self.count}",
                "# HELP http_requests_in_flight Requests currently being served.",
                "# TYPE http_requests_in_flight gauge",
                f"http_requests_in_flight {self.in_flight}",
            ]
            return "\n".join(lines) + "\n"


METRICS = Metrics()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    served = 0  # requests served on this connection (one handler per connection)

    def do_GET(self):
        start = time.monotonic()
        path = self.path.split("?", 1)[0]
        with METRICS.lock:
            METRICS.in_flight += 1
        try:
            code = self.route(path)
        finally:
            with METRICS.lock:
                METRICS.in_flight -= 1
        label = path if path in KNOWN_PATHS else "other"
        METRICS.observe(label, code, time.monotonic() - start)

    def route(self, path):
        if path == "/healthz":
            return self.respond(200, "healthy\n")
        if path == "/readyz":
            if STOP.is_set():
                return self.respond(503, "stopping\n")
            return self.respond(200, "ready\n")
        if path == "/metrics":
            return self.respond(200, METRICS.render(), "text/plain; version=0.0.4")
        if path == "/":
            time.sleep(LATENCY_MS / 1000)
            if random.random() < FAIL_RATE:
                return self.respond(500, f"synthetic failure; version={VERSION}\n")
            return self.respond(200, f"synthetic harness; version={VERSION}\n")
        return self.respond(404, "not found\n")

    def respond(self, status, body, content_type="text/plain"):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.served += 1
        if STOP.is_set() or self.served >= MAX_REQUESTS_PER_CONN:
            # Ask keep-alive clients to reconnect: during shutdown so they land
            # on a pod that is not stopping, otherwise to rebalance after scale-out.
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        self.wfile.write(data)
        return status

    def log_message(self, fmt, *args):
        pass  # Access logs at load-test rates drown the useful output.


class Server(ThreadingHTTPServer):
    daemon_threads = False  # server_close() waits for in-flight requests
    request_queue_size = 512


def run_api():
    server = Server(("0.0.0.0", 8080), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"api {VERSION} listening on :8080 fail_rate={FAIL_RATE}", flush=True)
    STOP.wait()
    # Kubernetes runs the preStop sleep before SIGTERM, so endpoints are already
    # being removed. Stop accepting, then let in-flight requests finish.
    print("SIGTERM: readiness now 503, draining in-flight requests", flush=True)
    server.shutdown()
    deadline = time.monotonic() + DRAIN_SECONDS
    while METRICS.in_flight and time.monotonic() < deadline:
        time.sleep(0.1)
    server.server_close()
    print(f"api stopped; in_flight_at_exit={METRICS.in_flight}", flush=True)


# ------------------------------------------------------------------ worker
#
# Reliable-queue pattern: BLMOVE atomically moves a job from jobs:pending to a
# per-worker processing list, so a job is never only in the worker's memory.
# A worker that dies without draining stops refreshing its heartbeat key; any
# worker then moves the orphaned processing list back to pending. Delivery is
# therefore at-least-once, and jobs:done (a set of job IDs) detects duplicates.

PENDING = "jobs:pending"
HEARTBEAT_TTL = 30


def _redis():
    import redis

    r = redis.Redis.from_url(
        os.getenv("REDIS_URL", "redis://redis:6379/0"), decode_responses=True
    )
    # Wait out Redis start-up instead of crash-looping; a Redis outage after
    # start-up still crashes the process, which is safe because claimed jobs
    # live in Redis, not in memory.
    for _ in range(30):
        try:
            r.ping()
            return r
        except redis.exceptions.ConnectionError:
            if STOP.wait(2):
                raise SystemExit(0)
    return r


def reap_orphans(r):
    for key in r.scan_iter("jobs:processing:*"):
        owner = key.split(":", 2)[2]
        if r.exists(f"worker:alive:{owner}"):
            continue
        moved = 0
        while r.lmove(key, PENDING, "RIGHT", "LEFT"):
            moved += 1
        if moved:
            r.incrby("jobs:requeued", moved)
            print(f"requeued {moved} orphaned job(s) from {owner}", flush=True)


def run_worker():
    r = _redis()
    wid = f"{socket.gethostname()}-{uuid.uuid4().hex[:6]}"
    processing = f"jobs:processing:{wid}"
    heartbeat = f"worker:alive:{wid}"
    drain = float(os.getenv("WORKER_DRAIN_TIMEOUT_SECONDS", "75"))
    stop_at = None
    last_reap = 0.0
    print(f"worker {wid} {VERSION} started drain_timeout={drain}s", flush=True)

    while not STOP.is_set():
        r.set(heartbeat, VERSION, ex=HEARTBEAT_TTL)
        if time.monotonic() - last_reap > HEARTBEAT_TTL:
            reap_orphans(r)
            last_reap = time.monotonic()
        job = r.blmove(PENDING, processing, 1, "LEFT", "RIGHT")
        if job is None:
            continue
        job_id, seconds = job.split("|")[:2]
        started = time.monotonic()
        released = False
        # Simulate work in short slices so the heartbeat stays fresh and a
        # drain deadline can be honoured.
        while time.monotonic() - started < float(seconds):
            r.set(heartbeat, VERSION, ex=HEARTBEAT_TTL)
            if STOP.is_set():
                stop_at = stop_at or time.monotonic()
                if time.monotonic() - stop_at > drain:
                    # Out of drain budget: hand the job back instead of losing it.
                    pipe = r.pipeline()
                    pipe.lrem(processing, 1, job)
                    pipe.lpush(PENDING, job)
                    pipe.incr("jobs:released")
                    pipe.execute()
                    released = True
                    print(f"released job {job_id} unfinished", flush=True)
                    break
            time.sleep(0.5)
        if released:
            break
        pipe = r.pipeline()
        pipe.sadd("jobs:done", job_id)
        pipe.incr("jobs:completed")
        pipe.lrem(processing, 1, job)
        first_completion, _, _ = pipe.execute()
        if not first_completion:
            r.incr("jobs:duplicates")
        if STOP.is_set():
            print(f"finished in-flight job {job_id} during drain", flush=True)

    r.delete(heartbeat)
    print(f"worker {wid} exited cleanly", flush=True)


def run_producer():
    r = _redis()
    rate = float(os.getenv("JOBS_PER_SECOND", "5.56"))
    low = float(os.getenv("JOB_SECONDS_MIN", "5"))
    high = float(os.getenv("JOB_SECONDS_MAX", "60"))
    total = int(os.getenv("TOTAL_JOBS", "0"))  # 0 means until stopped
    sent = 0
    print(f"producer rate={rate}/s duration={low}-{high}s total={total or 'unbounded'}", flush=True)
    while not STOP.is_set() and (total == 0 or sent < total):
        job = f"{uuid.uuid4().hex}|{random.uniform(low, high):.1f}|{time.time():.3f}"
        pipe = r.pipeline()
        pipe.rpush(PENDING, job)
        pipe.incr("jobs:enqueued")
        pipe.execute()
        sent += 1
        time.sleep(1 / rate)
    print(f"producer stopped after {sent} job(s)", flush=True)
    if total:
        STOP.wait()  # Stay Running so a Deployment does not restart and re-enqueue.


def queue_metrics(r):
    processing = sum(r.llen(k) for k in r.scan_iter("jobs:processing:*"))
    pending = r.llen(PENDING)
    oldest = r.lindex(PENDING, 0)
    age = 0.0
    if oldest and oldest.count("|") >= 2:
        age = max(0.0, time.time() - float(oldest.split("|")[2]))
    counters = {
        k: int(r.get(f"jobs:{k}") or 0)
        for k in ("enqueued", "completed", "duplicates", "requeued", "released")
    }
    lines = [
        "# TYPE jobs_pending gauge", f"jobs_pending {pending}",
        "# TYPE jobs_processing gauge", f"jobs_processing {processing}",
        "# HELP jobs_outstanding Pending plus in-flight jobs; the worker scaling signal.",
        "# TYPE jobs_outstanding gauge", f"jobs_outstanding {pending + processing}",
        "# TYPE jobs_oldest_pending_age_seconds gauge",
        f"jobs_oldest_pending_age_seconds {age:.3f}",
    ]
    for name, value in counters.items():
        lines += [f"# TYPE jobs_{name}_total counter", f"jobs_{name}_total {value}"]
    return "\n".join(lines) + "\n"


def run_queue_exporter():
    r = _redis()

    class ExporterHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/metrics":
                body, code = queue_metrics(r).encode(), 200
            elif self.path in ("/healthz", "/readyz"):
                body, code = b"ok\n", 200
            else:
                body, code = b"not found\n", 404
            self.send_response(code)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    server = ThreadingHTTPServer(("0.0.0.0", 8080), ExporterHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print("queue-exporter listening on :8080", flush=True)
    STOP.wait()
    server.shutdown()


if __name__ == "__main__":
    {
        "api": run_api,
        "worker": run_worker,
        "producer": run_producer,
        "queue-exporter": run_queue_exporter,
    }[ROLE]()
