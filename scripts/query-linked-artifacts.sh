#!/bin/bash
# Query Linked Artifacts
#
# Retrieve all linked artifacts with their attestations, storage locations,
# and deployment history from your organization.
#
# Reference: https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Query linked artifacts with their attestations, storage locations, and deployments.

OPTIONS:
    -o, --org               GitHub organization name (required)
    -p, --package           Filter by package name (optional)
    -t, --package-type      Filter by package type: container, npm, maven, etc. (optional)
    -e, --environment       Filter by deployment environment (optional)
    --has-deployment        Only show artifacts with deployment records
    --has-attestation       Only show artifacts with attestations
    --risk-level            Filter by runtime risk level: low, medium, high, critical
    --format                Output format: table, json, summary (default: table)
    -h, --help              Show this help message

EXAMPLES:
    # List all linked artifacts
    $(basename "$0") -o openbao

    # Show only production deployments with high risk
    $(basename "$0") -o openbao --has-deployment -e production --risk-level high

    # Get JSON output for scripting
    $(basename "$0") -o openbao --format json

ENVIRONMENT:
    GITHUB_TOKEN    GitHub token with packages:read permission (required)
EOF
}

# Default values
OUTPUT_FORMAT="table"
HAS_DEPLOYMENT=""
HAS_ATTESTATION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            ORG="$2"
            shift 2
            ;;
        -p|--package)
            PACKAGE_FILTER="$2"
            shift 2
            ;;
        -t|--package-type)
            PACKAGE_TYPE_FILTER="$2"
            shift 2
            ;;
        -e|--environment)
            ENV_FILTER="$2"
            shift 2
            ;;
        --has-deployment)
            HAS_DEPLOYMENT="true"
            shift
            ;;
        --has-attestation)
            HAS_ATTESTATION="true"
            shift
            ;;
        --risk-level)
            RISK_FILTER="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
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
if [[ -z "${ORG:-}" ]]; then
    echo -e "${RED}Error: Organization name is required${NC}"
    usage
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo -e "${RED}Error: GITHUB_TOKEN environment variable is required${NC}"
    exit 1
fi

# Build query parameters
build_query_params() {
    local params=""
    [[ -n "${PACKAGE_FILTER:-}" ]] && params="${params}&package=${PACKAGE_FILTER}"
    [[ -n "${PACKAGE_TYPE_FILTER:-}" ]] && params="${params}&package_type=${PACKAGE_TYPE_FILTER}"
    [[ -n "${ENV_FILTER:-}" ]] && params="${params}&environment=${ENV_FILTER}"
    [[ -n "${HAS_DEPLOYMENT}" ]] && params="${params}&has_deployment=true"
    [[ -n "${HAS_ATTESTATION}" ]] && params="${params}&has_attestation=true"
    [[ -n "${RISK_FILTER:-}" ]] && params="${params}&runtime_risk=${RISK_FILTER}"
    
    # Remove leading &
    echo "${params#&}"
}

# Format risk level with color
format_risk() {
    local risk="$1"
    case "${risk}" in
        low)
            echo -e "${GREEN}low${NC}"
            ;;
        medium)
            echo -e "${YELLOW}medium${NC}"
            ;;
        high)
            echo -e "${RED}high${NC}"
            ;;
        critical)
            echo -e "${RED}CRITICAL${NC}"
            ;;
        *)
            echo "${risk}"
            ;;
    esac
}

# Format attestation type
format_attestation() {
    local type="$1"
    case "${type}" in
        build-provenance)
            echo "🔐 provenance"
            ;;
        sbom)
            echo "📋 sbom"
            ;;
        vulnerability-scan)
            echo "🔍 vuln-scan"
            ;;
        *)
            echo "${type}"
            ;;
    esac
}

# Display table output
display_table() {
    local data="$1"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${CYAN}%-40s %-12s %-25s %-15s %-12s${NC}\n" "ARTIFACT" "TYPE" "STORAGE" "ENVIRONMENT" "RISK"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo "$data" | jq -r '.artifacts[]? // empty | [
        .name,
        .package_type,
        (.storage_records[0]?.registry_url // "N/A"),
        (.deployment_records[0]?.environment // "N/A"),
        (.deployment_records[0]?.runtime_risk?.risk_level // "N/A")
    ] | @tsv' | while IFS=$'\t' read -r name type storage env risk; do
        printf "%-40s %-12s %-25s %-15s " "${name:0:40}" "${type}" "${storage:0:25}" "${env}"
        format_risk "${risk}"
    done
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Display summary output
display_summary() {
    local data="$1"
    
    local total=$(echo "$data" | jq '.artifacts | length // 0')
    local with_deployments=$(echo "$data" | jq '[.artifacts[]? | select(.deployment_records | length > 0)] | length')
    local with_attestations=$(echo "$data" | jq '[.artifacts[]? | select(.attestations | length > 0)] | length')
    local high_risk=$(echo "$data" | jq '[.artifacts[]? | select(.deployment_records[]?.runtime_risk?.risk_level == "high" or .deployment_records[]?.runtime_risk?.risk_level == "critical")] | length')
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}                    Linked Artifacts Summary                           ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "📦 Total Artifacts:          ${total}"
    echo "🚀 With Deployments:         ${with_deployments}"
    echo "🔐 With Attestations:        ${with_attestations}"
    echo -e "⚠️  High/Critical Risk:      ${RED}${high_risk}${NC}"
    echo ""
    
    if [[ "${high_risk}" -gt 0 ]]; then
        echo -e "${RED}⚠️  Warning: You have ${high_risk} artifact(s) in high/critical risk deployments!${NC}"
        echo "   Consider reviewing security alerts with: has:deployment runtime-risk:high"
    fi
    echo ""
}

# Main execution
QUERY_PARAMS=$(build_query_params)
API_URL="https://api.github.com/orgs/${ORG}/linked-artifacts"
[[ -n "${QUERY_PARAMS}" ]] && API_URL="${API_URL}?${QUERY_PARAMS}"

echo -e "${YELLOW}Querying linked artifacts for organization: ${ORG}...${NC}"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API_URL}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 ]] && [[ "$HTTP_CODE" -lt 300 ]]; then
    case "${OUTPUT_FORMAT}" in
        json)
            echo "$BODY" | jq .
            ;;
        summary)
            display_summary "$BODY"
            ;;
        table|*)
            display_table "$BODY"
            display_summary "$BODY"
            ;;
    esac
else
    echo -e "${RED}❌ Failed to query linked artifacts (HTTP ${HTTP_CODE})${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi
