# Development Setup

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- A Salesforce DevHub org with unlocked package creation enabled
- Node.js 20+

## One-command setup

```bash
git clone https://github.com/Lastonedown86/flipswitch.git
cd flipswitch
npm install
bash scripts/create-scratch-org.sh flipswitch-dev 30
sf org open --target-org flipswitch-dev
```

## Manual steps

```bash
npm install

# Authenticate DevHub
sf org login web --set-default-dev-hub --alias devhub

# Create scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias flipswitch-dev \
  --duration-days 30

# Deploy source
sf project deploy start --target-org flipswitch-dev

# Assign permission set
sf org assign permset --name FlipSwitch_Admin --target-org flipswitch-dev

# Schedule expiration job
sf apex run --target-org flipswitch-dev \
  --file scripts/apex/schedule-expiration-job.apex
```

## npm scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run LWC Jest tests with coverage |
| `npm run lint` | ESLint on all LWC components |
| `npm run prettier` | Auto-format all HTML/JS/CSS/JSON |
| `npm run prettier:check` | Check formatting (used in CI) |
| `npm run scratch:create` | Create a `flipswitch-dev` scratch org |
| `npm run scratch:deploy` | Deploy source to `flipswitch-dev` |
| `npm run scratch:test` | Run Apex tests on `flipswitch-dev` with coverage |

## Create a new package version

```bash
# First time only — create the package
sf package create \
  --name FlipSwitch \
  --package-type Unlocked \
  --path force-app \
  --target-dev-hub devhub

# Create and validate a version
sf package version create \
  --package FlipSwitch \
  --definition-file config/project-scratch-def.json \
  --installation-key-bypass \
  --code-coverage \
  --wait 30

# Promote to released (run from main branch only)
sf package version promote --package <PACKAGE_VERSION_ID> --no-prompt
```
