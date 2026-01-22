#!/bin/bash
# Test the new GitHub Artifact Metadata APIs
# These APIs were announced in the Jan 2026 changelog
#
# NOTE: These APIs may require:
# - Specific GitHub plan (Enterprise?)
# - Feature flag enablement
# - Beta access

set -euo pipefail

REPO="${1:-}"
DIGEST="${2:-}"

if [[ -z "$REPO" ]]; then
    echo "Usage: $0 <owner/repo> [digest]"
    exit 1
fi

ORG=$(echo "$REPO" | cut -d'/' -f1)
PACKAGE=$(echo "$REPO" | cut -d'/' -f2)
GITHUB_TOKEN=$(gh auth token)

echo "═══════════════════════════════════════════════════════════════"
echo "  Testing GitHub Artifact Metadata APIs"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Organization: $ORG"
echo "Package: $PACKAGE"
echo ""

# Get package version if digest not provided
if [[ -z "$DIGEST" ]]; then
    echo "Fetching latest package version..."
    VERSION_INFO=$(gh api "users/${ORG}/packages/container/${PACKAGE}/versions" --jq '.[0]' 2>/dev/null || echo "")
    
    if [[ -z "$VERSION_INFO" ]]; then
        echo "❌ Could not find package versions"
        exit 1
    fi
    
    VERSION_ID=$(echo "$VERSION_INFO" | jq -r '.id')
    DIGEST=$(echo "$VERSION_INFO" | jq -r '.name')
    echo "Version ID: $VERSION_ID"
    echo "Digest: $DIGEST"
fi

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Test 1: Create Storage Record"
echo "───────────────────────────────────────────────────────────────"
echo ""

STORAGE_PAYLOAD=$(cat << EOF
{
    "registry_url": "ghcr.io/${ORG}/${PACKAGE}@${DIGEST}",
    "registry_name": "GitHub Container Registry",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

echo "Endpoint: POST /orgs/${ORG}/packages/container/${PACKAGE}/versions/{version}/storage-records"
echo ""
echo "Payload:"
echo "$STORAGE_PAYLOAD" | jq .
echo ""
echo "Response:"

curl -s -w "\nHTTP Status: %{http_code}\n" -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/packages/container/${PACKAGE}/versions/${DIGEST}/storage-records" \
    -d "$STORAGE_PAYLOAD" | jq . 2>/dev/null || cat

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Test 2: Create Deployment Record"
echo "───────────────────────────────────────────────────────────────"
echo ""

DEPLOYMENT_PAYLOAD=$(cat << EOF
{
    "environment": "staging",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "cloud_provider": "kubernetes",
    "cluster_name": "test-cluster",
    "namespace": "default",
    "runtime_risk": {
        "internet_exposed": false,
        "processes_sensitive_data": false,
        "risk_level": "low"
    }
}
EOF
)

echo "Endpoint: POST /orgs/${ORG}/packages/container/${PACKAGE}/versions/{version}/deployment-records"
echo ""
echo "Payload:"
echo "$DEPLOYMENT_PAYLOAD" | jq .
echo ""
echo "Response:"

curl -s -w "\nHTTP Status: %{http_code}\n" -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/packages/container/${PACKAGE}/versions/${DIGEST}/deployment-records" \
    -d "$DEPLOYMENT_PAYLOAD" | jq . 2>/dev/null || cat

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Test 3: Query Linked Artifacts"
echo "───────────────────────────────────────────────────────────────"
echo ""

echo "Endpoint: GET /orgs/${ORG}/linked-artifacts"
echo ""
echo "Response:"

curl -s -w "\nHTTP Status: %{http_code}\n" -X GET \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/linked-artifacts" | jq . 2>/dev/null || cat

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Test 4: Filter Dependabot Alerts (with new filters)"
echo "───────────────────────────────────────────────────────────────"
echo ""

echo "Endpoint: GET /orgs/${ORG}/dependabot/alerts?q=has:deployment"
echo ""
echo "Response:"

curl -s -w "\nHTTP Status: %{http_code}\n" -X GET \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/dependabot/alerts?q=has:deployment" | jq '.[:3]' 2>/dev/null || cat

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  API Test Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Notes:"
echo "  • HTTP 404: API endpoint may not be available yet"
echo "  • HTTP 403: May require specific permissions or plan"
echo "  • HTTP 422: Validation error in request"
echo ""
echo "These APIs are from the Jan 2026 announcement and may require:"
echo "  • GitHub Enterprise plan"
echo "  • Feature flag enablement"
echo "  • Partner integration (Defender for Cloud, JFrog)"
echo ""
