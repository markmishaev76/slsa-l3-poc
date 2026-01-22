#!/bin/bash
# Create Deployment Record for Linked Artifacts
#
# Deployment records capture where an artifact is deployed and runtime risk factors
# such as whether the workload is exposed to the internet or processes sensitive data.
#
# Reference: https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create a deployment record linking an artifact to its deployment location with runtime risk context.

OPTIONS:
    -o, --org                   GitHub organization name (required)
    -p, --package               Package name (required)
    -t, --package-type          Package type: container, npm, maven, etc. (default: container)
    -d, --digest                Artifact digest (sha256:...) (required)
    -e, --environment           Deployment environment: production, staging, dev (required)
    
    Runtime Risk Options:
    --internet-exposed          Whether workload is exposed to internet (true/false)
    --processes-sensitive-data  Whether workload processes sensitive data (true/false)
    --risk-level                Overall risk level: low, medium, high, critical
    
    Deployment Context:
    --cloud-provider            Cloud provider: aws, gcp, azure, kubernetes, etc.
    --cluster-name              Kubernetes cluster or compute resource name
    --namespace                 Kubernetes namespace
    --region                    Cloud region
    --replicas                  Number of replicas running
    
    -h, --help                  Show this help message

EXAMPLES:
    # Production deployment with high risk (internet exposed)
    $(basename "$0") -o openbao -p openbao -d sha256:abc123 \\
        -e production \\
        --internet-exposed true \\
        --processes-sensitive-data true \\
        --risk-level high \\
        --cloud-provider kubernetes \\
        --cluster-name prod-cluster

    # Staging deployment with lower risk
    $(basename "$0") -o openbao -p openbao -d sha256:abc123 \\
        -e staging \\
        --internet-exposed false \\
        --risk-level low

ENVIRONMENT:
    GITHUB_TOKEN    GitHub token with packages:write permission (required)
EOF
}

# Default values
PACKAGE_TYPE="container"
INTERNET_EXPOSED="false"
PROCESSES_SENSITIVE_DATA="false"
RISK_LEVEL="medium"
CLOUD_PROVIDER=""
CLUSTER_NAME=""
NAMESPACE=""
REGION=""
REPLICAS=""

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
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --internet-exposed)
            INTERNET_EXPOSED="$2"
            shift 2
            ;;
        --processes-sensitive-data)
            PROCESSES_SENSITIVE_DATA="$2"
            shift 2
            ;;
        --risk-level)
            RISK_LEVEL="$2"
            shift 2
            ;;
        --cloud-provider)
            CLOUD_PROVIDER="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --replicas)
            REPLICAS="$2"
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
if [[ -z "${ORG:-}" ]] || [[ -z "${PACKAGE:-}" ]] || [[ -z "${DIGEST:-}" ]] || [[ -z "${ENVIRONMENT:-}" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    usage
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo -e "${RED}Error: GITHUB_TOKEN environment variable is required${NC}"
    exit 1
fi

# Validate risk level
case "${RISK_LEVEL}" in
    low|medium|high|critical) ;;
    *)
        echo -e "${RED}Error: Invalid risk level '${RISK_LEVEL}'. Must be: low, medium, high, critical${NC}"
        exit 1
        ;;
esac

# Validate environment
case "${ENVIRONMENT}" in
    production|staging|development|dev|test|qa) ;;
    *)
        echo -e "${YELLOW}Warning: Non-standard environment '${ENVIRONMENT}'${NC}"
        ;;
esac

# Build JSON payload
build_payload() {
    cat << EOF
{
    "environment": "${ENVIRONMENT}",
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "runtime_risk": {
        "internet_exposed": ${INTERNET_EXPOSED},
        "processes_sensitive_data": ${PROCESSES_SENSITIVE_DATA},
        "risk_level": "${RISK_LEVEL}"
    }$(
    # Add optional fields
    [[ -n "${CLOUD_PROVIDER}" ]] && echo ",
    \"cloud_provider\": \"${CLOUD_PROVIDER}\""
    [[ -n "${CLUSTER_NAME}" ]] && echo ",
    \"cluster_name\": \"${CLUSTER_NAME}\""
    [[ -n "${NAMESPACE}" ]] && echo ",
    \"namespace\": \"${NAMESPACE}\""
    [[ -n "${REGION}" ]] && echo ",
    \"region\": \"${REGION}\""
    [[ -n "${REPLICAS}" ]] && echo ",
    \"replicas\": ${REPLICAS}"
)
}
EOF
}

# Display risk badge
display_risk_badge() {
    case "${RISK_LEVEL}" in
        low)
            echo -e "${GREEN}🟢 LOW RISK${NC}"
            ;;
        medium)
            echo -e "${YELLOW}🟡 MEDIUM RISK${NC}"
            ;;
        high)
            echo -e "${RED}🟠 HIGH RISK${NC}"
            ;;
        critical)
            echo -e "${RED}🔴 CRITICAL RISK${NC}"
            ;;
    esac
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                    Creating Deployment Record                               ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📦 Package:     ${ORG}/${PACKAGE} (${PACKAGE_TYPE})"
echo "🔑 Digest:      ${DIGEST}"
echo "🌍 Environment: ${ENVIRONMENT}"
echo ""
echo "Runtime Risk Assessment:"
display_risk_badge
echo "  • Internet Exposed:         ${INTERNET_EXPOSED}"
echo "  • Processes Sensitive Data: ${PROCESSES_SENSITIVE_DATA}"
[[ -n "${CLOUD_PROVIDER}" ]] && echo "  • Cloud Provider:           ${CLOUD_PROVIDER}"
[[ -n "${CLUSTER_NAME}" ]] && echo "  • Cluster:                  ${CLUSTER_NAME}"
[[ -n "${NAMESPACE}" ]] && echo "  • Namespace:                ${NAMESPACE}"
[[ -n "${REGION}" ]] && echo "  • Region:                   ${REGION}"
[[ -n "${REPLICAS}" ]] && echo "  • Replicas:                 ${REPLICAS}"
echo ""

# API endpoint
API_URL="https://api.github.com/orgs/${ORG}/packages/${PACKAGE_TYPE}/${PACKAGE}/versions/${DIGEST}/deployment-records"

# Build and send request
PAYLOAD=$(build_payload)

echo -e "${YELLOW}Sending request to GitHub API...${NC}"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "${API_URL}" \
    -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo ""
if [[ "$HTTP_CODE" -ge 200 ]] && [[ "$HTTP_CODE" -lt 300 ]]; then
    echo -e "${GREEN}✅ Deployment record created successfully!${NC}"
    echo ""
    echo "This artifact is now linked to its ${ENVIRONMENT} deployment."
    echo "You can now filter security alerts using:"
    echo ""
    echo -e "  ${BLUE}has:deployment runtime-risk:${RISK_LEVEL}${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
    echo -e "${RED}❌ Failed to create deployment record (HTTP ${HTTP_CODE})${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi
