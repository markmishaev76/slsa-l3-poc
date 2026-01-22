#!/bin/bash
# Create a test repository for SLSA experimentation
# This creates a PUBLIC repo (required for Sigstore verification)

set -euo pipefail

REPO_NAME="${1:-slsa-l3-experiment}"
GITHUB_USER=$(gh api user --jq '.login')

echo "═══════════════════════════════════════════════════════════════"
echo "  Creating Test Repository: ${GITHUB_USER}/${REPO_NAME}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if repo exists
if gh repo view "${GITHUB_USER}/${REPO_NAME}" &> /dev/null; then
    echo "⚠️  Repository already exists"
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gh repo delete "${GITHUB_USER}/${REPO_NAME}" --yes
        sleep 2
    else
        echo "Using existing repository"
        exit 0
    fi
fi

# Create public repo (required for Sigstore)
echo "Creating public repository..."
gh repo create "${REPO_NAME}" \
    --public \
    --description "SLSA Build Level 3 Experiment" \
    --clone

cd "${REPO_NAME}"

# Copy workflow files
echo "Copying workflow files..."
mkdir -p .github/workflows

cat > .github/workflows/slsa-l3-reusable.yml << 'WORKFLOW'
# SLSA Level 3 Reusable Workflow
name: SLSA L3 Build Service

on:
  workflow_call:
    inputs:
      image_name:
        required: true
        type: string
    outputs:
      digest:
        value: ${{ jobs.build.outputs.digest }}

permissions:
  contents: read
  packages: write
  id-token: write
  attestations: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.build.outputs.digest }}

    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ inputs.image_name }}
          tags: type=sha

      - id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}

      # SLSA L3: Attestation in reusable workflow
      - uses: actions/attest-build-provenance@v2
        with:
          subject-name: ghcr.io/${{ inputs.image_name }}
          subject-digest: ${{ steps.build.outputs.digest }}
          push-to-registry: true
WORKFLOW

cat > .github/workflows/ci.yml << 'WORKFLOW'
name: CI
on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write
  attestations: write

jobs:
  build:
    uses: ./.github/workflows/slsa-l3-reusable.yml
    with:
      image_name: ${{ github.repository }}
WORKFLOW

# Create simple Dockerfile
cat > Dockerfile << 'DOCKERFILE'
FROM alpine:3.19
RUN echo "SLSA L3 Test" > /test.txt
CMD ["cat", "/test.txt"]
DOCKERFILE

# Create README
cat > README.md << 'README'
# SLSA L3 Experiment

This repository demonstrates SLSA Build Level 3 with GitHub artifact attestations.

## How it works

1. `ci.yml` (caller) triggers `slsa-l3-reusable.yml` (reusable)
2. The reusable workflow builds and attests the container
3. Attestation is pushed to the registry with the image

## Verify

```bash
gh attestation verify oci://ghcr.io/YOUR_USER/slsa-l3-experiment@sha256:... --owner YOUR_USER
```
README

# Commit and push
git add .
git commit -m "Initial SLSA L3 experiment setup"
git push -u origin main

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Repository Created!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Repository: https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo ""
echo "The workflow will run automatically. Check:"
echo "  https://github.com/${GITHUB_USER}/${REPO_NAME}/actions"
echo ""
echo "Once complete, verify with:"
echo "  ./03-verify-attestation.sh ${GITHUB_USER}/${REPO_NAME}"
echo ""
