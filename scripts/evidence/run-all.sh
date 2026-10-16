#!/usr/bin/env bash
# Reproduce every kind evidence log from scratch (~35 minutes).
# Prerequisites: docker, kind, kubectl, python3. Creates the cluster if missing.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
EVID=docs/evidence

kind get clusters | grep -qx continuity || kind create cluster --config platform/overlays/local/kind-config.yaml
TARGET=kind bash scripts/platform-addons.sh
docker build -t continuity-harness:local tests/harness
kind load docker-image continuity-harness:local --name continuity
kubectl apply -k tests/harness/k8s
kubectl -n continuity-demo rollout status deploy/synthetic-worker --timeout=180s
sleep 30  # Rollout reaches Healthy, Prometheus has scraped all targets

run() { echo ">>> $1"; bash "scripts/evidence/$1.sh" 2>&1 | grep -v 'Waiting for deployment' | tee "$EVID/$1.log"; }
run worker-drain
run autoscale-15x
run canary-under-load
run canary-auto-rollback
run restore-test
run migration-expand-contract
echo "all evidence regenerated in $EVID"
