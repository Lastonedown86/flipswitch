# FlipSwitch

**Progressive Delivery Feature Flags for Salesforce**

FlipSwitch brings feature flags, percentage rollouts, user targeting, multi-variant experiments, and kill switches to Apex, LWC, and Flows. Distributed as an unlocked package — open source, MIT licensed, zero AppExchange.

---

## Quick Start

```apex
// One-liner: is this feature on for the running user?
if (FeatureFlag.isEnabled('NEW_CHECKOUT')) {
    // new path
}

// Fluent API with targeting
String variant = FeatureFlag.flag('HOMEPAGE_EXPERIMENT')
    .forUser(someUserId)
    .withAttribute('region', 'US')
    .fallback('control')
    .getVariant();

// Batch evaluation (single SOQL)
Map<String, FeatureFlagResult> results = FeatureFlag.flags('FLAG_A', 'FLAG_B')
    .forUser(someUserId)
    .evaluateAll();
```

```html
<!-- LWC conditional rendering -->
<c-feature-flag-gate flag-key="DARK_MODE">
    <div slot="enabled">New dark mode UI</div>
    <div slot="disabled">Classic UI</div>
</c-feature-flag-gate>
```

---

## Install

**Sandbox**
```
/packaging/installPackage.apexp?p0=PACKAGE_VERSION_ID
```

**Production**
```
/packaging/installPackage.apexp?p0=PACKAGE_VERSION_ID
```

**Salesforce CLI**
```bash
sf package install --wait 20 --security-type AdminsOnly --package PACKAGE_VERSION_ID
```

---

## Post-Install Setup

1. **Assign permission set** — `Feature_Flag_Admin` (admins) or `Feature_Flag_User` (read-only)
2. **Configure Platform Cache** — create a partition named `FlipSwitch` in Setup → Platform Cache (optional but recommended for performance)
3. **Schedule expiration job** — run the anonymous Apex in `scripts/apex/schedule-expiration-job.apex`

---

## Features

| Feature | Description |
|---------|-------------|
| Boolean flags | Simple on/off per user, profile, or percentage |
| Percentage rollouts | Deterministic SHA-256 hash — same user always gets same result |
| Multi-variant | A/B/n experiments with weighted distribution |
| Kill switch | One-click emergency disable — no deployment needed |
| Auto-expiration | Scheduled cleanup of stale flags |
| Flow support | `@InvocableMethod` for use in any Flow type |
| Admin UI | Full LWC dashboard for flag management |
| Evaluation logging | Async Platform Events — no DML impact |
| Plugin framework | CMDT-configured hooks for custom logic |
| Callable adapter | `System.Callable` interface for zero-dependency usage |

---

## Evaluation Order

1. Kill switch (`Is_Active__c = false` or `Kill_Switch` rule)
2. Expiration (`Expiration_Date__c < TODAY`)
3. Targeting rules by priority: User → Profile → Permission Set → Segment → Custom Field → Percentage
4. Default value

---

## Architecture

- **CMDT** (`Feature_Flag__mdt`) — flag definitions, CI/CD deployable
- **Custom Objects** (`Feature_Flag_Rule__c`, etc.) — runtime rules, admin editable
- **Platform Events** (`Feature_Flag_Evaluation__e`) — async evaluation logging
- **Hierarchy Custom Settings** — per-user framework configuration
- **Platform Cache** — org-level CMDT cache + session-level result dedup

---

## Development

```bash
# Create scratch org and deploy
npm run scratch:create
npm run scratch:deploy

# Run all tests
npm run scratch:test

# LWC Jest tests
npm test
```

---

## License

MIT — see [LICENSE](LICENSE)
