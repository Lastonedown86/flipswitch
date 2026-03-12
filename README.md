# FlipSwitch

> **Progressive Delivery Feature Flags for Salesforce**
>
> Boolean flags · Percentage rollouts · Multi-variant A/B experiments · Kill switches · Flow support · LWC components

FlipSwitch is an open-source, unlocked-package feature flag framework for Salesforce. It brings LaunchDarkly-style progressive delivery to Apex, LWC, and Flows — with zero external dependencies, no AppExchange gatekeeping, and MIT licensing so you can fork, modify, and redistribute freely.

[![CI](https://github.com/Lastonedown86/flipswitch/actions/workflows/build.yml/badge.svg)](https://github.com/Lastonedown86/flipswitch/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Table of Contents

- [Why FlipSwitch?](#why-flipswitch)
- [Features](#features)
- [Install](#install)
- [Post-Install Setup](#post-install-setup)
- [Apex API](#apex-api)
  - [Static API](#static-api)
  - [Fluent Builder API](#fluent-builder-api)
  - [Batch API](#batch-api)
  - [Transaction Controls](#transaction-controls)
  - [FeatureFlagResult](#featureflagresult)
  - [FeatureFlagHandler](#featureflaghandler)
  - [Callable Adapter](#callable-adapter)
- [LWC Components](#lwc-components)
  - [featureFlagGate](#featureflaggate)
  - [featureFlagVariant](#featureflagvariant)
  - [featureFlagService](#featureflagservice)
  - [featureFlagAdmin](#featureflagadmin)
- [Flow Support](#flow-support)
- [Flag Definitions (CMDT)](#flag-definitions-cmdt)
- [Targeting Rules](#targeting-rules)
- [Evaluation Order](#evaluation-order)
- [Kill Switch](#kill-switch)
- [Percentage Rollouts](#percentage-rollouts)
- [Multi-Variant Experiments](#multi-variant-experiments)
- [Logging & Analytics](#logging--analytics)
- [Platform Cache](#platform-cache)
- [Plugin Framework](#plugin-framework)
- [Architecture](#architecture)
- [Development Setup](#development-setup)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

---

## Why FlipSwitch?

| Problem | FlipSwitch solution |
|---------|---------------------|
| Deploying to enable a feature is risky | Define flags in CMDT, enable via admin UI — no deployment needed |
| Hard to roll out to 5% of users safely | Deterministic SHA-256 hash — same user always gets the same result, no per-user storage |
| A/B testing requires custom code each time | `FeatureFlag.getVariant()` with weighted `FlipSwitch_Variant__c` records |
| Incident response requires a redeployment | One-click kill switch in the admin UI takes effect on the next request |
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
| **Kill switch** | Runtime rule, no deployment — takes effect on the next request |
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

## Post-Install Setup

### 1. Assign permission sets

```bash
# Admin users — full read/write + kill switch
sf org assign permset --name FlipSwitch_Admin --target-org <alias>

# Application users — read-only, flag evaluation only
sf org assign permset --name FlipSwitch_User --target-org <alias>
```

Or assign manually via **Setup → Permission Sets**.

### 2. Configure Platform Cache (optional but recommended)

1. Go to **Setup → Platform Cache**
2. Create a partition named **`FlipSwitch`**
3. Update `Cache_Partition_Name__c` on the `FlipSwitch_Config.Default` CMDT record to `local.FlipSwitch`

Without a cache partition the framework works correctly but performs a SOQL query on every evaluation.

### 3. Schedule the expiration job

```apex
System.schedule('FlipSwitch Expiration Job', '0 0 0 * * ?', new FeatureFlagExpirationJob());
```

Or run the helper script:

```bash
sf apex run --target-org <alias> --file scripts/apex/schedule-expiration-job.apex
```

### 4. Open the admin dashboard

Navigate to the **Feature Flags** tab (or the **Feature Flag Admin** Lightning App Page).

---

## Apex API

### Static API

The simplest way to check a flag for the running user:

```apex
if (FeatureFlag.isEnabled('NEW_CHECKOUT')) {
    // new code path
}

String variant = FeatureFlag.getVariant('HOMEPAGE_EXPERIMENT');
switch on variant {
    when 'control'     { /* original */    }
    when 'treatment_a' { /* new layout */  }
    when 'treatment_b' { /* bold layout */ }
}
```

### Fluent Builder API

Use the builder when you need targeting context, a fallback, or a conditional callback:

```apex
// Evaluate for a specific user with custom attributes
Boolean isOn = FeatureFlag.flag('NEW_CHECKOUT')
    .forUser(someUserId)
    .withAttribute('region', 'US')
    .withAttribute('tier', 'Enterprise')
    .fallback(false)
    .isEnabled();

// Get a variant key
String variant = FeatureFlag.flag('HOMEPAGE_EXPERIMENT')
    .forUser(someUserId)
    .fallback('control')
    .getVariant();

// Get the full result (includes reason and payload)
FeatureFlagResult result = FeatureFlag.flag('MY_FLAG').evaluate();
System.debug(result.isEnabled); // Boolean
System.debug(result.variant);   // String — null for boolean flags
System.debug(result.reason);    // RULE_MATCH | DEFAULT | KILL_SWITCH | EXPIRED | ERROR

// Conditional execution via registered handlers
FeatureFlag.flag('NEW_CHECKOUT')
    .whenEnabled(new NewCheckoutHandler())
    .whenDisabled(new LegacyCheckoutHandler())
    .execute();

// Suppress logging for performance-sensitive paths
Boolean cheapCheck = FeatureFlag.flag('HIGH_VOLUME_FLAG').silent().isEnabled();

// Tag this evaluation with a business scenario for analytics
Boolean scored = FeatureFlag.flag('LEAD_SCORING')
    .inScenario('Lead Assignment Flow')
    .isEnabled();
```

#### Builder method reference

| Method | Returns | Description |
|--------|---------|-------------|
| `.forUser(Id)` | `FeatureFlagBuilder` | Evaluate for a specific user (default: running user) |
| `.withAttribute(String, Object)` | `FeatureFlagBuilder` | Add a single custom context attribute |
| `.withAttributes(Map)` | `FeatureFlagBuilder` | Bulk-add custom context attributes |
| `.fallback(Boolean)` | `FeatureFlagBuilder` | Override the CMDT default when no rules match |
| `.fallback(String)` | `FeatureFlagBuilder` | Override the CMDT default (variant key) |
| `.silent()` | `FeatureFlagBuilder` | Suppress evaluation logging for this call |
| `.inScenario(String)` | `FeatureFlagBuilder` | Tag this evaluation with a business scenario |
| `.whenEnabled(Handler)` | `FeatureFlagBuilder` | Register callback to run when flag is enabled |
| `.whenDisabled(Handler)` | `FeatureFlagBuilder` | Register callback to run when flag is disabled |
| `.isEnabled()` | `Boolean` | **Terminal** — evaluate and return boolean |
| `.getVariant()` | `String` | **Terminal** — evaluate and return variant key |
| `.getPayload()` | `Map<String, Object>` | **Terminal** — evaluate and return variant payload |
| `.evaluate()` | `FeatureFlagResult` | **Terminal** — evaluate and return full result |
| `.execute()` | `void` | **Terminal** — evaluate and invoke the matching handler |

### Batch API

Use when checking multiple flags in the same transaction. All rules are loaded in **a single SOQL query**:

```apex
// Two- and three-argument shorthand
Map<String, FeatureFlagResult> results = FeatureFlag.flags('FLAG_A', 'FLAG_B')
    .forUser(someUserId)
    .evaluateAll();

// List overload for dynamic sets
List<String> keys = new List<String>{ 'FLAG_A', 'FLAG_B', 'FLAG_C' };
Map<String, FeatureFlagResult> results = FeatureFlag.flags(keys)
    .forUser(someUserId)
    .withAttribute('region', 'EMEA')
    .evaluateAll();

if (results.get('FLAG_A').isEnabled) { /* ... */ }
System.debug(results.get('FLAG_B').variant); // e.g. 'treatment_a'
```

### Transaction Controls

Mirrors the NebulaLogger pattern — buffer all evaluation events and publish once at the end of the transaction:

```apex
// Tag all evaluations in this transaction for per-flow analytics
FeatureFlag.setScenario('Checkout Flow');

doCheckout(); // evaluations buffer internally

FeatureFlag.flushEvaluations(); // single EventBus.publish() call

// Suppress all logging for a block of code
FeatureFlag.suspendLogging();
doBulkProcessing();
FeatureFlag.resumeLogging();

// Override save method for this transaction
FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.EVENT_BUS);   // default — buffer then publish
FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.QUEUEABLE);   // defer to async job
FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.SYNCHRONOUS); // direct DML (debug only)
```

### FeatureFlagResult

All terminal methods return a `FeatureFlagResult`:

```apex
FeatureFlagResult result = FeatureFlag.flag('MY_FLAG').evaluate();

result.isEnabled  // Boolean  — was the flag on?
result.variant    // String   — variant key (null for boolean flags)
result.reason     // String   — why this result was returned
result.payload    // Map<String, Object> — optional variant payload
```

**Reason constants:**

| Constant | Meaning |
|----------|---------|
| `RULE_MATCH` | A targeting rule matched |
| `DEFAULT` | No rules matched; CMDT `Default_Value__c` was used |
| `KILL_SWITCH` | Flag or a `Kill_Switch` rule forced it off |
| `EXPIRED` | `Expiration_Date__c` has passed |
| `QA_OVERRIDE` | `Override_All_Flags__c` hierarchy setting is active |
| `CACHE_HIT` | Result was returned from Platform Cache |
| `ERROR` | Evaluation error; safe default returned (circuit breaker) |

### FeatureFlagHandler

Implement this interface to use the conditional execution pattern:

```apex
public class NewCheckoutHandler implements FeatureFlagHandler {
    public void handle() {
        // runs when NEW_CHECKOUT is enabled
    }
}

FeatureFlag.flag('NEW_CHECKOUT')
    .whenEnabled(new NewCheckoutHandler())
    .whenDisabled(new LegacyCheckoutHandler())
    .execute();
```

### Callable Adapter

Allows managed packages and ISV code to use FlipSwitch without a hard compile-time dependency:

```apex
Type t = Type.forName('CallableFeatureFlag');
if (t != null) {
    System.Callable ff = (System.Callable) t.newInstance();

    // Boolean check
    Boolean isOn = (Boolean) ff.call('isEnabled', new Map<String, Object>{
        'flagKey' => 'MY_FLAG',
        'userId'  => someUserId  // optional — defaults to running user
    });

    // Variant check
    String variant = (String) ff.call('getVariant', new Map<String, Object>{
        'flagKey' => 'EXPERIMENT'
    });

    // Full result
    Map<String, Object> full = (Map<String, Object>) ff.call('evaluate', new Map<String, Object>{
        'flagKey' => 'MY_FLAG'
    });
    // full keys: isEnabled, variant, reason, payload

    // Transaction controls
    ff.call('setScenario', new Map<String, Object>{ 'scenario' => 'My Flow' });
    ff.call('flushLogs',   new Map<String, Object>());
}
```

---

## LWC Components

### featureFlagGate

Conditionally renders content based on a flag using named slots:

```html
<c-feature-flag-gate flag-key="NEW_CHECKOUT">
    <div slot="enabled">
        <!-- Shown when NEW_CHECKOUT is on -->
        <c-new-checkout-form></c-new-checkout-form>
    </div>
    <div slot="disabled">
        <!-- Shown when NEW_CHECKOUT is off -->
        <c-legacy-checkout-form></c-legacy-checkout-form>
    </div>
</c-feature-flag-gate>
```

Also available as a **drag-and-drop component** in App Builder (Lightning App Page, Record Page, Home Page) with a configurable `Flag Key` property.

### featureFlagVariant

Renders the named slot that matches the evaluated variant key. Designed for A/B/n experiments:

```html
<c-feature-flag-variant flag-key="HOMEPAGE_EXPERIMENT" default-variant="control">
    <div slot="control">
        <!-- Original homepage -->
    </div>
    <div slot="treatment_a">
        <!-- Redesigned homepage -->
    </div>
    <div slot="treatment_b">
        <!-- Bold homepage -->
    </div>
</c-feature-flag-variant>
```

If the returned variant doesn't match any declared slot, the `default-variant` slot is rendered.

### featureFlagService

Imperative JavaScript service module with a 30-second in-memory cache. Import and call it from any LWC:

```js
import { isEnabled, getVariant, evaluateFlags, clearCache }
    from 'c/featureFlagService';

// Single boolean check
const showNewUI = await isEnabled('NEW_CHECKOUT');

// Variant
const variant = await getVariant('HOMEPAGE_EXPERIMENT');

// Batch — single Apex call for multiple flags
const results = await evaluateFlags(['FLAG_A', 'FLAG_B', 'FLAG_C']);
if (results['FLAG_A'].isEnabled) { /* ... */ }
console.log(results['FLAG_B'].variant); // 'treatment_a'
console.log(results['FLAG_C'].reason);  // 'DEFAULT'

// Bust the client cache after admin changes
clearCache();
```

### featureFlagAdmin

Full admin dashboard available as a Lightning App Page. Three tabs:

| Tab | Purpose |
|-----|---------|
| **Flags** | Datatable of all `FlipSwitch_Flag__mdt` records — type, active status, default value, category, expiry |
| **Add Rule** | Form to create `FlipSwitch_Rule__c` targeting rules without opening Object Manager |
| **Kill Switch** | One-click emergency disable or re-enable for any flag by key |

---

## Flow Support

FlipSwitch registers an `@InvocableMethod` that appears in Flow Builder under the **Feature Flags** action category.

**Input variables:**

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `Flag Key` | Text | Yes | `FlipSwitch_Flag__mdt` DeveloperName |
| `User Id` | Text | No | Salesforce User Id — defaults to running user |

**Output variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `Is Enabled` | Boolean | Whether the flag is on for this user |
| `Variant` | Text | Variant key (null for boolean flags) |
| `Reason` | Text | `RULE_MATCH`, `DEFAULT`, `KILL_SWITCH`, etc. |

**Usage in a Record-Triggered Flow:**

1. Add an **Action** element
2. Search for **Evaluate Feature Flag**
3. Set `Flag Key` to your flag's DeveloperName
4. Use `{!Is_Enabled}` in a **Decision** element to branch

The action is **bulkified** — when a record-triggered flow processes 200 records, all evaluations share a single SOQL query for targeting rules.

---

## Flag Definitions (CMDT)

Flags are defined in `FlipSwitch_Flag__mdt`. Deploy them via CI/CD alongside the code that checks them so the flag and its implementation always ship together.

```xml
<!-- force-app/main/default/customMetadata/FlipSwitch_Flag.NEW_CHECKOUT.md-meta.xml -->
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>New Checkout</label>
    <protected>false</protected>
    <values>
        <field>Type__c</field>
        <value xsi:type="xsd:string">Boolean</value>
    </values>
    <values>
        <field>Default_Value__c</field>
        <value xsi:type="xsd:string">false</value>
    </values>
    <values>
        <field>Is_Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Category__c</field>
        <value xsi:type="xsd:string">Checkout</value>
    </values>
    <values>
        <field>Expiration_Date__c</field>
        <value xsi:type="xsd:string">2026-09-30</value>
    </values>
    <values>
        <field>Description__c</field>
        <value xsi:type="xsd:string">Enables the redesigned checkout flow. Remove after full rollout.</value>
    </values>
</CustomMetadata>
```

| Field | Type | Description |
|-------|------|-------------|
| `DeveloperName` | Text | The key used in code — `FeatureFlag.isEnabled('NEW_CHECKOUT')` |
| `Type__c` | Picklist | `Boolean` · `Variant` · `Percentage` |
| `Default_Value__c` | Text | Fallback when no rules match: `true`, `false`, or a variant key |
| `Is_Active__c` | Checkbox | Master kill switch — `false` disables the flag immediately |
| `Expiration_Date__c` | Date | Flag evaluates as disabled after this date |
| `Category__c` | Text | Grouping label in the admin dashboard |
| `Description__c` | Long Text | Human-readable purpose, owner, and cleanup notes |

---

## Targeting Rules

Targeting rules live in `FlipSwitch_Rule__c` (a Custom Object) so admins can create and modify them without a deployment.

### Rule types

#### User

Enable for specific users. `Rule_Value__c` is a semicolon-delimited list of User Ids:

```
005Dn000005abc1AAA;005Dn000005abc2AAA
```

#### Profile

Enable for an entire profile. `Rule_Value__c` is a semicolon-delimited list of Profile Ids:

```
00e000000000001AAA
```

#### Permission Set

Enable for users who hold a specific permission set. `Rule_Value__c` is a semicolon-delimited list of permission set API names:

```
Beta_Testers;Release_Team
```

#### Percentage

Enable for a percentage of users based on a deterministic hash. `Rule_Value__c` is an integer `0`–`100`:

```
20
```

See [Percentage Rollouts](#percentage-rollouts) for how the hash is calculated.

#### Segment

Enable when all specified context attributes match. `Rule_Value__c` is a JSON object — all key-value pairs must be present and equal in the evaluation context:

```json
{"region": "US", "tier": "Enterprise"}
```

Pass attributes in the builder:

```apex
FeatureFlag.flag('FEATURE')
    .withAttribute('region', 'US')
    .withAttribute('tier', 'Enterprise')
    .isEnabled();
```

#### Custom Field

Enable based on a single named attribute. `Rule_Value__c` is a JSON object with `field` and `value` keys:

```json
{"field": "account_type", "value": "Partner"}
```

#### Kill Switch

Immediately disables the flag regardless of all other rules. No `Rule_Value__c` needed. Set `Priority__c = 1` to ensure it always wins.

### Rule scheduling

Every rule supports optional `Start_Date__c` and `End_Date__c` fields. A rule is only evaluated while:

```
Start_Date__c ≤ NOW ≤ End_Date__c
```

Rules past their `End_Date__c` are automatically deactivated by `FeatureFlagExpirationJob` each night.

---

## Evaluation Order

FlipSwitch evaluates in this fixed priority order and short-circuits on the first match:

```
1. CMDT Is_Active__c = false            → KILL_SWITCH
2. Expiration_Date__c < TODAY           → EXPIRED
3. QA override (Override_All_Flags__c)  → QA_OVERRIDE
4. Kill_Switch rule (Priority__c ASC)   → KILL_SWITCH
5. Targeting rules (Priority__c ASC):
     User → Profile → Permission_Set
     → Segment → Custom_Field           → RULE_MATCH
     → Percentage
6. CMDT Default_Value__c                → DEFAULT
```

Rules with the same `Priority__c` are evaluated in insertion order. Lower number = higher precedence (1 beats 10).

---

## Kill Switch

A kill switch immediately disables a flag for all users with no deployment. There are two levels:

### CMDT-level

Set `Is_Active__c = false` on the `FlipSwitch_Flag__mdt` record and deploy via CI/CD. Suitable for permanent retirements.

### Runtime kill switch (instant, no deployment)

Via the admin UI **Kill Switch** tab, or directly in Apex:

```apex
// Disable immediately (also invalidates Platform Cache)
FeatureFlag.activateKillSwitch('NEW_CHECKOUT');

// Re-enable
FeatureFlag.deactivateKillSwitch('NEW_CHECKOUT');
```

Or create a `FlipSwitch_Rule__c` record manually:

| Field | Value |
|-------|-------|
| `Flag_Key__c` | `NEW_CHECKOUT` |
| `Rule_Type__c` | `Kill_Switch` |
| `Priority__c` | `1` |
| `Is_Active__c` | `true` |

The kill switch takes effect on the next evaluation — no cache TTL delay.

---

## Percentage Rollouts

FlipSwitch uses a **deterministic SHA-256 hash** to assign each user a consistent percentile:

```
percentile = SHA-256( userId + ':' + flagKey ) mod 100
```

Properties:
- Same user + same flag = same percentile every time, with no per-user storage
- Increasing the threshold from 10% to 20% preserves all users already in the treatment group
- Each flag hashes independently — a user in Flag A's 10% is not guaranteed to be in Flag B's 10%
- Changing the flag's `DeveloperName` reassigns all users (use a stable, permanent key)

To roll out to 20% of users, create a `Percentage` rule with `Rule_Value__c = 20`.

---

## Multi-Variant Experiments

### 1. Create variant records in `FlipSwitch_Variant__c`

| Name | Flag_Key__c | Variant_Key__c | Weight__c |
|------|---------------------|----------------|-----------|
| Control | HOMEPAGE_EXPERIMENT | control | 50 |
| Treatment A | HOMEPAGE_EXPERIMENT | treatment_a | 30 |
| Treatment B | HOMEPAGE_EXPERIMENT | treatment_b | 20 |

Weights across all variants for a given flag must sum to 100.

### 2. Add targeting rules with Variant_Value__c

Create targeting rules that return the appropriate variant key. For a full-population experiment, use a `Percentage` rule at 100% and set `Variant_Value__c` based on the weighted variant logic.

### 3. Evaluate the variant in Apex

```apex
String variant = FeatureFlag.flag('HOMEPAGE_EXPERIMENT')
    .forUser(someUserId)
    .fallback('control')
    .getVariant();

switch on variant {
    when 'control'     { renderOriginal();  }
    when 'treatment_a' { renderRedesign();  }
    when 'treatment_b' { renderBoldLayout();}
}
```

### 4. Evaluate the variant in LWC

```html
<c-feature-flag-variant flag-key="HOMEPAGE_EXPERIMENT" default-variant="control">
    <div slot="control">...</div>
    <div slot="treatment_a">...</div>
    <div slot="treatment_b">...</div>
</c-feature-flag-variant>
```

---

## Logging & Analytics

Every flag evaluation publishes a `FlipSwitch_Evaluation__e` Platform Event. Events are **buffered in memory** during the transaction and published in a single `EventBus.publish()` call when `FeatureFlag.flushEvaluations()` is called (or at the end of the builder chain).

A subscriber trigger handler aggregates events into `FlipSwitch_Metric__c` records:

| Field | Description |
|-------|-------------|
| `Flag_Key__c` | The flag evaluated (external ID for upsert) |
| `Evaluation_Count__c` | Running total of evaluations |
| `Unique_Users__c` | Running total of distinct users |
| `Last_Evaluated__c` | Most recent evaluation timestamp |
| `Variant_Distribution__c` | JSON map of variant key → count |

### Controlling logging

```apex
// Suppress for an entire transaction
FeatureFlag.suspendLogging();
doBulkProcessing();
FeatureFlag.resumeLogging();

// Suppress for one specific call
FeatureFlag.flag('MY_FLAG').silent().isEnabled();

// Disable for a specific user via Hierarchy Custom Setting
FlipSwitch_Settings__c s = FlipSwitch_Settings__c.getInstance(userId);
s.Is_Logging_Enabled__c = false;
upsert s;
```

### Sampling

Set `Log_Sampling_Rate__c` on the `FlipSwitch_Config.Default` CMDT record to a value between 0–100 to log only a percentage of evaluations. Default is `100` (log everything).

### Save methods

| Method | Behaviour | Best for |
|--------|-----------|----------|
| `EVENT_BUS` | Buffer in transaction, publish on flush | Normal usage |
| `QUEUEABLE` | Publish from a deferred `System.enqueueJob` | Avoiding Platform Event limits |
| `SYNCHRONOUS` | Direct `EventBus.publish()` per call | Debug and tests only |

---

## Platform Cache

FlipSwitch uses two cache tiers when a partition is configured:

| Tier | Scope | Content | TTL |
|------|-------|---------|-----|
| Org | Cross-session | CMDT flag definitions | 1 hour |
| Session | Per-user | Evaluation results | 1 hour |

If the partition is unavailable or not configured, all cache operations silently no-op and the framework falls back to direct SOQL queries. No configuration is required for the framework to function correctly.

**Setup:** Create a partition named `FlipSwitch` in **Setup → Platform Cache**, then set `Cache_Partition_Name__c` on `FlipSwitch_Config.Default` to `local.FlipSwitch`.

---

## Plugin Framework

Register post-evaluation hooks by implementing `FeatureFlagPlugin` and creating a `FlipSwitch_Plugin__mdt` record:

```apex
public class MyAnalyticsPlugin implements FeatureFlagPlugin {
    public void onEvaluate(FeatureFlagResult result, FeatureFlagContext ctx) {
        if (result.reason == FeatureFlagResult.REASON_KILL_SWITCH) {
            MyAlertService.notify('Kill switch hit: ' + ctx.flagKey);
        }
        MyAnalytics.track(ctx.flagKey, result.variant, ctx.userId);
    }
}
```

Register via CMDT (`FlipSwitch_Plugin.My_Analytics_Plugin.md-meta.xml`):

```xml
<CustomMetadata ...>
    <label>My Analytics Plugin</label>
    <values>
        <field>Class_Name__c</field>
        <value xsi:type="xsd:string">MyAnalyticsPlugin</value>
    </values>
    <values>
        <field>Is_Enabled__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Priority__c</field>
        <value xsi:type="xsd:double">10</value>
    </values>
</CustomMetadata>
```

Plugin errors are silently absorbed — a failing plugin never breaks flag evaluation.

### FeatureFlagContext (available in plugins)

| Property | Type | Description |
|----------|------|-------------|
| `userId` | `Id` | The user being evaluated |
| `profileId` | `Id` | The user's profile |
| `permissionSetNames` | `Set<String>` | Active permission set API names |
| `customAttributes` | `Map<String, Object>` | Attributes passed via `.withAttribute()` |
| `flagKey` | `String` | The flag being evaluated |
| `scenario` | `String` | Business scenario tag (if set) |

---

## Architecture

### Storage model

```
FlipSwitch_Flag__mdt           ← flag definitions — deploy via CI/CD
FlipSwitch_Config__mdt    ← framework configuration — deploy via CI/CD
FlipSwitch_Plugin__mdt    ← plugin registry — deploy via CI/CD
FlipSwitch_Rule__c        ← runtime targeting rules — admin editable
FlipSwitch_Variant__c     ← variant weight definitions — admin editable
FlipSwitch_Assignment__c  ← sticky variant overrides — admin editable
FlipSwitch_Metric__c      ← aggregated analytics — written by event trigger
FlipSwitch_Settings__c    ← hierarchy custom setting — per user/profile config
FlipSwitch_Evaluation__e  ← async evaluation log (Platform Event)
```

### Class map

```
FeatureFlag                      ← public entry point + @AuraEnabled methods
├── FeatureFlagBuilder           ← fluent single-flag builder
├── FeatureFlagBatchBuilder      ← multi-flag builder (single SOQL)
├── FeatureFlagEvaluator         ← core evaluation engine + SOQL loading
├── FeatureFlagContext           ← evaluation context (user, profile, perm sets)
├── FeatureFlagResult            ← immutable result wrapper
├── FeatureFlagCache             ← Platform Cache (graceful no-op fallback)
├── FeatureFlagLogger            ← Platform Event buffering + SaveMethod enum
├── FeatureFlagHash              ← SHA-256 deterministic percentile
├── FeatureFlagHandler           ← callback interface (whenEnabled/whenDisabled)
├── FeatureFlagPlugin            ← extensibility interface (post-evaluation hooks)
├── FeatureFlagException         ← custom exception (internal use only)
├── FeatureFlagFlowAction        ← @InvocableMethod for Flows (bulkified)
├── FeatureFlagExpirationJob     ← Schedulable — daily rule cleanup
├── FeatureFlagEvaluationTriggerHandler ← Platform Event → Metric__c aggregation
└── CallableFeatureFlag          ← System.Callable adapter (zero-dependency)
```

### LWC map

```
featureFlagGate      ← named-slot conditional rendering (wire adapter)
featureFlagVariant   ← dynamic slot by variant key (wire adapter)
featureFlagService   ← imperative JS module with 30s in-memory cache
featureFlagAdmin     ← admin dashboard (flag list, rule builder, kill switch)
```

---

## Development Setup

### Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- A Salesforce DevHub org with unlocked package creation enabled
- Node.js 20+

### One-command setup

```bash
git clone https://github.com/Lastonedown86/flipswitch.git
cd flipswitch
npm install
bash scripts/create-scratch-org.sh flipswitch-dev 30
sf org open --target-org flipswitch-dev
```

### Manual steps

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

### npm scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run LWC Jest tests with coverage |
| `npm run lint` | ESLint on all LWC components |
| `npm run prettier` | Auto-format all HTML/JS/CSS/JSON |
| `npm run prettier:check` | Check formatting (used in CI) |
| `npm run scratch:create` | Create a `flipswitch-dev` scratch org |
| `npm run scratch:deploy` | Deploy source to `flipswitch-dev` |
| `npm run scratch:test` | Run Apex tests on `flipswitch-dev` with coverage |

### Create a new package version

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

---

## Testing

### Apex tests

```bash
sf apex run test \
  --target-org flipswitch-dev \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 20
```

Coverage target: **90%+**. Test classes:

| Test class | What it covers |
|------------|----------------|
| `FeatureFlagTest` | Static API, factory methods, transaction controls, `@AuraEnabled` methods, kill switch lifecycle |
| `FeatureFlagBuilderTest` | All builder methods, fallback, silent, handlers, evaluate terminal |
| `FeatureFlagBatchBuilderTest` | Single-SOQL batch, shared context, scenario tags, SOQL governor limits |
| `FeatureFlagEvaluatorTest` | All rule types, priority ordering, QA overrides, expiration, circuit breaker |
| `FeatureFlagHashTest` | Determinism, range [0–99], distribution uniformity across 200 users |
| `FeatureFlagCacheTest` | Put/get/miss/remove, graceful fallback when partition unavailable |
| `FeatureFlagFlowActionTest` | Single + bulk invocation, blank key error, explicit user ID |
| `FeatureFlagExpirationJobTest` | Rule deactivation, job scheduling, bulk expiry across 5 rules |
| `FeatureFlagEvaluationTriggerHandlerTest` | Metric create/upsert, blank key skip, empty list handling |

### LWC Jest tests

```bash
npm test           # single run with coverage report
npm run test:watch # watch mode during development
```

Jest test files live in `__tests__/` directories alongside each LWC component.

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
