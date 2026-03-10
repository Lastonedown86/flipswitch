#!/bin/bash
set -e

ALIAS=${1:-flipswitch-dev}
DAYS=${2:-30}

echo "Creating scratch org: $ALIAS (duration: $DAYS days)"
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias "$ALIAS" \
  --duration-days "$DAYS" \
  --wait 10

echo "Deploying source..."
sf project deploy start --target-org "$ALIAS" --wait 20

echo "Scheduling expiration job..."
sf apex run --target-org "$ALIAS" --file scripts/apex/schedule-expiration-job.apex

echo "Done! Scratch org '$ALIAS' is ready."
echo "Run: sf org open --target-org $ALIAS"
