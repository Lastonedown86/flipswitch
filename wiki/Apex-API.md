# Apex API

## Static API

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

## Fluent Builder API

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
System.debug(result.reason);    // RULE_MATCH | DEFAULT | EMERGENCY_DISABLE | EXPIRED | ERROR

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

### Builder method reference

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

## Batch API

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

## Code-Defined Flags

Flags can be defined directly in Apex code. When a code-defined flag is evaluated for the first time, FlipSwitch **automatically registers** it in the `FlipSwitch_Flag_Registry__c` custom object so it appears in the admin dashboard.

> **Which approach should I use?**
>
> - **CMDT (`FlipSwitch_Flag__mdt`)** — flags that need CI/CD-deployable definitions, pre-configured targeting rules, and full lifecycle management. Best for release flags, ops flags, and flags shared across teams.
> - **Code-Defined (Registry)** — flags defined inline in Apex. Best for developer-owned experiments, feature-in-progress gates, and prototype flags that may later be promoted to CMDT. Registered flags default to **disabled** until an admin activates them.

### Implicit Registration

Simply evaluate a flag key that doesn't exist in CMDT. FlipSwitch auto-registers it on first evaluation:

```apex
// First call: auto-registers 'MY_NEW_FEATURE' → result.reason = 'NOT_CONFIGURED'
// After admin activates it in the dashboard → returns true/false based on rules
if (FeatureFlag.isEnabled('MY_NEW_FEATURE')) {
    // new behavior
}

// Use .fallback() to control behavior before activation
Boolean enabled = FeatureFlag.flag('MY_NEW_FEATURE')
    .fallback(true)       // returns true even when NOT_CONFIGURED
    .isEnabled();
```

### Inline Declaration (Recommended)

Use the fluent `define()` builder to declare a flag with metadata — type, category, description, and default value. The `register()` terminal method writes to the registry using **fill-not-overwrite** semantics: it never overwrites fields that an admin has already set.

```apex
FeatureFlag.define('CHECKOUT_V2')
    .type('Boolean')
    .defaultValue('false')
    .category('Release')
    .description('New checkout flow experiment')
    .expiresOn(Date.newInstance(2025, 6, 30))
    .register();
```

### One-Liner Registration

Register a flag key without metadata:

```apex
FeatureFlag.register('MY_FEATURE');
```

### How It Works

1. On first evaluation, if the flag key is not found in CMDT, FlipSwitch calls `FeatureFlagRegistry.registerIfNew()`.
2. The registry upserts a `FlipSwitch_Flag_Registry__c` record using `Flag_Key__c` as an External ID (concurrency-safe).
3. The flag appears in the admin dashboard with source = **Code** and `Is_Active__c = false`.
4. An admin can activate the flag, configure targeting rules, and optionally **Promote** it to CMDT for CI/CD deployment.
5. Once a matching CMDT record exists, the CMDT definition takes precedence.

### Define Builder API Reference

| Method | Return Type | Description |
|--------|-----------|-------------|
| `FeatureFlag.define(String flagKey)` | `FeatureFlagDefinition` | Start a flag definition builder |
| `.type(String)` | `FeatureFlagDefinition` | Set flag type: `Boolean`, `Variant`, or `Percentage` |
| `.defaultValue(String)` | `FeatureFlagDefinition` | Set the default evaluation value |
| `.category(String)` | `FeatureFlagDefinition` | Set the dashboard grouping category |
| `.description(String)` | `FeatureFlagDefinition` | Set a human-readable description |
| `.expiresOn(Date)` | `FeatureFlagDefinition` | Set an auto-expiration date |
| `.register()` | `void` | **Terminal** — upsert to registry (fill-not-overwrite) |
| `FeatureFlag.register(String flagKey)` | `void` | One-liner registration (no metadata) |

## Transaction Controls

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

## FeatureFlagResult

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
| `EMERGENCY_DISABLE` | Flag or an `Emergency_Disable` rule forced it off |
| `EXPIRED` | `Expiration_Date__c` has passed |
| `QA_OVERRIDE` | `Override_All_Flags__c` hierarchy setting is active |
| `CACHE_HIT` | Result was returned from Platform Cache |
| `ERROR` | Evaluation error; safe default returned (circuit breaker) |
| `NOT_CONFIGURED` | Flag exists only in the runtime registry and is not yet activated |

## FeatureFlagHandler

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

## Callable Adapter

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
