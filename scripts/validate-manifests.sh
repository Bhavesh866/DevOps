#!/usr/bin/env bash
# Render every overlay (local, aws, each tenant) and the kind test harness and
# assert basic invariants. Rendering only: this is not a cluster deployment test.
set -euo pipefail
command -v kubectl >/dev/null || { echo "kubectl required"; exit 2; }
out=$(mktemp -d)

overlays=(platform/overlays/local platform/overlays/aws platform/tenants/* tests/harness/k8s platform/observability)
for dir in "${overlays[@]}"; do
  file="$out/$(echo "$dir" | tr / _).yaml"
  kubectl kustomize "$dir" > "$file"
  echo "rendered $dir ($(grep -c '^kind:' "$file") resources)"
done

for file in "$out"/platform_overlays_*.yaml "$out"/platform_tenants_*.yaml; do
  grep -q '/readyz' "$file"
  grep -q '/healthz' "$file"
  grep -q 'kind: ScaledObject' "$file"
  grep -q 'kind: NetworkPolicy' "$file"
done

for file in "$out"/platform_tenants_*.yaml; do
  tenant=$(basename "$file" .yaml | sed 's/^platform_tenants_//')
  grep -q "tenant: $tenant" "$file" || { echo "tenant label missing in $tenant"; exit 1; }
  grep -q "key: $tenant/prod/app-secrets" "$file" || { echo "secret key not tenant-scoped in $tenant"; exit 1; }
done

if grep -l 'REPLACE_WITH_REAL_IMAGE' "$out"/platform_*.yaml >/dev/null; then
  echo "NOTICE: application image placeholder remains in platform overlays; the real image is a black box not supplied."
fi
echo "Manifest render/basic assertions passed; this is not a cluster deployment test."
