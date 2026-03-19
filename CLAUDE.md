# CLAUDE.md — FlipSwitch

## Project Overview

FlipSwitch is a Salesforce Progressive Delivery Feature Flag Framework. It brings feature flags, percentage rollouts, user targeting, multi-variant experiments, and emergency disable to Apex, LWC, and Flows. Distributed as an unlocked package via GitHub (MIT license, same model as NebulaLogger).

**Current status**: Planning phase — only `plan.md` (the full technical specification) exists. No code has been implemented yet.

## Technology Stack

- **Apex** — core business logic and service classes
- **Lightning Web Components (LWC)** — admin UI and conditional rendering components
- **Salesforce Flows** — invocable action integration
- **Custom Metadata Types (CMDT)** — CI/CD-deployable flag definitions
- **Custom Objects** — runtime targeting rules, variants, assignments, metrics
- **Platform Events** — async evaluation logging
- **Hierarchy Custom Settings** — per-user framework configuration
- **Platform Cache** — org-level and session-level caching
- **SFDX / Salesforce CLI** — project structure and package management

## Planned Project Structure

```
sfdx-project.json
force-app/main/default/
├── classes/
│   ├── FeatureFlag.cls                    # Entry point, static API + factory methods
│   ├── FeatureFlagBuilder.cls             # Fluent single-flag builder
│   ├── FeatureFlagBatchBuilder.cls        # Multi-flag batch builder
│   ├── FeatureFlagEvaluator.cls           # Core evaluation engine
│   ├── FeatureFlagContext.cls             # Internal evaluation context
│   ├── FeatureFlagCache.cls               # Platform Cache integration
│   ├── FeatureFlagLogger.cls              # Async Platform Event logging
│   ├── FeatureFlagResult.cls              # Result wrapper
│   ├── FeatureFlagHash.cls                # Deterministic SHA-256 hashing
│   ├── FeatureFlagHandler.cls             # Callback interface
│   ├── FeatureFlagPlugin.cls              # Extensibility interface
│   ├── FeatureFlagException.cls           # Custom exception
│   ├── FeatureFlagFlowAction.cls          # @InvocableMethod for Flows
│   ├── FeatureFlagExpirationJob.cls       # Scheduled Apex for auto-expiration
│   ├── CallableFeatureFlag.cls            # System.Callable for loose coupling
│   └── tests/
│       ├── FeatureFlagTest.cls
│       ├── FeatureFlagBuilderTest.cls
│       ├── FeatureFlagBatchBuilderTest.cls
│       ├── FeatureFlagEvaluatorTest.cls
│       ├── FeatureFlagCacheTest.cls
│       └── FeatureFlagHashTest.cls
├── customMetadata/
│   ├── FlipSwitch_Flag__mdt/              # Flag definitions
│   ├── FlipSwitch_Config__mdt/            # Framework settings
│   └── FlipSwitch_Plugin__mdt/            # Plugin configuration
├── customSettings/
│   └── FlipSwitch_Settings__c/            # Hierarchy custom setting
├── objects/
│   ├── FlipSwitch_Rule__c/                # Runtime targeting rules
│   ├── FlipSwitch_Variant__c/             # Multi-variant definitions
│   ├── FlipSwitch_Assignment__c/          # Sticky user assignments
│   └── FlipSwitch_Metric__c/             # Evaluation analytics
├── platformEventChannelMembers/
│   └── FlipSwitch_Evaluation__e/          # Audit trail events
├── lwc/
│   ├── featureFlagGate/                   # Conditional rendering
│   ├── featureFlagVariant/                # Multi-variant rendering
│   ├── featureFlagService/                # Imperative JS service module
│   └── featureFlagAdmin/                  # Admin dashboard
├── permissionsets/
│   ├── FlipSwitch_Admin.permissionset-meta.xml
│   └── FlipSwitch_User.permissionset-meta.xml
├── tabs/
└── flexipages/
```

## Architecture

### Hybrid Storage Model

- **CMDT** (`FlipSwitch_Flag__mdt`) for flag definitions — deployable via CI/CD, no data storage limits
- **Custom Objects** (`FlipSwitch_Rule__c`, etc.) for runtime rules — admin-editable without deployments
- **Platform Events** (`FlipSwitch_Evaluation__e`) for async logging — non-blocking, decoupled

### Dual API Pattern

```apex
// Quick static API
FeatureFlag.isEnabled('NEW_CHECKOUT')
FeatureFlag.getVariant('HOMEPAGE_EXPERIMENT')

// Fluent builder API
FeatureFlag.flag('FEATURE_KEY')
    .forUser(userId)
    .withAttribute('region', 'US')
    .fallback(false)
    .isEnabled()

// Batch evaluation (single SOQL)
Map<String, FeatureFlagResult> results = FeatureFlag.flags('FLAG_A', 'FLAG_B')
    .forUser(userId)
    .evaluateAll()
```

