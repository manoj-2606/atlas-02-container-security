# Troubleshooting — atlas-02-container-security

## 1. Docker Build Fails — "COPY requirements.txt: file not found"

**Cause:** `requirements.txt` is not at the repo root, or `.dockerignore` is excluding it.

**Fix:**
```bash
# Verify file exists at root (not inside app/)
ls -la requirements.txt

# Check .dockerignore doesn't exclude it
grep "requirements" .dockerignore
```

## 2. Trivy Scan Fails — "unable to initialize a scanner"

**Cause:** Trivy can't find the local Docker image (name/tag mismatch).

**Fix:**
```bash
# List local images
docker images | grep atlas-platform-app

# Ensure the image name matches what scan-trivy.sh expects
# Usage: ./scripts/scan-trivy.sh "atlas-platform-app:"
```

## 3. Trivy Finds CRITICAL CVEs — Pipeline Blocked

**This is working as designed.** The pipeline is supposed to fail.

**Options:**
1. **Fix it** — update the base image in Dockerfile to a patched version:
   ```dockerfile
   FROM python:3.12-slim AS builder
   # Try a newer slim tag or switch to alpine
   ```
2. **Accept it** — if no patch exists and it doesn't apply to your use case, add to `.trivyignore` with justification:
   ```
   CVE-2024-XXXXX  # No patch available, not exploitable in our context (no network listener on affected lib)
   ```
3. **Never silently skip** — undocumented ignores are a security antipattern.

## 4. az acr login Fails — "403 Forbidden"

**Cause:** Pipeline identity doesn't have `AcrPush` role on the ACR.

**Fix:** Verify the role assignment exists in Terraform:
```hcl
resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

If Terraform already applied but push still fails, Azure role propagation can take 1-2 minutes. Re-run the pipeline.

**Manual check:**
```bash
# Get the service principal's object ID
az ad sp show --id  --query id -o tsv

# Check role assignments on ACR
az role assignment list --scope  --output table
```

## 5. docker push Fails — "unauthorized: authentication required"

**Cause:** `az acr login` token expired (valid for ~3 hours) or wasn't called before push.

**Fix:** Ensure `az acr login --name ` runs in the same pipeline step as `docker push`. Splitting across steps can lose the Docker auth context.

## 6. ACR Name Conflict — "already exists"

**Cause:** ACR names are globally unique across all Azure tenants. `acratlas02dev` might be taken.

**Fix:** Change the naming in `terraform/main.tf`:
```hcl
locals {
  acr_name = "acr${replace(var.project_name, "-", "")}${var.environment}2606"
}
```
Append your unique suffix (e.g., last 4 digits of your phone number).

## 7. Image Size > 100MB

**Cause:** Multi-stage build not working correctly, or unnecessary files copied in.

**Debug:**
```bash
# Check layer sizes
docker history atlas-platform-app:

# Check what's in the image
docker run --rm -it atlas-platform-app: ls -la /app/
docker run --rm -it atlas-platform-app: pip list
```

**Common culprits:**
- `.dockerignore` missing → `.git/` copied into image
- `COPY . .` instead of `COPY app/ ./app/` → terraform files in image
- `--no-cache-dir` missing from pip install → pip cache inflates size

## 8. SBOM Generation Fails — "no packages found"

**Cause:** Trivy can't read the image filesystem.

**Fix:**
```bash
# Verify image exists locally
docker images | grep atlas-platform-app

# Run SBOM manually to see full error
trivy image --format spdx-json atlas-platform-app:
```

## 9. Pipeline Variable $(GetACR.acrName) Is Empty

**Cause:** The `GetACR` step's output variable didn't propagate. Usually means the step name doesn't match.

**Fix:** Verify the step has `name: GetACR` (not just `displayName`). In ADO, `$(stepName.variableName)` requires the `name` property on the task, not `displayName`.

## 10. Terraform State Lock — "Error acquiring the state lock"

**Same fix as P1:**
```bash
# Find the lock
az storage blob lease break \
  --blob-name atlas-02.tfstate \
  --container-name tfstate \
  --account-name atlastfstate2606

# Then re-run the pipeline
```