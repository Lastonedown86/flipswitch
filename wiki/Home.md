# FlipSwitch Wiki

> **Progressive Delivery Feature Flags for Salesforce**

Welcome to the FlipSwitch wiki. Use the sidebar to navigate between topics.

## Getting Started

- [Post-Install Setup](Post-Install-Setup) — permission sets, cache, scheduled jobs
- [Flag Definitions (CMDT)](Flag-Definitions) — define flags deployable via CI/CD

## API Reference

- [Apex API](Apex-API) — static API, fluent builder, batch, code-defined flags, transaction controls
- [LWC Components](LWC-Components) — gate, variant, service module, admin dashboard
- [Flow Support](Flow-Support) — `@InvocableMethod` for Flow Builder

## Concepts

- [Targeting Rules](Targeting-Rules) — user, profile, permission set, segment, custom field, percentage
- [Evaluation Order](Evaluation-Order) — priority chain and short-circuit logic
- [Emergency Disable](Emergency-Disable) — runtime kill switch, no deployment required
- [Percentage Rollouts](Percentage-Rollouts) — deterministic SHA-256 hashing
- [Multi-Variant Experiments](Multi-Variant-Experiments) — A/B/n testing with weighted variants

## Operations

- [Logging & Analytics](Logging-and-Analytics) — Platform Event buffering, metrics, sampling
- [Platform Cache](Platform-Cache) — org and session cache tiers
- [Plugin Framework](Plugin-Framework) — post-evaluation hooks and extensibility

## Development

- [Architecture](Architecture) — storage model, class map, LWC map
- [Development Setup](Development-Setup) — prerequisites, scratch orgs, npm scripts
- [Testing](Testing) — Apex test classes, LWC Jest tests
