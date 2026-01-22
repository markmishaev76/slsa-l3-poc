#!/bin/bash
# Experiment Setup Script
# Run this first to set up your environment

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  GitHub SLSA L3 & Artifact Metadata Experiment Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check prerequisites
check_prereq() {
    if command -v "$1" &> /dev/null; then
        echo "✅ $1 installed"
        return 0
    else
        echo "❌ $1 not found - please install it"
        return 1
    fi
}

echo "Checking prerequisites..."
check_prereq gh
check_prereq docker
check_prereq jq
check_prereq cosign || echo "   (optional - for local verification)"
echo ""

# Check GitHub CLI auth
echo "Checking GitHub authentication..."
if gh auth status &> /dev/null; then
    echo "✅ GitHub CLI authenticated"
    echo "   User: $(gh api user --jq '.login')"
else
    echo "❌ Not authenticated. Run: gh auth login"
    exit 1
fi
echo ""

# Export required variables
echo "Setting up environment variables..."
export GITHUB_USER=$(gh api user --jq '.login')
export GITHUB_TOKEN=$(gh auth token)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Setup Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Create a test repo:  ./02-create-test-repo.sh"
echo "  2. Build with SLSA:     Push to the repo to trigger workflow"
echo "  3. Verify attestation:  ./03-verify-attestation.sh"
echo "  4. Test metadata APIs:  ./04-test-metadata-apis.sh"
echo ""
