#!/usr/bin/env bash
# Build the synthetic harness image once, then scan it and generate its SBOM
# from the same local image ID so every evidence file describes one artifact.
set -euo pipefail

IMAGE="${1:-continuity-harness:hardened}"
OUT_DIR="${2:-docs/evidence/final}"
mkdir -p "$OUT_DIR"

docker build -t "$IMAGE" tests/harness
IMAGE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# All severities, unfixed included: the full picture, not a gate.
trivy image --quiet --format json --output "$OUT_DIR/trivy-all-severities.json" "$IMAGE"
# The gate CI enforces: HIGH/CRITICAL with a fix available fails the build.
trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  --format table --output "$OUT_DIR/trivy-gate-high-critical.txt" "$IMAGE"
trivy image --quiet --format cyclonedx --output "$OUT_DIR/sbom.cdx.json" "$IMAGE"

{
  echo "image_ref=$IMAGE"
  echo "image_id=$IMAGE_ID"
  echo "generated_at=$TIMESTAMP"
  echo "git_commit=$(git rev-parse HEAD)"
  echo "git_dirty=$(test -z "$(git status --porcelain)" && echo false || echo true)"
  echo "trivy_version=$(trivy --version | head -1 | awk '{print $2}')"
} > "$OUT_DIR/provenance.txt"

cat "$OUT_DIR/provenance.txt"
echo "HIGH/CRITICAL gate passed for $IMAGE_ID"
