#!/bin/bash
set -euo pipefail

# Usage: scan-trivy.sh  [report-dir]
IMAGE_NAME="${1:?Usage: scan-trivy.sh  [report-dir]}"
REPORT_DIR="${2:-$(pwd)/reports}"
mkdir -p "$REPORT_DIR"

# --- Install Trivy (pinned version for reproducibility) ---
TRIVY_VERSION="0.57.1"
echo "=== Installing Trivy v${TRIVY_VERSION} ==="

# Try direct download first
for i in 1 2 3; do
  curl -sfL --retry 3 --retry-delay 5 -o trivy.tar.gz \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
    && break
  echo "Retry $i..."
  sleep 10
done

# Fallback: install via apt if download failed
if [ ! -f trivy.tar.gz ]; then
  echo "=== Direct download failed, installing via apt ==="
  sudo apt-get update -qq
  sudo apt-get install -y -qq wget apt-transport-https gnupg
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
  sudo apt-get update -qq
  sudo apt-get install -y -qq trivy
else
  tar -xzf trivy.tar.gz -C /usr/local/bin trivy
fi

trivy --version

# --- Generate table report (human-readable) ---
echo "=== Scanning $IMAGE_NAME — CRITICAL + HIGH ==="
trivy image \
  --severity CRITICAL,HIGH \
  --format table \
  --output "$REPORT_DIR/trivy-report.txt" \
  "$IMAGE_NAME"

# --- Generate JSON report (machine-readable, for dashboards) ---
trivy image \
  --severity CRITICAL,HIGH \
  --format json \
  --output "$REPORT_DIR/trivy-report.json" \
  "$IMAGE_NAME"

# --- Print report to pipeline log ---
echo "=== Scan Results ==="
cat "$REPORT_DIR/trivy-report.txt"

# --- Gate: fail pipeline if ANY critical CVE exists ---
echo "=== Checking for CRITICAL CVEs ==="
CRITICAL_COUNT=$(jq '[.Results[]? | .Vulnerabilities // [] | map(select(.Severity == "CRITICAL")) | length] | add // 0' "$REPORT_DIR/trivy-report.json")

echo "CRITICAL CVEs found: $CRITICAL_COUNT"

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "##[error]BLOCKED — $CRITICAL_COUNT CRITICAL CVEs detected. Image will NOT be pushed to ACR."
  exit 1
fi

echo "=== PASSED — Zero CRITICAL CVEs. Image is clean. ==="