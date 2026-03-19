# Architecture

## Storage model

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

## Class map

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

## LWC map

```
featureFlagGate      ← named-slot conditional rendering (wire adapter)
featureFlagVariant   ← dynamic slot by variant key (wire adapter)
featureFlagService   ← imperative JS module with 30s in-memory cache
featureFlagAdmin     ← admin dashboard (flag list, rule builder, emergency disable)
```
