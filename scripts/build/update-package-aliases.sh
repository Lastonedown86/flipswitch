#!/bin/bash
# update-package-aliases.sh
# Adds a new package version alias to sfdx-project.json packageAliases.
# Usage: ./scripts/build/update-package-aliases.sh <version-name> <version-id>
# Example: ./scripts/build/update-package-aliases.sh "FlipSwitch@1.0.0-initial-release" "04tXXXXXX"

set -euo pipefail

VERSION_NAME="${1:?Usage: update-package-aliases.sh <version-name> <version-id>}"
VERSION_ID="${2:?Usage: update-package-aliases.sh <version-name> <version-id>}"

echo "Adding alias: \"$VERSION_NAME\": \"$VERSION_ID\""

# Use python to update the JSON (cross-platform, no jq dependency)
python3 -c "
import json, sys

with open('sfdx-project.json', 'r') as f:
    data = json.load(f)

data['packageAliases']['$VERSION_NAME'] = '$VERSION_ID'

with open('sfdx-project.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print('Updated sfdx-project.json packageAliases')
"
