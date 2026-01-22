# SLSA L3 & Artifact Metadata Experiment

Hands-on scripts to understand GitHub's SLSA Build Level 3 and the new artifact metadata APIs.

## Prerequisites

- GitHub CLI (`gh`) authenticated
- Docker installed
- `jq` for JSON parsing
- Optional: `cosign` for alternative verification

## Quick Start

```bash
# 1. Setup and check prerequisites
./01-setup.sh

# 2. Create a test repository (PUBLIC - required for Sigstore)
./02-create-test-repo.sh

# 3. Wait for workflow to complete, then verify attestation
./03-verify-attestation.sh YOUR_USER/slsa-l3-experiment

# 4. Test the new metadata APIs (may not be available yet)
./04-test-metadata-apis.sh YOUR_USER/slsa-l3-experiment

# 5. Understand L2 vs L3 difference
./05-compare-l2-vs-l3.sh
```

## What You'll Learn

### 1. SLSA Build Level 3 Structure

The key insight is that **reusable workflows provide build isolation**:

```
ci.yml (caller)                     slsa-l3-reusable.yml (reusable)
┌─────────────────────┐            ┌─────────────────────┐
│ jobs:               │            │ on: workflow_call   │
│   build:            │───────────▶│ jobs:               │
│     uses: ...       │   inputs   │   build:            │
│     with:           │   only     │     - Build         │
│       image: myapp  │            │     - Attest ◄──────┼── ISOLATED
└─────────────────────┘            └─────────────────────┘
```

The caller can only pass declared `inputs` — they **cannot modify** the build or attestation logic.

### 2. Verification Levels

```bash
# SLSA L2: Just checks signature exists
gh attestation verify oci://IMAGE --owner OWNER

# SLSA L3: Checks it came from specific trusted workflow
gh attestation verify oci://IMAGE --owner OWNER \
    --signer-workflow OWNER/REPO/.github/workflows/slsa-l3-reusable.yml
```

### 3. Artifact Metadata APIs (New in Jan 2026)

These are **separate from SLSA** — they're operational metadata:

| API | Purpose |
|-----|---------|
| Storage Records | Where artifacts are stored (GHCR, JFrog, etc.) |
| Deployment Records | Where artifacts are deployed + runtime risk |
| Linked Artifacts | Unified view of artifacts with metadata |

These enable the new security alert filters:
- `has:deployment`
- `runtime-risk:high`
- `artifact-registry:ghcr.io`

## File Structure

```
experiment/
├── 01-setup.sh              # Check prerequisites
├── 02-create-test-repo.sh   # Create test repo with SLSA L3 workflow
├── 03-verify-attestation.sh # Verify attestations (L2 and L3)
├── 04-test-metadata-apis.sh # Test new artifact metadata APIs
├── 05-compare-l2-vs-l3.sh   # Visual explanation of the difference
└── README.md                # This file
```

## Common Issues

### "Attestation verification failed"

- Make sure the workflow completed successfully
- Check that the repository is **public** (required for Sigstore)
- Verify you're using the correct digest

### "404 Not Found" on metadata APIs

- These APIs are from the Jan 2026 announcement
- May require specific GitHub plan or feature flags
- May only work with partner integrations (Defender for Cloud, JFrog)

### "Permission denied"

- Check `gh auth status`
- Ensure token has `packages:write` and `attestations:write` scopes

## References

- [GitHub Changelog: SLSA Build Level 3](https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/)
- [GitHub Docs: SLSA L3 with Reusable Workflows](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-and-reusable-workflows-to-achieve-slsa-v1-build-level-3)
- [SLSA v1.2 Specification](https://slsa.dev/spec/v1.2/)
