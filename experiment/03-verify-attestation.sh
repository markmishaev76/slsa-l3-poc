#!/bin/bash
# Verify SLSA attestations for a container image
# Usage: ./03-verify-attestation.sh [owner/repo] [digest]

set -euo pipefail

REPO="${1:-}"
DIGEST="${2:-}"

if [[ -z "$REPO" ]]; then
    echo "Usage: $0 <owner/repo> [digest]"
    echo ""
    echo "Examples:"
    echo "  $0 myuser/slsa-l3-experiment"
    echo "  $0 myuser/slsa-l3-experiment sha256:abc123..."
    exit 1
fi

OWNER=$(echo "$REPO" | cut -d'/' -f1)

echo "═══════════════════════════════════════════════════════════════"
echo "  Verifying SLSA Attestations"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Repository: $REPO"
echo "Owner: $OWNER"
echo ""

# If no digest provided, get the latest
if [[ -z "$DIGEST" ]]; then
    echo "Fetching latest image digest..."
    DIGEST=$(gh api "users/${OWNER}/packages/container/${REPO##*/}/versions" \
        --jq '.[0].name' 2>/dev/null || echo "")
    
    if [[ -z "$DIGEST" ]]; then
        echo "❌ Could not find image. Make sure the workflow has run successfully."
        exit 1
    fi
    echo "Found: $DIGEST"
fi

IMAGE="ghcr.io/${REPO}@${DIGEST}"
echo ""
echo "Image: $IMAGE"
echo ""

echo "───────────────────────────────────────────────────────────────"
echo "  Method 1: Basic Verification (SLSA L2)"
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "Command: gh attestation verify oci://${IMAGE} --owner ${OWNER}"
echo ""

gh attestation verify "oci://${IMAGE}" --owner "${OWNER}" && {
    echo ""
    echo "✅ Basic verification passed (SLSA L2)"
} || {
    echo ""
    echo "❌ Basic verification failed"
}

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Method 2: Workflow-Specific Verification (SLSA L3)"
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "Command: gh attestation verify oci://${IMAGE} --owner ${OWNER} \\"
echo "         --signer-workflow ${REPO}/.github/workflows/slsa-l3-reusable.yml"
echo ""

gh attestation verify "oci://${IMAGE}" \
    --owner "${OWNER}" \
    --signer-workflow "${REPO}/.github/workflows/slsa-l3-reusable.yml" && {
    echo ""
    echo "✅ Workflow verification passed (SLSA L3)"
    echo ""
    echo "This proves:"
    echo "  • Artifact was built by the specified reusable workflow"
    echo "  • Build process was isolated from caller workflow"
    echo "  • Attestation was generated in the trusted build environment"
} || {
    echo ""
    echo "❌ Workflow verification failed"
    echo ""
    echo "This could mean:"
    echo "  • Image was not built by the reusable workflow"
    echo "  • Attestation was generated differently"
}

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Method 3: View Raw Attestation"
echo "───────────────────────────────────────────────────────────────"
echo ""

gh attestation verify "oci://${IMAGE}" --owner "${OWNER}" --format json 2>/dev/null | jq '.' || {
    echo "Could not retrieve attestation JSON"
}

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Cosign Verification (Alternative)"
echo "───────────────────────────────────────────────────────────────"
echo ""

if command -v cosign &> /dev/null; then
    echo "Command: cosign verify-attestation ${IMAGE} \\"
    echo "         --type slsaprovenance \\"
    echo "         --certificate-identity-regexp 'https://github.com/${REPO}/.*' \\"
    echo "         --certificate-oidc-issuer https://token.actions.githubusercontent.com"
    echo ""
    
    cosign verify-attestation "${IMAGE}" \
        --type slsaprovenance \
        --certificate-identity-regexp "https://github.com/${REPO}/.*" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" && {
        echo ""
        echo "✅ Cosign verification passed"
    } || {
        echo ""
        echo "❌ Cosign verification failed (or attestation format differs)"
    }
else
    echo "Cosign not installed. Install with:"
    echo "  brew install cosign"
    echo "  # or"
    echo "  go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
fi

echo ""
