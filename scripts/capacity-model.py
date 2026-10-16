#!/usr/bin/env python3
import math
baseline_rps = 150
peak_rps = baseline_rps * 15
jobs_per_hour = 20000
arrival_rate = jobs_per_hour / 3600
duration = 60
factor = 1.5
print(f"Baseline API: {baseline_rps} req/s; peak: {peak_rps} req/s")
print(f"Average jobs/sec: {arrival_rate:.2f}")
print(f"Concurrency at 60s/job: {arrival_rate * duration:.1f}")
print(f"Planning worker slots at {factor}x: {math.ceil(arrival_rate * duration * factor)}")
print("API replicas by measured sustained throughput (before N+1/headroom):")
for per_pod in (25, 50, 100, 150, 250):
    print(f"  {per_pod} req/s/pod => {math.ceil(peak_rps / per_pod)} replicas")
print("DB connections = API replicas*API pool + worker connections + migrations + admin reserve.")
print("Hypothesis calculator only; it is not a benchmark and proves no scaling target.")
