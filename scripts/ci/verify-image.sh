#!/usr/bin/env bash
# Refuse an image unless it was signed by this repository's CI workflow on the
# main branch and carries a signed CycloneDX SBOM attestation.
set -euo pipefail
REF="$1"
IDENTITY="^https://github.com/${GITHUB_REPOSITORY}/.github/workflows/ci.yml@refs/heads/(master|main)$"
ISSUER=https://token.actions.githubusercontent.com

cosign verify --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER" "$REF" >/dev/null
cosign verify-attestation --type cyclonedx \
  --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER" "$REF" >/dev/null
echo "verified signature and SBOM attestation for $REF"
