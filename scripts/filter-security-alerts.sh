#!/bin/bash
# Filter Security Alerts by Production Context
#
# Filter Dependabot and code scanning alerts based on deployment records
# and runtime risk to prioritize vulnerabilities that matter most.
#
# Reference: https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Filter security alerts based on production context and deployment records.

OPTIONS:
    -o, --org               GitHub organization name (required)
    -r, --repo              Repository name (optional, defaults to all repos)
    
    Production Context Filters (NEW):
    --has-deployment        Only alerts affecting deployed artifacts
    --runtime-risk          Filter by risk level: low, medium, high, critical
    --artifact-registry     Filter by registry URL pattern
    --internet-exposed      Only alerts for internet-exposed workloads
    
    Traditional Filters:
    --severity              Filter by severity: critical, high, medium, low
    --state                 Filter by state: open, fixed, dismissed
    --epss-min              Minimum EPSS score (0.0-1.0)
    --cvss-min              Minimum CVSS score (0.0-10.0)
    
    --alert-type            Alert type: dependabot, code-scanning, secret-scanning, all
    --format                Output format: table, json, summary (default: table)
    -h, --help              Show this help message

EXAMPLES:
    # High-priority: deployed to production with high risk
    $(basename "$0") -o openbao --has-deployment --runtime-risk high --severity critical

    # All alerts affecting GHCR artifacts
    $(basename "$0") -o openbao --artifact-registry ghcr.io

    # Critical alerts for internet-exposed workloads
    $(basename "$0") -o openbao --internet-exposed --severity critical

    # Combine EPSS scoring with deployment context
    $(basename "$0") -o openbao --has-deployment --epss-min 0.7 --severity high

ENVIRONMENT:
    GITHUB_TOKEN    GitHub token with security_events:read permission (required)
EOF
}

# Default values
OUTPUT_FORMAT="table"
ALERT_TYPE="all"
SEVERITY=""
STATE="open"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            ORG="$2"
            shift 2
            ;;
        -r|--repo)
            REPO="$2"
            shift 2
            ;;
        --has-deployment)
            HAS_DEPLOYMENT="true"
            shift
            ;;
        --runtime-risk)
            RUNTIME_RISK="$2"
            shift 2
            ;;
        --artifact-registry)
            ARTIFACT_REGISTRY="$2"
            shift 2
            ;;
        --internet-exposed)
            INTERNET_EXPOSED="true"
            shift
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --state)
            STATE="$2"
            shift 2
            ;;
        --epss-min)
            EPSS_MIN="$2"
            shift 2
            ;;
        --cvss-min)
            CVSS_MIN="$2"
            shift 2
            ;;
        --alert-type)
            ALERT_TYPE="$2"
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

# Build query string for the new filters
build_filter_query() {
    local filters=""
    
    # Production context filters (new)
    [[ -n "${HAS_DEPLOYMENT:-}" ]] && filters="${filters}+has:deployment"
    [[ -n "${RUNTIME_RISK:-}" ]] && filters="${filters}+runtime-risk:${RUNTIME_RISK}"
    [[ -n "${ARTIFACT_REGISTRY:-}" ]] && filters="${filters}+artifact-registry:${ARTIFACT_REGISTRY}"
    [[ -n "${INTERNET_EXPOSED:-}" ]] && filters="${filters}+runtime-risk-factor:internet-exposed"
    
    # Traditional filters
    [[ -n "${SEVERITY:-}" ]] && filters="${filters}+severity:${SEVERITY}"
    [[ -n "${STATE:-}" ]] && filters="${filters}+state:${STATE}"
    
    # Remove leading +
    echo "${filters#+}"
}

# Format severity with color
format_severity() {
    local sev="$1"
    case "${sev}" in
        critical)
            echo -e "${RED}CRITICAL${NC}"
            ;;
        high)
            echo -e "${RED}HIGH${NC}"
            ;;
        medium)
            echo -e "${YELLOW}MEDIUM${NC}"
            ;;
        low)
            echo -e "${GREEN}LOW${NC}"
            ;;
        *)
            echo "${sev}"
            ;;
    esac
}

# Display visual risk prioritization matrix
display_risk_matrix() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}                    Risk Prioritization Matrix                         ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "                        RUNTIME RISK"
    echo "                   Low    Medium   High    Critical"
    echo "              ┌────────┬────────┬────────┬────────┐"
    echo "   Critical   │   🟡   │   🟠   │   🔴   │   ⛔   │  ← Fix immediately"
    echo "              ├────────┼────────┼────────┼────────┤"
    echo "S  High       │   🟢   │   🟡   │   🟠   │   🔴   │"
    echo "E             ├────────┼────────┼────────┼────────┤"
    echo "V  Medium     │   🟢   │   🟢   │   🟡   │   🟠   │"
    echo "              ├────────┼────────┼────────┼────────┤"
    echo "   Low        │   ⚪   │   🟢   │   🟢   │   🟡   │"
    echo "              └────────┴────────┴────────┴────────┘"
    echo ""
    echo "Legend: ⛔ P0  🔴 P1  🟠 P2  🟡 P3  🟢 P4  ⚪ P5"
    echo ""
}

