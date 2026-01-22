# Supply Chain Security - Code-to-Cloud Traceability PoC

This PoC demonstrates GitHub's new supply chain security features for achieving **SLSA Build Level 3** security with code-to-cloud traceability.

## Overview

Based on the [GitHub Changelog announcement](https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/), this PoC implements:

### 1. Artifact Attestations
Cryptographically bind build artifacts to their source repository and build workflow using GitHub's `attest-build-provenance` action.

### 2. Storage Records
Track where your artifacts (containers, binaries) are stored in package registries via the new REST API.

### 3. Deployment Records
Capture where artifacts are deployed and runtime risk factors (internet exposure, sensitive data processing).

### 4. Production-Context Security Filtering
Filter Dependabot and code scanning alerts based on what's actually deployed in production.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GitHub Actions Workflow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────────────────┐ │
│  │   Build     │───>│ Attest Artifact  │───>│ Push to Registry            │ │
│  │  (Binary/   │    │ (SLSA L3 Prov.)  │    │ + Create Storage Record     │ │
│  │  Container) │    └──────────────────┘    └─────────────────────────────┘ │
│  └─────────────┘                                         │                   │
└──────────────────────────────────────────────────────────│───────────────────┘
                                                           │
                                                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GitHub Artifact View                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Artifact: openbao:v2.1.0-rc1                                            ││
│  │ ├── Attestations: build-provenance, sbom, vulnerability-scan            ││
│  │ ├── Storage: ghcr.io/openbao/openbao:v2.1.0-rc1                        ││
│  │ └── Deployments: staging (low risk), production (high risk - exposed)  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                                           │
                                                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Security Alert Filtering                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Filters: has:deployment runtime-risk:high artifact-registry:ghcr.io    ││
│  │ Result: 3 critical CVEs affecting production workloads                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

## Files in this PoC

| File | Description |
|------|-------------|
| `.github/workflows/build-attest.yml` | GitHub Actions workflow with artifact attestation |
| `scripts/create-storage-record.sh` | Create storage records via REST API |
| `scripts/create-deployment-record.sh` | Create deployment records via REST API |
| `scripts/query-linked-artifacts.sh` | Query linked artifacts and their metadata |
| `scripts/filter-security-alerts.sh` | Filter security alerts by production context |
| `examples/api-payloads/` | Example JSON payloads for the APIs |

## Quick Start

### Prerequisites
- GitHub repository with Actions enabled
- `GITHUB_TOKEN` with appropriate permissions
- Container registry (GHCR, Docker Hub, or JFrog Artifactory)

### 1. Setup the Workflow

Copy the workflow file to your repository:

```bash
cp .github/workflows/build-attest.yml <your-repo>/.github/workflows/
```

### 2. Build with Attestation

The workflow automatically:
- Builds your container/binary
- Creates SLSA Build Level 3 provenance attestation
- Pushes to your registry
- Creates a storage record linking the artifact to GitHub

### 3. Add Deployment Records

When deploying to production, call the deployment record API:

```bash
./scripts/create-deployment-record.sh \
  --artifact-digest "sha256:abc123..." \
  --environment "production" \
  --runtime-risk "high" \
  --internet-exposed "true"
```

### 4. Filter Security Alerts

Query alerts affecting your production deployments:

```bash
./scripts/filter-security-alerts.sh \
  --filter "has:deployment runtime-risk:high"
```

## Security Benefits

| Feature | Benefit |
|---------|---------|
| **SLSA Build Level 3** | Cryptographic proof artifacts came from trusted build |
| **Storage Records** | Track artifact locations across registries |
| **Deployment Records** | Know what's running in production |
| **Runtime Risk Tagging** | Prioritize by actual exposure |
| **Alert Filtering** | Focus on vulnerabilities that matter |

## API Reference

### Storage Record Endpoint
```
POST /orgs/{org}/packages/{package_type}/{package_name}/versions/{version_id}/storage-records
```

### Deployment Record Endpoint
```
POST /orgs/{org}/packages/{package_type}/{package_name}/versions/{version_id}/deployment-records
```

### Query Linked Artifacts
```
GET /orgs/{org}/linked-artifacts
```

## Partner Integrations

- **Microsoft Defender for Cloud**: Automatically sends deployment and runtime data
- **JFrog Artifactory**: Provides storage and promotion context

## References

- [GitHub Blog Announcement](https://github.blog/changelog/2026-01-20-strengthen-your-supply-chain-with-code-to-cloud-traceability-and-slsa-build-level-3-security/)
- [About Linked Artifacts (GitHub Docs)](https://docs.github.com/en/code-security/supply-chain-security/about-linked-artifacts)
- [Artifact Metadata API Reference](https://docs.github.com/en/rest/packages/artifact-metadata)
- [SLSA Framework](https://slsa.dev/)