### Evaluation Order

The evaluator checks rules in this priority:
1. Emergency disable (`Is_Active__c = false` or `Emergency_Disable` rule)
2. Expiration (`Expiration_Date__c < TODAY`)
3. Targeting rules by `Priority__c`: User > Profile > Permission Set > Segment > Custom Field > Percentage
4. Falls through to `Default_Value__c` if no rules match

### Key Design Decisions

- **Deterministic hashing**: `SHA-256(userId + flagKey) % 100` for consistent percentage rollouts without per-user storage
- **Platform Events for logging**: async, won't impact DML limits
- **Circuit breaker**: evaluation errors return default values, never break the caller
- **Lazy evaluation with memoization**: most transactions check 1-3 flags, batch on demand
- **Product-branded metadata names**: all Salesforce objects/CMDT/events use `FlipSwitch_` prefix to avoid conflicts with existing org metadata; Apex classes use `FeatureFlag` prefix (no conflict risk)

## Coding Conventions

### Naming

- All public classes prefixed with `FeatureFlag` (e.g., `FeatureFlagBuilder`, `FeatureFlagCache`)
- Interfaces: `FeatureFlagHandler`, `FeatureFlagPlugin`
- Test classes: `<ClassName>Test.cls` (e.g., `FeatureFlagBuilderTest`)
- CMDT/Object/Event names: `FlipSwitch_*` with underscores (avoids naming conflicts in subscriber orgs)
- LWC components: camelCase (e.g., `featureFlagGate`, `featureFlagAdmin`)

### Patterns

- **Builder pattern** — fluent API chaining on `FeatureFlagBuilder` and `FeatureFlagBatchBuilder`
- **Factory pattern** — `FeatureFlag.flag()` and `FeatureFlag.flags()` create builders
- **Strategy pattern** — pluggable `FeatureFlagPlugin` interface
- **Adapter pattern** — `CallableFeatureFlag` wraps the API for `System.Callable`
- **Circuit breaker** — all evaluation errors return safe defaults

### API Design Principles

- Static convenience methods on `FeatureFlag.cls` delegate to fluent builders internally
- Terminal methods (`.isEnabled()`, `.evaluate()`, `.execute()`) trigger evaluation
- `.silent()` suppresses logging for performance-sensitive paths
- `.fallback()` overrides the CMDT default value
- Batch builder loads all rules in a single SOQL query

## Development Setup

### Prerequisites

- Salesforce CLI (`sf`) installed
- A Salesforce DevHub org with unlocked package creation enabled
- Platform Cache partition (post-install configuration step)

### Common Commands

```bash
# Create scratch org
sf org create scratch -f config/project-scratch-def.json -a flipswitch-dev -d 30

# Push source to scratch org
sf project deploy start --target-org flipswitch-dev

# Run all tests
sf apex run test --target-org flipswitch-dev --code-coverage --result-format human

# Create package version
sf package version create -p FlipSwitch -d force-app -x --wait 20

# Install package
sf package install --wait 20 --security-type AdminsOnly --package <PACKAGE_VERSION_ID>
```

## Testing Requirements

- **Target**: 90%+ Apex code coverage
- **Test classes**: one per core class, located in `force-app/main/default/classes/tests/`
- **Coverage areas**:
  - Boolean flag evaluation (enabled/disabled)
  - Multi-variant evaluation with weight distribution
  - Targeting rule priority and matching (user, profile, permission set, percentage)
  - Emergency disable and expiration behavior
  - Cache hit/miss/invalidation
  - Deterministic hashing consistency
  - Flow invocable action (single + bulk)
  - Circuit breaker (errors return defaults)

## Implementation Phases

| Phase | Scope |
|-------|-------|
| 1 | Data Model & Storage — CMDT, Custom Objects, Platform Events, Custom Settings |
| 2 | Apex Service Layer — dual API (static + fluent), evaluator, cache, logging, hashing |
| 3 | Flow Support — invocable action for Flow decisions |
| 4 | LWC Components — gate, variant, service module, admin dashboard |
| 5 | Safety & Observability — emergency disable, auto-expiration, circuit breaker, analytics |
| 6 | Package & Distribution — unlocked package, MIT license, GitHub release |
| 7 | Integrations — New Relic dashboards, optional NebulaLogger, PagerDuty alerts |

## Key Reference

- `plan.md` — the comprehensive technical specification (source of truth for all architecture and design decisions)

## Dependencies

- **Zero external dependencies** for core functionality
- **Optional**: NebulaLogger integration (detected at runtime via `Type.forName('Logger')`)
- **Optional**: New Relic / PagerDuty for observability

## Scope Exclusions

Not in scope for v1: Aura components, Visualforce, external integrations (LaunchDarkly sync), mobile SDK, real-time flag streaming, AppExchange listing, managed package.
