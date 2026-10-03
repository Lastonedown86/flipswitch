#!/bin/bash
set -e

ALIAS=${1:-flipswitch-dev}

echo "Running Apex tests on: $ALIAS"
sf apex run test \
  --target-org "$ALIAS" \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 20

echo ""
echo "Running LWC Jest tests..."
npm test
