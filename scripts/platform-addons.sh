#!/usr/bin/env bash
# Platform layer add-ons, pinned. The same versions are intended for EKS; only
# metrics-server's --kubelet-insecure-tls flag is kind-specific.
#   TARGET=kind bash scripts/platform-addons.sh
set -euo pipefail

TARGET="${TARGET:-kind}"
METRICS_SERVER_VERSION=v0.7.2
KEDA_VERSION=2.16.1
ARGO_ROLLOUTS_VERSION=v1.7.2

echo "== metrics-server $METRICS_SERVER_VERSION"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"
if [ "$TARGET" = kind ]; then
  # kind kubelets use self-signed serving certificates.
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
fi

echo "== KEDA $KEDA_VERSION"
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}.yaml"

echo "== Argo Rollouts $ARGO_ROLLOUTS_VERSION"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ARGO_ROLLOUTS_VERSION}/install.yaml"

if [ "$TARGET" = kind ]; then
  echo "== Prometheus (kind-only minimal deployment)"
  kubectl apply -k platform/observability
fi

kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
kubectl -n keda rollout status deploy/keda-operator --timeout=300s
kubectl -n keda rollout status deploy/keda-metrics-apiserver --timeout=300s
kubectl -n keda rollout status deploy/keda-admission --timeout=300s
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s
if [ "$TARGET" = kind ]; then
  kubectl -n monitoring rollout status deploy/prometheus --timeout=180s
fi
echo "add-ons ready"
