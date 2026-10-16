#!/usr/bin/env bash
# Deploy the harness stack to the current cluster with the image pinned to a
# registry digest (pulled with a short-lived token), then wait until healthy.
set -euo pipefail
REF="$1"
NS=continuity-demo

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret docker-registry ghcr --docker-server=ghcr.io \
  --docker-username="$GHCR_USER" --docker-password="$GHCR_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
for _ in $(seq 30); do kubectl -n "$NS" get serviceaccount default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n "$NS" patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr"}]}'

work=$(mktemp -d)
cp tests/harness/k8s/*.yaml "$work/"
(cd "$work" && kustomize edit set image "continuity-harness:local=$REF")
kubectl kustomize "$work" | grep -q "image: $REF"
kubectl apply -k "$work"

kubectl -n "$NS" rollout status deploy/redis --timeout=180s
kubectl -n "$NS" rollout status deploy/synthetic-worker --timeout=180s
for _ in $(seq 60); do
  [ "$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.phase}')" = Healthy ] && break
  sleep 5
done
kubectl -n "$NS" get rollout,deploy,pods
kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'
[ "$(kubectl -n "$NS" get rollout synthetic-api -o jsonpath='{.status.phase}')" = Healthy ]
