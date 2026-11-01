# atlas-02-container-security

Container security and image hardening for the Atlas Platform portfolio. Takes a Python FastAPI application, builds a production-grade Docker image, scans it for vulnerabilities, generates a software bill of materials (SBOM), and pushes only clean images to Azure Container Registry.

**Part of the [Atlas Platform Portfolio](https://github.com/manoj-2606) — 11 production-grade Azure DevOps projects.**

---

## What This Project Proves

1. **Multi-stage Docker builds** — builder stage installs dependencies, production stage copies only what's needed. Final image under 100MB.
2. **Non-root containers** — application runs as `atlas` user with no shell and no home directory. Minimal attack surface.
3. **CVE scanning gate** — Trivy scans every image before it reaches ACR. Zero CRITICAL CVEs allowed. Pipeline fails if any are found.
4. **Software Bill of Materials** — every image gets an SBOM in SPDX JSON format. Full supply chain visibility — you know exactly what's inside your container.
5. **Secure registry access** — ACR admin disabled. Pipeline authenticates via OIDC Workload Identity (zero stored credentials). AcrPush role granted via Terraform.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ADO Pipeline (ubuntu-latest)              │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │ Docker   │    │ Trivy Scan   │    │ SBOM Generation   │  │
│  │ Build    │───►│              │───►│                    │  │
│  │          │    │ CRITICAL = 0?│    │ SPDX JSON format   │  │
│  │ Multi-   │    │  YES → next  │    │ Package inventory  │  │
│  │ stage    │    │  NO  → FAIL  │    │                    │  │
│  │ Non-root │    └──────────────┘    └───────────────────┘  │
│  └──────────┘                                               │
│       │                                                      │
│       │ Only if scan passes                                  │
│       ▼                                                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  az acr login (OIDC — no stored credentials)         │   │
│  │  docker push → ACR Basic (acratlas02dev.azurecr.io)  │   │
│  │  az acr repository show-tags (verify)                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PublishPipelineArtifact: trivy-report + sbom.json    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

Infrastructure (Terraform):
┌────────────────────────────────────────┐
│  Resource Group: rg-atlas-02-dev       │
│  ACR: acratlas02dev (Basic, no admin)  │
│  Role: AcrPush → pipeline identity     │
│  Tags: project, env, team, cost-center │
└────────────────────────────────────────┘
```

---

## Pipeline Stages

| Stage | What Happens | Task Types |
|---|---|---|
| Bootstrap | Creates Terraform backend storage (idempotent) | AzureCLI@2 |
| Infra | Terraform provisions RG + ACR + role assignment | AzureCLI@2 (TF commands) |
| Container_Security | Build → Scan → SBOM → Push → Verify → Publish | Docker@2, script, AzureCLI@2, PublishPipelineArtifact@1 |

**How this differs from P1:** P1 was Terraform-heavy with PowerShell validation scripts. P2 is Docker-heavy with security scanning, `az acr` commands, scan report parsing, and pipeline artifact publishing.

---

## Security Controls

| Control | Implementation | Why |
|---|---|---|
| Non-root user | `USER atlas` in Dockerfile | Compromised container can't escalate to root |
| Multi-stage build | Builder → Production separation | No pip, cache, or build tools in final image |
| CVE gate | Trivy `--severity CRITICAL` with exit code check | Zero CRITICAL CVEs reach any registry |
| SBOM | Trivy `--format spdx-json` | Full visibility into container contents — auditable supply chain |
| No stored credentials | OIDC service connection + `AcrPush` role | Pipeline authenticates via token exchange, not secrets |
| ACR admin disabled | `admin_enabled = false` | No username/password for registry — identity-based access only |
| Secrets scanning | gitleaks pre-commit hook | Credentials never reach Git history |
| Layer optimization | `COPY requirements.txt` before `COPY app/` | Dependencies cached, app changes don't rebuild deps layer |

---

## Dockerfile Explained

```dockerfile
# Stage 1 — install dependencies into /install (thrown away after)
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2 — clean production image
FROM python:3.12-slim
RUN groupadd -r atlas && useradd -r -g atlas -d /app -s /sbin/nologin atlas
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/
USER atlas
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Result:** Under 100MB. No pip. No cache. No root. No shell for the app user.

---

## What is an SBOM?

**Software Bill of Materials** — a list of every package, library, and dependency inside your container image. Like an ingredients list on food packaging.

**Why it matters:**
- When a new CVE is announced (e.g., "log4j"), you can instantly check: "Do any of my images contain this library?" without re-scanning everything.
- Compliance teams in EU companies require SBOMs for production workloads (supply chain security regulations).
- Generated with: `trivy image --format spdx-json`

**Interview angle:** "I generate an SBOM for every image. If a zero-day drops tomorrow, I can grep my SBOMs and know within minutes which images are affected."

---

## Prerequisites

1. Azure Pay-As-You-Go subscription
2. ADO project `Atlas-Platform` with service connection `MI-ADO-API` (OIDC)
3. Variable group `atlas-02-vars`:
   - `serviceConnection` = `MI-ADO-API`
   - `backendResourceGroup` = `rg-atlas-tfstate`
   - `backendStorageAccount` = `atlastfstate2606`
   - `backendContainer` = `tfstate`
   - `backendKey` = `atlas-02.tfstate`
   - `location` = `centralindia`
4. ADO environments: `atlas-02-deploy`, `atlas-02-destroy`

## Deploy

1. Push code to ADO repo (`atlas-02-container-security`)
2. Create pipeline from `azure-pipelines.yml`
3. Run pipeline → approve at Infra stage → Container_Security runs automatically
4. Check pipeline artifacts tab → download `security-reports` (trivy-report + sbom.json)

## Cleanup

Run the destroy pipeline (`azure-pipelines-destroy.yml`), or manual fallback:

```bash
az group delete --name rg-atlas-02-dev --yes --no-wait
```

Verify: Azure Portal → Resource Groups → search "atlas-02" → should return empty.

---

## Cost

~₹15 per project day (ACR Basic only, no AKS). Full breakdown: [COST.md](COST.md)

---

## Troubleshooting

Common issues and fixes: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

Covers: Docker build failures, Trivy scan blocks, ACR auth errors, image size debugging, SBOM issues, state lock recovery.

---

## Repo Structure

```
atlas-02-container-security/
├── terraform/
│   ├── main.tf                # RG + ACR + AcrPush role assignment
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   └── environments/
│       └── dev.tfvars
├── app/
│   ├── __init__.py
│   ├── main.py                # FastAPI app (from atlas-platform-app)
│   ├── metrics.py             # Prometheus metrics
│   └── simulator.py           # Failure/load simulation
├── scripts/
│   ├── scan-trivy.sh          # CVE scan — fails on CRITICAL
│   └── generate-sbom.sh       # SBOM in SPDX JSON format
├── requirements.txt
├── Dockerfile                 # Multi-stage, non-root, < 100MB
├── .dockerignore
├── .trivyignore               # Accepted CVEs (with justification)
├── azure-pipelines.yml        # Build → Scan → Push pipeline
├── azure-pipelines-destroy.yml
├── .pre-commit-config.yaml    # gitleaks
├── .gitignore
├── docs/
│   ├── architecture.png       # Pipeline flow diagram
│   ├── image-layers.png       # docker history screenshot
│   ├── trivy-report.png       # Clean scan screenshot
│   └── sbom-sample.json       # Sample SBOM output
├── COST.md
├── TROUBLESHOOTING.md
└── README.md
```

---

## What This Project Says in Interviews

> "I enforce zero critical CVEs in every image before it reaches any registry.
> Every container runs as non-root. Every image has an SBOM.
> The pipeline authenticates via OIDC — zero stored credentials.
> ACR admin is disabled — identity-based access only.
> If a zero-day drops, I can check my SBOMs in minutes."

---

## Author

**Manoj Kumar R** — Senior DevOps / Platform Engineer
[GitHub](https://github.com/manoj-2606) · [LinkedIn](https://linkedin.com/in/manoj2606)