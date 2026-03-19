# Logging & Analytics

Every flag evaluation publishes a `FlipSwitch_Evaluation__e` Platform Event. Events are **buffered in memory** during the transaction and published in a single `EventBus.publish()` call when `FeatureFlag.flushEvaluations()` is called (or at the end of the builder chain).

A subscriber trigger handler aggregates events into `FlipSwitch_Metric__c` records:

| Field | Description |
|-------|-------------|
| `Flag_Key__c` | The flag evaluated (external ID for upsert) |
| `Evaluation_Count__c` | Running total of evaluations |
| `Unique_Users__c` | Running total of distinct users |
| `Last_Evaluated__c` | Most recent evaluation timestamp |
| `Variant_Distribution__c` | JSON map of variant key → count |

## Controlling logging

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

## Sampling

Set `Log_Sampling_Rate__c` on the `FlipSwitch_Config.Default` CMDT record to a value between 0–100 to log only a percentage of evaluations. Default is `100` (log everything).

## Save methods

| Method | Behaviour | Best for |
|--------|-----------|----------|
| `EVENT_BUS` | Buffer in transaction, publish on flush | Normal usage |
| `QUEUEABLE` | Publish from a deferred `System.enqueueJob` | Avoiding Platform Event limits |
| `SYNCHRONOUS` | Direct `EventBus.publish()` per call | Debug and tests only |
