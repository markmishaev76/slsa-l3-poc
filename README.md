# GitHub SLSA L3 & Artifact Metadata - Analysis & Experimentation

[![AI Harness Scorecard](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmarkmishaev76%2Fslsa-l3-poc%2Fmain%2Fscorecard-badge.json)](scorecard-report.md)

Analysis and hands-on experimentation with GitHub's [January 2026 announcement](https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/) on code-to-cloud traceability and SLSA Build Level 3.

## TL;DR - What GitHub Actually Shipped

| Feature | What It Does | SLSA Related? |
|---------|--------------|---------------|
| **Artifact Attestations** | Cryptographic provenance (Sigstore) | ✅ Yes - enables SLSA L2/L3 |
| **Storage Records API** | Track where artifacts are stored | ❌ No - operational metadata |
| **Deployment Records API** | Track where artifacts are deployed + runtime risk | ❌ No - operational metadata |
| **Alert Filters** | `has:deployment`, `runtime-risk:high` | ❌ No - prioritization tool |

**Key Insight:** The article conflates two separate features. Only artifact attestations relate to SLSA. The metadata APIs are operational tools for vulnerability prioritization.

## SLSA Build Level 3 - The Reality

### What's Required for L3

SLSA L3 requires **build isolation** — the build process must be tamper-resistant. On GitHub, this means using **reusable workflows**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SLSA BUILD LEVEL 2                           │
│              (Single workflow - NO isolation)                   │
├─────────────────────────────────────────────────────────────────┤
│   .github/workflows/build.yml                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  jobs:                                                   │   │
│   │    build:                                                │   │
│   │      steps:                                              │   │
│   │        - name: Build              ◄── Can be modified    │   │
│   │        - name: Attest             ◄── Can be modified    │   │
│   └─────────────────────────────────────────────────────────┘   │
│   ⚠️  Anyone with write access can modify both build & attest   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    SLSA BUILD LEVEL 3                           │
│              (Reusable workflow - ISOLATED)                     │
├─────────────────────────────────────────────────────────────────┤
│   ci.yml (CALLER)              slsa-l3-reusable.yml (REUSABLE)  │
│   ┌───────────────────┐       ┌───────────────────────────────┐ │
│   │ uses: ...reusable │──────▶│ on: workflow_call             │ │
│   │ with:             │inputs │   steps:                      │ │
│   │   image: myapp    │ only  │     - Build  ◄── ISOLATED     │ │
│   └───────────────────┘       │     - Attest ◄── ISOLATED     │ │
│                               └───────────────────────────────┘ │
│   ✅ Caller cannot modify build/attestation logic               │
└─────────────────────────────────────────────────────────────────┘
```

### Verification Commands

```bash
# SLSA L2: Checks signature exists
gh attestation verify oci://IMAGE --owner OWNER

# SLSA L3: Checks it came from specific trusted workflow
gh attestation verify oci://IMAGE --owner OWNER \
    --signer-workflow OWNER/REPO/.github/workflows/slsa-l3-reusable.yml
```

## Repository Structure

```
.
├── .github/workflows/
│   ├── slsa-l3-reusable.yml    # ✅ SLSA L3 reusable workflow (isolated)
│   ├── ci.yml                   # Caller workflow (triggers reusable)
│   └── build-attest.yml         # ⚠️  Original L2-only workflow
├── experiment/                   # Hands-on experimentation scripts
│   ├── 01-setup.sh              # Check prerequisites
│   ├── 02-create-test-repo.sh   # Create test repo with SLSA L3
│   ├── 03-verify-attestation.sh # Verify attestations (L2 and L3)
│   ├── 04-test-metadata-apis.sh # Test new metadata APIs
│   └── 05-compare-l2-vs-l3.sh   # Visual L2 vs L3 comparison
├── scripts/                      # API interaction scripts
│   ├── create-storage-record.sh
│   ├── create-deployment-record.sh
│   ├── query-linked-artifacts.sh
│   └── filter-security-alerts.sh
├── examples/api-payloads/        # Example JSON payloads
└── Dockerfile                    # Simple test container
```

## Quick Start - Experimentation

### Prerequisites

- GitHub CLI (`gh`) authenticated
- Docker installed
- `jq` for JSON parsing

### Run the Experiment

```bash
cd experiment

# 1. Check prerequisites
./01-setup.sh

# 2. Create a test repo (PUBLIC required for Sigstore)
./02-create-test-repo.sh

# 3. Wait ~2 min for workflow, then verify
./03-verify-attestation.sh YOUR_USER/slsa-l3-experiment

# 4. Test the new metadata APIs
./04-test-metadata-apis.sh YOUR_USER/slsa-l3-experiment
```

## Artifact Metadata APIs (Not SLSA)

These APIs provide **operational visibility**, not security guarantees:

### Storage Records
```bash
POST /orgs/{org}/packages/container/{package}/versions/{digest}/storage-records

{
  "registry_url": "ghcr.io/org/package:v1.0.0",
  "registry_name": "GitHub Container Registry"
}
```

### Deployment Records
```bash
POST /orgs/{org}/packages/container/{package}/versions/{digest}/deployment-records

{
  "environment": "production",
  "runtime_risk": {
    "internet_exposed": true,
    "processes_sensitive_data": true,
    "risk_level": "high"
  }
}
```

### New Security Alert Filters
- `has:deployment` — Alerts affecting deployed artifacts
- `runtime-risk:high` — Filter by risk level
- `artifact-registry:ghcr.io` — Filter by registry

## SLSA v1.2 Conformance Analysis

| Requirement | GitHub Status | Notes |
|-------------|---------------|-------|
| **Build L1** (Provenance exists) | ✅ | `attest-build-provenance` action |
| **Build L2** (Signed provenance) | ✅ | Sigstore signing |
| **Build L3** (Hardened builds) | ⚠️ Conditional | Requires reusable workflows |
| **Hermetic builds** | ❌ | Not enforced |
| **Reproducible builds** | ❌ | Not enforced |
| **Source Track** | ❌ | Not addressed |

## Comparison: GitHub vs GitLab

| Aspect | GitHub | GitLab |
|--------|--------|--------|
| **Provenance Generation** | Client-side (runner) | Server-side (control plane) |
| **L3 Isolation** | User must configure reusable workflows | Automatic (server-side) |
| **Private Projects** | ✅ Supported | ❌ Public only (current) |
| **Status** | ✅ GA | ⚠️ Experiment |
| **Self-Managed** | N/A | Limited (hardcoded Sigstore) |

## References

- [GitHub Changelog Announcement](https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/)
- [GitHub Docs: SLSA L3 with Reusable Workflows](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-and-reusable-workflows-to-achieve-slsa-v1-build-level-3)
- [SLSA v1.2 Specification](https://slsa.dev/spec/v1.2/)
- [Sigstore Documentation](https://docs.sigstore.dev/)
