#!/bin/bash
set -euo pipefail

# Usage: scan-trivy.sh  [report-dir]
IMAGE_NAME="${1:?Usage: scan-trivy.sh  [report-dir]}"
REPORT_DIR="${2:-$(pwd)/reports}"
mkdir -p "$REPORT_DIR"

# --- Install Trivy (pinned version for reproducibility) ---
echo "=== Installing Trivy v0.57.1 ==="
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.57.1
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