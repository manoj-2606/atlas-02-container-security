# Cost Analysis — atlas-02-container-security

## Azure Resources Provisioned

| Resource | SKU / Config | Cost (per hour) | Cost (8-hour day) |
|---|---|---|---|
| Resource Group | Free | ₹0 | ₹0 |
| ACR (Basic) | Basic SKU | ~₹1.9/hr | ~₹15 |
| **Total** | | | **~₹15** |

## Why This Is the Cheapest P2 Can Be

- **No AKS** — P2 only needs a container registry, not a running cluster. AKS would add ~₹28/day for a node we never use.
- **Basic ACR over Standard** — Basic supports 10GB storage, sufficient for a portfolio image. Standard (₹60/day) adds geo-replication and higher throughput — overkill for one image.
- **No VNet** — ACR doesn't require a VNet for public push/pull. Private endpoints would add cost for no benefit here.

## Why Not az acr build?

`az acr build` builds inside ACR (cloud-side). It costs extra for build minutes and — critically — you cannot scan the image BEFORE it reaches the registry. Our security model requires the image to pass Trivy locally before it ever touches ACR.

## Comparison with P1

| | P1 (IaC Foundation) | P2 (Container Security) |
|---|---|---|
| Resources | RG + VNet + AKS + ACR | RG + ACR |
| Daily cost | ~₹50 | ~₹15 |
| Reason | Proves full infra provisioning | Only needs a registry to push to |

## FinOps Practices in This Project

1. **Cost tags on every resource** — `project`, `environment`, `team`, `cost-center`, `created-by`, `managed-by`, `destroy-by` applied via Terraform locals.
2. **destroy-by: end-of-day** — signals this infrastructure is ephemeral. Cloud governance teams look for this tag to auto-delete resources.
3. **Right-sized** — no unused resources provisioned. ACR Basic is the minimum viable SKU.
4. **Standalone Terraform over shared module** — atlas-infra-base provisions AKS + VNet alongside ACR. P2 skips the module to avoid provisioning resources it doesn't need. Right tool for the job.

## Pipeline Costs

- **Microsoft-hosted agent** — included in Azure DevOps free tier (1800 minutes/month for public projects, 1 free parallel job for private).
- **Trivy** — open source, no cost.
- **Docker build** — runs on the agent, no additional charge.

## Cleanup

```bash
# Run the destroy pipeline, or manually:
az group delete --name rg-atlas-02-dev --yes --no-wait
```

Verify: Azure Portal → Resource Groups → search "atlas-02" → should return empty.