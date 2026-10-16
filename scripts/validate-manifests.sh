#!/usr/bin/env bash
set -euo pipefail
command -v kubectl >/dev/null || { echo "kubectl required"; exit 2; }
kubectl kustomize platform/overlays/local >/tmp/continuity-rendered.yaml
grep -q 'kind: Deployment' /tmp/continuity-rendered.yaml
grep -q '/readyz' /tmp/continuity-rendered.yaml
grep -q '/healthz' /tmp/continuity-rendered.yaml
if grep -q 'REPLACE_WITH_REAL_IMAGE' /tmp/continuity-rendered.yaml; then
  echo "NOTICE: image placeholder remains; deployment will not be functional until replaced."
fi
echo "Manifest render/basic assertions passed; this is not a cluster deployment test."
