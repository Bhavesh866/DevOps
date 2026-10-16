import os
import signal
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLE = os.getenv("ROLE", "api")
VERSION = os.getenv("APP_VERSION", "synthetic-v1")
READY = True
STOPPING = False

def stop_handler(signum, frame):
    global READY, STOPPING
    READY = False
    STOPPING = True

signal.signal(signal.SIGTERM, stop_handler)
signal.signal(signal.SIGINT, stop_handler)

if ROLE == "worker":
    # Synthetic lifecycle test only: no Redis connection or job processing.
    while not STOPPING:
        time.sleep(1)
    raise SystemExit(0)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.respond(200, "healthy\n")
        elif self.path == "/readyz":
            self.respond(200 if READY and not STOPPING else 503,
                         "ready\n" if READY and not STOPPING else "stopping\n")
        elif self.path == "/metrics":
            body = (
                "# HELP synthetic_requests_total Requests handled by the synthetic harness\n"
                "# TYPE synthetic_requests_total counter\n"
                "synthetic_requests_total 1\n"
            )
            self.respond(200, body, "text/plain; version=0.0.4")
        elif self.path == "/":
            self.respond(200, f"synthetic harness; version={VERSION}\n")
        else:
            self.respond(404, "not found\n")

    def respond(self, status, body, content_type="text/plain"):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
server.timeout = 1
while not STOPPING:
    server.handle_request()
server.server_close()