# Display alerts table
display_alerts_table() {
    local data="$1"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${CYAN}%-8s %-12s %-12s %-35s %-15s %-15s${NC}\n" "NUMBER" "SEVERITY" "RISK" "PACKAGE" "ENVIRONMENT" "CVE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo "$data" | jq -r '.alerts[]? // empty | [
        (.number | tostring),
        .security_vulnerability.severity,
        (.deployment_context.runtime_risk // "N/A"),
        (.security_vulnerability.package.name // "N/A"),
        (.deployment_context.environment // "N/A"),
        (.security_advisory.cve_id // "N/A")
    ] | @tsv' | while IFS=$'\t' read -r number sev risk pkg env cve; do
        printf "#%-7s " "${number}"
        format_severity "${sev}"
        printf "   %-12s %-35s %-15s %-15s\n" "${risk}" "${pkg:0:35}" "${env}" "${cve}"
    done
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Display summary
display_summary() {
    local data="$1"
    
    local total=$(echo "$data" | jq '.alerts | length // 0')
    local critical=$(echo "$data" | jq '[.alerts[]? | select(.security_vulnerability.severity == "critical")] | length')
    local high=$(echo "$data" | jq '[.alerts[]? | select(.security_vulnerability.severity == "high")] | length')
    local deployed=$(echo "$data" | jq '[.alerts[]? | select(.deployment_context != null)] | length')
    local high_risk_deployed=$(echo "$data" | jq '[.alerts[]? | select(.deployment_context.runtime_risk == "high" or .deployment_context.runtime_risk == "critical")] | length')
    
    echo ""
    echo -e "${MAGENTA}Summary:${NC}"
    echo "  Total Alerts:               ${total}"
    echo -e "  Critical:                   ${RED}${critical}${NC}"
    echo -e "  High:                       ${YELLOW}${high}${NC}"
    echo "  Affecting Deployments:      ${deployed}"
    echo -e "  High-Risk Deployments:      ${RED}${high_risk_deployed}${NC}"
    echo ""
    
    if [[ "${high_risk_deployed}" -gt 0 ]]; then
        echo -e "${RED}⚠️  ACTION REQUIRED: ${high_risk_deployed} alerts affect high-risk production deployments!${NC}"
        echo ""
    fi
}

# Main execution
FILTER_QUERY=$(build_filter_query)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                    Security Alert Filter                              ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Organization: ${ORG}"
[[ -n "${REPO:-}" ]] && echo "Repository:   ${REPO}"
echo "Filters:      ${FILTER_QUERY:-none}"
echo ""

# Determine API endpoint based on alert type
if [[ -n "${REPO:-}" ]]; then
    BASE_URL="https://api.github.com/repos/${ORG}/${REPO}"
else
    BASE_URL="https://api.github.com/orgs/${ORG}"
fi

# Build the search query URL
if [[ "${ALERT_TYPE}" == "dependabot" ]] || [[ "${ALERT_TYPE}" == "all" ]]; then
    API_URL="${BASE_URL}/dependabot/alerts"
    [[ -n "${FILTER_QUERY}" ]] && API_URL="${API_URL}?q=${FILTER_QUERY}"
    
    echo -e "${YELLOW}Fetching Dependabot alerts...${NC}"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${API_URL}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [[ "$HTTP_CODE" -ge 200 ]] && [[ "$HTTP_CODE" -lt 300 ]]; then
        # Wrap array in object for consistent processing
        DATA="{\"alerts\": ${BODY}}"
        
        case "${OUTPUT_FORMAT}" in
            json)
                echo "$DATA" | jq .
                ;;
            summary)
                display_summary "$DATA"
                ;;
            table|*)
                display_risk_matrix
                display_alerts_table "$DATA"
                display_summary "$DATA"
                ;;
        esac
    else
        echo -e "${RED}❌ Failed to fetch alerts (HTTP ${HTTP_CODE})${NC}"
        echo ""
        echo "Response:"
        echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
        
        # Provide helpful message about the new filters
        if [[ "${HTTP_CODE}" == "422" ]]; then
            echo ""
            echo -e "${YELLOW}Note: Some production context filters (has:deployment, runtime-risk) require${NC}"
            echo -e "${YELLOW}linked artifacts with deployment records. See the README for setup instructions.${NC}"
        fi
        exit 1
    fi
fi

echo ""
echo -e "${CYAN}💡 Tip: Combine these new filters for maximum efficiency:${NC}"
echo "   has:deployment runtime-risk:high severity:critical"
echo ""
