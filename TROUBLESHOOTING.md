# Troubleshooting — atlas-02-container-security

Sections 1–7 are real incidents from the first pipeline runs. Sections 8+ are known failure modes of this design.

---

## 1. `terraform: command not found`

- **Cause:** Microsoft-hosted agents do not ship Terraform.
- **Fix:** install a pinned version before `terraform init`:
  ```bash
  curl -sLo tf.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
  sudo unzip -o tf.zip -d /usr/local/bin
  terraform version
  ```
- **Prevent:** every pipeline installs its tools explicitly.

## 2. `$(terraformVersion): command not found`

- **Cause:** the script referenced a variable that does not exist in `atlas-02-vars`. Azure DevOps leaves unresolved macros as literal text, so bash tried to run it as a command.
- **Fix:** hardcode `1.9.8` in the YAML.
- **Prevent:** only reference variables you have defined. Pin tool versions in YAML so they are reviewed in Git.

## 3. `Error building ARM Config: Authenticating using Azure CLI is only supported as a User`

- **Cause:** `ARM_OIDC_TOKEN` was not exported, so the provider fell back to Azure CLI auth, which does not work for a service principal.
- **Fix:** export all five variables in **every** step that runs Terraform (init and plan/apply):
  ```bash
  export ARM_USE_OIDC=true
  export ARM_CLIENT_ID=$servicePrincipalId
  export ARM_OIDC_TOKEN=$idToken
  export ARM_TENANT_ID=$tenantId
  export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  ```
  Requires `addSpnToEnvironment: true` on the AzureCLI@2 task.
- **Prevent:** copy the auth block from a working pipeline (atlas-01).

## 4. PyPI SSL / timeout errors during `docker build`

- **Cause:** unreliable outbound connectivity from the hosted agent to pypi.org.
- **Fix:** in the Dockerfile:
  ```dockerfile
  RUN pip install --no-cache-dir --timeout=120 --retries=10 --prefix=/install -r requirements.txt
  ```
  Re-running often lands on a healthier agent.
- **Prevent:** always set timeout and retries on external downloads in CI.

## 5. Trivy install failed (GitHub download timeout)

- **Cause:** `raw.githubusercontent.com` / GitHub releases unreachable from the agent.
- **Fix:** try the install script first, fall back to the Trivy apt repository:
  ```bash
  sudo apt-get install -y wget gnupg
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
  sudo apt-get update && sudo apt-get install -y trivy
  ```
- **Prevent:** never depend on a single download source for CI tooling.

## 6. `unable to find image "atlas-platform-app:311" locally`

- **Cause:** `Docker@2` with `command: build` but no `repository` input does not apply the `tags` you specified, so the image name Trivy looked for never existed.
- **Fix:** replace the task with a script:
  ```yaml
  - script: |
      docker build -t $(imageName):$(imageTag) -t $(imageName):latest .
    displayName: 'Docker build'
  ```
- **Prevent:** plain `docker build` is explicit, with no hidden task behavior.

## 7. YAML error: stray `inputs:` under a `script:` step

- **Cause:** converted a `task:` to `script:` and left the old `inputs:` block behind.
- **Fix:** delete the orphaned block.
- **Prevent:** when replacing a task, remove the whole task including `inputs:`.

---

## 8. Trivy finds CRITICAL CVEs — pipeline blocked

**This is the gate working.** Options:
1. Fix: update the base image tag (`python:3.12-slim` rebuilds regularly) or the vulnerable package pin.
2. Accept (only if no patch exists and it is not exploitable here): add to `.trivyignore` **with a justification comment**.
3. Never ignore silently.

## 9. `az acr login` or `docker push` returns 403 / unauthorized

- **Cause:** pipeline identity lacks `AcrPush`, or role propagation has not finished.
- **Fix:** confirm `azurerm_role_assignment.acr_push` applied; wait 1–2 minutes and re-run. Run `az acr login` and `docker push` in the **same** step so Docker auth is not lost.
- **Check:**
  ```bash
  az role assignment list --scope <acr-resource-id> --output table
  ```

## 10. ACR name already taken

- **Cause:** ACR names are globally unique. Change the suffix in `terraform/main.tf`:
  ```hcl
  acr_name = "acr${replace(var.project_name, "-", "")}${var.environment}2606"
  ```

## 11. Image larger than 100MB

```bash
docker history atlas-platform-app:<tag>
docker run --rm atlas-platform-app:<tag> pip list
```
Common causes: `COPY . .` instead of `COPY app/ ./app/`, missing `.dockerignore`, missing `--no-cache-dir`.

## 12. `$(GetACR.acrName)` is empty

- **Cause:** output variables need `name:` on the step (not just `displayName`) and `isOutput=true` in the `setvariable` command.
- **Fix:** verify both are present on the `GetACR` step.

## 13. Docs screenshot missing from GitHub

- **Cause:** `.gitignore` pattern `trivy-report.*` also matches `docs/trivy-report.png`.
- **Fix:** ignore only `trivy-report.txt` and `trivy-report.json`; then `git add docs/` and confirm with `git status`.

## 14. Destroy pipeline: cannot delete backend RG (403)

- **Cause:** `MI-ADO-API` lacks Contributor at subscription scope.
- **Fix:** grant Contributor (or a role with `Microsoft.Resources/subscriptions/resourceGroups/delete`) and re-run.

## 15. Destroy pipeline: backend RG already gone

- **Behaviour:** the pipeline detects this, skips Terraform (state is lost), and deletes `rg-atlas-02-dev` directly. If resources linger, delete the RG manually.

---

## New-pipeline checklist

- Copy the auth block from a working pipeline
- Install every tool explicitly (Terraform, Trivy), pinned versions in YAML
- `--timeout` and `--retries` on every external download
- Fallback install path for CI tools
- Plain `docker build -t` rather than `Docker@2`
- Run `terraform fmt` and pre-commit before pushing