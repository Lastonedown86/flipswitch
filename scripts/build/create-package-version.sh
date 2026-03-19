#!/bin/bash
# create-package-version.sh
# Creates a new FlipSwitch unlocked package version and extracts the SubscriberPackageVersionId.
# Usage: ./scripts/build/create-package-version.sh

set -euo pipefail

echo "Creating FlipSwitch package version..."

RESULT=$(sf package version create \
  --json \
  --package "FlipSwitch" \
  --skip-ancestor-check \
  --code-coverage \
  --installation-key-bypass \
  --wait 30)

echo "$RESULT"

VERSION_ID=$(echo "$RESULT" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['result']['SubscriberPackageVersionId'])")
PACKAGE_VERSION_ID=$(echo "$RESULT" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['result']['SubscriberPackageVersionId'])")

echo ""
echo "=================================================="
echo "Package Version Created Successfully!"
echo "SubscriberPackageVersionId: $VERSION_ID"
echo ""
echo "Install command:"
echo "  sf package install --wait 20 --security-type AdminsOnly --package $VERSION_ID"
echo ""
echo "Install URL (Sandbox):"
echo "  https://test.salesforce.com/packaging/installPackage.apexp?p0=$VERSION_ID"
echo ""
echo "Install URL (Production):"
echo "  https://login.salesforce.com/packaging/installPackage.apexp?p0=$VERSION_ID"
echo "=================================================="
