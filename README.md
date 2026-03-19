# FlipSwitch

> **Progressive Delivery Feature Flags for Salesforce**
>
> Boolean flags · Percentage rollouts · Multi-variant A/B experiments · Emergency disable · Flow support · LWC components

FlipSwitch is an open-source, unlocked-package feature flag framework for Salesforce. It brings LaunchDarkly-style progressive delivery to Apex, LWC, and Flows — with zero external dependencies, no AppExchange gatekeeping, and MIT licensing so you can fork, modify, and redistribute freely.

[![CI](https://github.com/Lastonedown86/flipswitch/actions/workflows/build.yml/badge.svg)](https://github.com/Lastonedown86/flipswitch/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Table of Contents

- [Why FlipSwitch?](#why-flipswitch)
- [Features](#features)
- [Install](#install)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Why FlipSwitch?

| Problem | FlipSwitch solution |
|---------|---------------------|
| Deploying to enable a feature is risky | Define flags in CMDT, enable via admin UI — no deployment needed |
| Hard to roll out to 5% of users safely | Deterministic SHA-256 hash — same user always gets the same result, no per-user storage |
| A/B testing requires custom code each time | `FeatureFlag.getVariant()` with weighted `FlipSwitch_Variant__c` records |
| Incident response requires a redeployment | One-click emergency disable in the admin UI takes effect on the next request |
| Feature flags litter the codebase forever | `Expiration_Date__c` + a scheduled cleanup job auto-retires stale flags |
| Managed packages can't depend on your framework | `CallableFeatureFlag` implements `System.Callable` — zero compile-time dependency |

---

## Features

| Feature | Notes |
|---------|-------|
| **Boolean flags** | On/off per user, profile, permission set, or percentage |
| **Percentage rollouts** | Deterministic `SHA-256(userId + flagKey) % 100` — consistent without storage |
| **Multi-variant (A/B/n)** | Weighted `FlipSwitch_Variant__c` records, `getVariant()` terminal |
| **Targeting rules** | User · Profile · Permission Set · Segment · Custom Field · Percentage |
| **Emergency disable** | Runtime rule, no deployment — takes effect on the next request |
| **Auto-expiration** | Scheduled Apex deactivates rules past their `End_Date__c` |
| **Fluent builder API** | Chainable, readable, single-terminal-call pattern |
| **Batch evaluation** | Single SOQL for N flags via `FeatureFlag.flags()` |
| **Flow support** | `@InvocableMethod`, bulkified, works in all Flow types |
| **LWC components** | Gate, variant, imperative service module, admin dashboard |
| **Async logging** | Platform Event buffering — evaluation never impacts DML limits |
| **Plugin hooks** | CMDT-registered `FeatureFlagPlugin` classes for post-evaluation callbacks |
| **Callable adapter** | `System.Callable` for zero-dependency usage from managed packages |
| **Circuit breaker** | Evaluation errors always return a safe default — never throws to the caller |
| **QA overrides** | Force all flags on/off per user via Hierarchy Custom Setting |

---

## Install

### Salesforce CLI (recommended)

```bash
sf package install \
  --wait 20 \
  --security-type AdminsOnly \
  --package <PACKAGE_VERSION_ID>
```

### Browser — Sandbox

```
https://<your-sandbox>.sandbox.my.salesforce.com/packaging/installPackage.apexp?p0=<PACKAGE_VERSION_ID>
```

### Browser — Production

```
https://<your-org>.my.salesforce.com/packaging/installPackage.apexp?p0=<PACKAGE_VERSION_ID>
```

> Package version IDs are listed on the [Releases](https://github.com/Lastonedown86/flipswitch/releases) page.

---

## Quick Start

```apex
// Simple boolean check
if (FeatureFlag.isEnabled('NEW_CHECKOUT')) {
    // new code path
}

// Fluent builder with targeting context
Boolean isOn = FeatureFlag.flag('NEW_CHECKOUT')
    .forUser(someUserId)
    .withAttribute('region', 'US')
    .fallback(false)
    .isEnabled();

// Multi-variant experiment
String variant = FeatureFlag.getVariant('HOMEPAGE_EXPERIMENT');

// Batch evaluation (single SOQL)
Map<String, FeatureFlagResult> results = FeatureFlag.flags('FLAG_A', 'FLAG_B')
    .forUser(someUserId)
    .evaluateAll();

// Emergency disable — instant, no deployment
FeatureFlag.activateEmergencyDisable('NEW_CHECKOUT');
```

---

## Documentation

Full documentation is available in the **[Wiki](https://github.com/Lastonedown86/flipswitch/wiki)**:

### Getting Started

- **[Post-Install Setup](https://github.com/Lastonedown86/flipswitch/wiki/Post-Install-Setup)** — permission sets, cache, scheduled jobs
- **[Flag Definitions (CMDT)](https://github.com/Lastonedown86/flipswitch/wiki/Flag-Definitions)** — define flags deployable via CI/CD

### API Reference

- **[Apex API](https://github.com/Lastonedown86/flipswitch/wiki/Apex-API)** — static API, fluent builder, batch, code-defined flags, transaction controls, handlers, callable adapter
- **[LWC Components](https://github.com/Lastonedown86/flipswitch/wiki/LWC-Components)** — gate, variant, service module, admin dashboard
- **[Flow Support](https://github.com/Lastonedown86/flipswitch/wiki/Flow-Support)** — `@InvocableMethod` for Flow Builder

### Concepts

- **[Targeting Rules](https://github.com/Lastonedown86/flipswitch/wiki/Targeting-Rules)** — user, profile, permission set, segment, custom field, percentage
- **[Evaluation Order](https://github.com/Lastonedown86/flipswitch/wiki/Evaluation-Order)** — priority chain and short-circuit logic
- **[Emergency Disable](https://github.com/Lastonedown86/flipswitch/wiki/Emergency-Disable)** — runtime kill switch, no deployment required
- **[Percentage Rollouts](https://github.com/Lastonedown86/flipswitch/wiki/Percentage-Rollouts)** — deterministic SHA-256 hashing
- **[Multi-Variant Experiments](https://github.com/Lastonedown86/flipswitch/wiki/Multi-Variant-Experiments)** — A/B/n testing with weighted variants

### Operations

- **[Logging & Analytics](https://github.com/Lastonedown86/flipswitch/wiki/Logging-and-Analytics)** — Platform Event buffering, metrics, sampling
- **[Platform Cache](https://github.com/Lastonedown86/flipswitch/wiki/Platform-Cache)** — org and session cache tiers
- **[Plugin Framework](https://github.com/Lastonedown86/flipswitch/wiki/Plugin-Framework)** — post-evaluation hooks and extensibility

### Development

- **[Architecture](https://github.com/Lastonedown86/flipswitch/wiki/Architecture)** — storage model, class map, LWC map
- **[Development Setup](https://github.com/Lastonedown86/flipswitch/wiki/Development-Setup)** — prerequisites, scratch orgs, npm scripts
- **[Testing](https://github.com/Lastonedown86/flipswitch/wiki/Testing)** — Apex test classes, LWC Jest tests

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Make changes against a scratch org
4. Ensure `npm test` and `sf apex run test` both pass at 90%+ coverage
5. Open a pull request — CI runs lint, Jest, Apex tests, and a package version create automatically

Please open an issue before starting large changes so we can discuss the approach first.

---

## License

MIT © FlipSwitch Contributors — see [LICENSE](LICENSE)
