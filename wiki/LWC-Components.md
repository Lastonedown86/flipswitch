# LWC Components

## featureFlagGate

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

## featureFlagVariant

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

## featureFlagService

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

## featureFlagAdmin

Full admin dashboard available as a Lightning App Page. Three tabs:

| Tab | Purpose |
|-----|---------|
| **Flags** | Datatable of all `FlipSwitch_Flag__mdt` records — type, active status, default value, category, expiry |
| **Add Rule** | Form to create `FlipSwitch_Rule__c` targeting rules without opening Object Manager |
| **Emergency Disable** | One-click emergency disable or re-enable for any flag by key |
