#!/bin/bash
# Create Storage Record for Linked Artifacts
# 
# Storage records capture where an artifact is stored in a package registry.
# This enables code-to-cloud traceability by linking GitHub-attested artifacts
# to their storage locations.
#
# Reference: https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create a storage record linking an artifact to its registry location.

OPTIONS:
    -o, --org               GitHub organization name (required)
    -p, --package           Package name (required)
    -t, --package-type      Package type: container, npm, maven, etc. (default: container)
    -d, --digest            Artifact digest (sha256:...) (required)
    -r, --registry-url      Full registry URL where artifact is stored (required)
    -n, --registry-name     Registry name for display (optional)
    --promoted-from         Previous registry URL if this is a promotion (optional)
    --promotion-policy      Promotion policy name (optional)
    -h, --help              Show this help message

EXAMPLES:
    # Create storage record for container in GHCR
    $(basename "$0") -o openbao -p openbao -d sha256:abc123 -r ghcr.io/openbao/openbao:v2.1.0

    # Create storage record with promotion tracking
    $(basename "$0") -o openbao -p openbao -d sha256:abc123 \\
        -r jfrog.example.com/prod/openbao:v2.1.0 \\
        --promoted-from ghcr.io/openbao/openbao:v2.1.0 \\
        --promotion-policy "staging-to-prod"

ENVIRONMENT:
    GITHUB_TOKEN    GitHub token with packages:write permission (required)
EOF
}

# Default values
PACKAGE_TYPE="container"
REGISTRY_NAME=""
PROMOTED_FROM=""
PROMOTION_POLICY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            ORG="$2"
            shift 2
            ;;
        -p|--package)
            PACKAGE="$2"
            shift 2
            ;;
        -t|--package-type)
            PACKAGE_TYPE="$2"
            shift 2
            ;;
        -d|--digest)
            DIGEST="$2"
            shift 2
            ;;
        -r|--registry-url)
            REGISTRY_URL="$2"
            shift 2
            ;;
        -n|--registry-name)
            REGISTRY_NAME="$2"
            shift 2
            ;;
        --promoted-from)
            PROMOTED_FROM="$2"
            shift 2
            ;;
        --promotion-policy)
            PROMOTION_POLICY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${ORG:-}" ]] || [[ -z "${PACKAGE:-}" ]] || [[ -z "${DIGEST:-}" ]] || [[ -z "${REGISTRY_URL:-}" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    usage
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo -e "${RED}Error: GITHUB_TOKEN environment variable is required${NC}"
    exit 1
fi

# Build JSON payload
build_payload() {
    local payload
    payload=$(cat << EOF
{
    "registry_url": "${REGISTRY_URL}",
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
)

    if [[ -n "${REGISTRY_NAME}" ]]; then
        payload=$(echo "$payload" | sed 's/}$/,/')
        payload="${payload}
    \"registry_name\": \"${REGISTRY_NAME}\"
}"
    fi

    if [[ -n "${PROMOTED_FROM}" ]]; then
        payload=$(echo "$payload" | sed 's/}$/,/')
        payload="${payload}
    \"promoted_from\": \"${PROMOTED_FROM}\""
        if [[ -n "${PROMOTION_POLICY}" ]]; then
            payload="${payload},
    \"promotion_policy\": \"${PROMOTION_POLICY}\""
        fi
        payload="${payload}
}"
    fi

    echo "$payload"
}

echo -e "${YELLOW}Creating storage record...${NC}"
echo ""
echo "Organization: ${ORG}"
echo "Package: ${PACKAGE} (${PACKAGE_TYPE})"
echo "Digest: ${DIGEST}"
echo "Registry URL: ${REGISTRY_URL}"
if [[ -n "${PROMOTED_FROM}" ]]; then
    echo "Promoted from: ${PROMOTED_FROM}"
fi
echo ""

# API endpoint
API_URL="https://api.github.com/orgs/${ORG}/packages/${PACKAGE_TYPE}/${PACKAGE}/versions/${DIGEST}/storage-records"

# Build and send request
PAYLOAD=$(build_payload)

echo -e "${YELLOW}Sending request to: ${API_URL}${NC}"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "${API_URL}" \
    -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 ]] && [[ "$HTTP_CODE" -lt 300 ]]; then
    echo -e "${GREEN}✅ Storage record created successfully!${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
    echo -e "${RED}❌ Failed to create storage record (HTTP ${HTTP_CODE})${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi
