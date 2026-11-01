#!/bin/bash
set -euo pipefail

# Usage: generate-sbom.sh  [report-dir]
IMAGE_NAME="${1:?Usage: generate-sbom.sh  [report-dir]}"
REPORT_DIR="${2:-$(pwd)/reports}"
mkdir -p "$REPORT_DIR"

# --- Generate SBOM in SPDX JSON format ---
echo "=== Generating SBOM for $IMAGE_NAME ==="
trivy image \
  --format spdx-json \
  --output "$REPORT_DIR/sbom.json" \
  "$IMAGE_NAME"

# --- Summary ---
PACKAGE_COUNT=$(jq '.packages | length' "$REPORT_DIR/sbom.json")
echo "=== SBOM generated: $REPORT_DIR/sbom.json ==="
echo "=== Total packages cataloged: $PACKAGE_COUNT ==="
echo "=== This proves supply chain visibility — you know exactly what's inside your container ==="