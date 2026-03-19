# Testing

## Apex tests

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
| `FeatureFlagTest` | Static API, factory methods, transaction controls, `@AuraEnabled` methods, emergency disable lifecycle |
| `FeatureFlagBuilderTest` | All builder methods, fallback, silent, handlers, evaluate terminal |
| `FeatureFlagBatchBuilderTest` | Single-SOQL batch, shared context, scenario tags, SOQL governor limits |
| `FeatureFlagEvaluatorTest` | All rule types, priority ordering, QA overrides, expiration, circuit breaker |
| `FeatureFlagHashTest` | Determinism, range [0–99], distribution uniformity across 200 users |
| `FeatureFlagCacheTest` | Put/get/miss/remove, graceful fallback when partition unavailable |
| `FeatureFlagFlowActionTest` | Single + bulk invocation, blank key error, explicit user ID |
| `FeatureFlagExpirationJobTest` | Rule deactivation, job scheduling, bulk expiry across 5 rules |
| `FeatureFlagEvaluationTriggerHandlerTest` | Metric create/upsert, blank key skip, empty list handling |

## LWC Jest tests

```bash
npm test           # single run with coverage report
npm run test:watch # watch mode during development
```

Jest test files live in `__tests__/` directories alongside each LWC component.
