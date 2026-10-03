# Multi-Variant Experiments

## 1. Create variant records in `FlipSwitch_Variant__c`

| Name | Flag_Key__c | Variant_Key__c | Weight__c |
|------|---------------------|----------------|-----------|
| Control | HOMEPAGE_EXPERIMENT | control | 50 |
| Treatment A | HOMEPAGE_EXPERIMENT | treatment_a | 30 |
| Treatment B | HOMEPAGE_EXPERIMENT | treatment_b | 20 |

Weights across all variants for a given flag must sum to 100.

## 2. Add targeting rules with Variant_Value__c

Create targeting rules that return the appropriate variant key. For a full-population experiment, use a `Percentage` rule at 100% and set `Variant_Value__c` based on the weighted variant logic.

## 3. Evaluate the variant in Apex

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

## 4. Evaluate the variant in LWC

```html
<c-feature-flag-variant flag-key="HOMEPAGE_EXPERIMENT" default-variant="control">
    <div slot="control">...</div>
    <div slot="treatment_a">...</div>
    <div slot="treatment_b">...</div>
</c-feature-flag-variant>
```
