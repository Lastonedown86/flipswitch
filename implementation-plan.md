# FlipSwitch: Comprehensive Implementation Plan

## Context

FlipSwitch is a Salesforce Progressive Delivery Feature Flag Framework — unlocked package, MIT license, GitHub distribution (same model as NebulaLogger). It solves the "all-or-nothing deployment" problem in Salesforce by bringing feature flags, percentage rollouts, user targeting, multi-variant experiments, and kill switches to Apex, LWC, and Flows.

**Current state**: Only `plan.md` (full technical spec) and `CLAUDE.md` exist. Zero code. This plan takes the project from 0 to a shippable v1 unlocked package.

**NebulaLogger reference**: Patterns adopted from https://github.com/jongpie/NebulaLogger — API v64.0, no namespace, transaction buffering, plugin framework via CMDT, System.Callable adapter, GitHub Actions CI/CD, semantic versioning.

---

## Phase 0: Project Scaffold

**Goal**: Bootstrap the SFDX project structure and tooling config so all subsequent phases have a foundation.

### Files to Create

```
sfdx-project.json
config/
  project-scratch-def.json
.github/
  workflows/
    build.yml
scripts/
  create-scratch-org.sh
  run-tests.sh
.forceignore
.eslintrc.json
.prettierrc
.gitignore
LICENSE               (MIT)
README.md
```

### `sfdx-project.json` Key Config
```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true,
      "package": "FlipSwitch",
      "versionName": "Version 1.0.0",
      "versionNumber": "1.0.0.NEXT",
      "versionDescription": "Progressive Delivery Feature Flag Framework"
    }
  ],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "64.0",
  "packageAliases": {}
}
```

### `config/project-scratch-def.json`
- Edition: Developer, features: `["PlatformCache", "Communities"]`
- orgPreferences: `{ "s1DesktopEnabled": true }`

### GitHub Actions `build.yml` (NebulaLogger pattern — 4 stages)
1. **Code Quality**: ESLint (LWC), Prettier check, SFDX Scanner (PMD Apex)
2. **LWC Tests**: Jest with coverage reporting to Codecov
3. **Apex Tests**: Create scratch org → deploy → run tests async + sync → assert 90%+ coverage → delete scratch org
4. **Package**: On `main` branch → promote package version; on feature branches → create beta

### Verification
- `sf project validate --source-dir force-app` passes
- `npm run lint` passes (ESLint + Prettier)
- GitHub Actions workflow file is syntactically valid

---

## Phase 1: Data Model & Storage

**Goal**: All Salesforce metadata definitions — CMDT, Custom Objects, Platform Event, Custom Settings.

**Depends on**: Phase 0 (sfdx-project.json must exist)

### Files to Create

```
force-app/main/default/
├── customMetadata/
│   ├── Feature_Flag__mdt.object-meta.xml
│   ├── Feature_Flag_Config__mdt.object-meta.xml
│   └── Feature_Flag_Plugin__mdt.object-meta.xml
├── customSettings/
│   └── Feature_Flag_Settings__c.object-meta.xml
├── objects/
│   ├── Feature_Flag_Rule__c/
│   │   ├── Feature_Flag_Rule__c.object-meta.xml
│   │   └── fields/  (Rule_Type__c, Rule_Value__c, Feature_Flag_Key__c, Priority__c, Variant_Value__c, Is_Active__c, Start_Date__c, End_Date__c)
│   ├── Feature_Flag_Variant__c/
│   │   └── fields/  (Feature_Flag_Key__c, Variant_Key__c, Weight__c, Payload__c)
│   ├── Feature_Flag_Assignment__c/
│   │   └── fields/  (Feature_Flag_Key__c, User_Id__c, Assigned_Variant__c)
│   │   (unique compound index on Feature_Flag_Key__c + User_Id__c)
│   └── Feature_Flag_Metric__c/
│       └── fields/  (Flag_Key__c, Evaluation_Count__c, Unique_Users__c, Variant_Distribution__c)
└── platformEventChannelMembers/
    └── Feature_Flag_Evaluation__e.object-meta.xml
        (fields: Flag_Key__c, User_Id__c, Result__c, Context__c, Timestamp__c, Evaluation_Reason__c, Scenario__c)
```

### Key Field Details

**`Feature_Flag__mdt`** fields:
- `Type__c` picklist: `Boolean | Variant | Percentage`
- `Default_Value__c` Text(255)
- `Is_Active__c` Checkbox (default true)
- `Expiration_Date__c` Date
- `Category__c` Text(100)
- `Description__c` LongTextArea

**`Feature_Flag_Rule__c`** picklist values for `Rule_Type__c`:
`User | Profile | Permission_Set | Percentage | Custom_Field | Segment | Kill_Switch`

**`Feature_Flag_Settings__c`** (Hierarchy):
- `Is_Logging_Enabled__c` Checkbox (default true)
- `Override_All_Flags__c` Picklist: `None | Enable_All | Disable_All`
- `Default_Save_Method__c` Picklist: `EVENT_BUS | QUEUEABLE | SYNCHRONOUS`

**`Feature_Flag_Config__mdt`** records (framework config):
- `Log_Sampling_Rate__c` Number (default 100 = log everything)
- `Cache_Partition_Name__c` Text (default "local.FlipSwitch")
- `Circuit_Breaker_Enabled__c` Checkbox (default true)

### Permission Sets
```
permissionsets/
├── Feature_Flag_Admin.permissionset-meta.xml   (CRUD on all objects + CMDT)
└── Feature_Flag_User.permissionset-meta.xml    (Read on CMDT, no object access)
```

### Verification
- `sf project deploy start --target-org <scratch>` succeeds with no errors
- All objects visible in Setup → Object Manager
- Platform Event channel visible in Setup → Platform Events

---

## Phase 2: Apex Service Layer + Test Classes

**Goal**: Full dual API (static + fluent), evaluation engine, cache, logging, hashing. All test classes achieving 90%+ coverage.

**Depends on**: Phase 1 (metadata objects must exist for SOQL in tests)

### Production Classes

#### `force-app/main/default/classes/FeatureFlagException.cls`
- Extends `Exception` — created first as a dependency of all other classes

#### `force-app/main/default/classes/FeatureFlagResult.cls`
```apex
public class FeatureFlagResult {
    public Boolean isEnabled;
    public String variant;
    public String reason;           // RULE_MATCH | DEFAULT | KILL_SWITCH | EXPIRED | CACHE_HIT | ERROR
    public Map<String,Object> payload;
    // Constructor + factory methods: enabled(variant), disabled(), fromDefault()
}
```

#### `force-app/main/default/classes/FeatureFlagHandler.cls`
```apex
public interface FeatureFlagHandler {
    void handle();
}
```

#### `force-app/main/default/classes/FeatureFlagPlugin.cls`
```apex
public interface FeatureFlagPlugin {
    void onEvaluate(FeatureFlagResult result, FeatureFlagContext ctx);
}
```

#### `force-app/main/default/classes/FeatureFlagContext.cls`
- Internal class (not instantiated by consumers directly)
- Fields: `userId`, `profileId`, `permissionSetIds`, `customAttributes Map<String,Object>`, `scenario`
- Static factory: `FeatureFlagContext.forUser(Id userId)` — auto-loads profile + permission sets via SOQL
- `FeatureFlagContext.forRunningUser()` — uses `UserInfo.getUserId()`

#### `force-app/main/default/classes/FeatureFlagHash.cls`
```apex
public class FeatureFlagHash {
    // Returns integer 0-99 for consistent percentage-based rollout
    public static Integer getHashedPercentile(Id userId, String flagKey) {
        Blob input = Blob.valueOf(userId + ':' + flagKey);
        Blob digest = Crypto.generateDigest('SHA-256', input);
        String hex = EncodingUtil.convertToHex(digest);
        Long hashVal = Long.valueOf('0x' + hex.substring(0, 8));
        return Math.abs(Integer.valueOf(Math.mod(hashVal, 100)));
    }
}
```

#### `force-app/main/default/classes/FeatureFlagCache.cls`
- Org-level cache: stores `Feature_Flag__mdt` definitions (key: `flagKey`)
- Session-level cache: stores per-user evaluation results (key: `userId:flagKey`)
- `get(String key)`, `put(String key, Object value)`, `remove(String key)`, `clear()`
- Graceful try/catch: if `Cache.Org.put()` throws (partition not configured), silently skip
- Cache invalidation: called by `Feature_Flag_Rule__c` trigger on insert/update/delete

#### `force-app/main/default/classes/FeatureFlagLogger.cls`
NebulaLogger-inspired transaction buffering:
```apex
public class FeatureFlagLogger {
    private static List<Feature_Flag_Evaluation__e> buffer = new List<>();
    private static Boolean suspended = false;
    private static FeatureFlag.SaveMethod saveMethod = FeatureFlag.SaveMethod.EVENT_BUS;

    public static void log(FeatureFlagResult result, FeatureFlagContext ctx) { /* buffers */ }
    public static void suspend() { suspended = true; }
    public static void resume() { suspended = false; }
    public static void flush() { /* publishes buffer as single EventBus.publish() call */ }
    // Sampling: read Feature_Flag_Config__mdt.Log_Sampling_Rate__c, skip if random > rate
}
```

#### `force-app/main/default/classes/FeatureFlagEvaluator.cls`
Core engine — called by both builders. Evaluation order:
1. Load `Feature_Flag__mdt` via CMDT query (or cache hit)
2. Kill switch: `Is_Active__c = false` → return `FeatureFlagResult.disabled()` with reason `KILL_SWITCH`
3. Expiration: `Expiration_Date__c != null && Expiration_Date__c < Date.today()` → return disabled, reason `EXPIRED`
4. Check `Feature_Flag_Settings__c.Override_All_Flags__c` (QA override)
5. Check for `Kill_Switch` rule type in `Feature_Flag_Rule__c`
6. Evaluate rules by `Priority__c` ASC:
   - `User`: `Rule_Value__c` contains context.userId
   - `Profile`: `Rule_Value__c` contains context.profileId
   - `Permission_Set`: context.permissionSetIds intersection
   - `Segment`: custom attribute matching (JSON key-value pairs in `Rule_Value__c`)
   - `Custom_Field`: evaluate field value expression
   - `Percentage`: `FeatureFlagHash.getHashedPercentile() < Integer.valueOf(Rule_Value__c)`
7. No match → return `Default_Value__c`, reason `DEFAULT`
8. Circuit breaker: wrap entire method in try/catch, on any exception return default with reason `ERROR`

#### `force-app/main/default/classes/FeatureFlagBuilder.cls`
Fluent builder returned by `FeatureFlag.flag()`:
```apex
public class FeatureFlagBuilder {
    private String flagKey;
    private Id userId;
    private Map<String,Object> attributes = new Map<String,Object>();
    private Object fallbackValue;
    private Boolean silent = false;
    private String scenario;
    private FeatureFlagHandler enabledHandler;
    private FeatureFlagHandler disabledHandler;

    // Fluent methods (return `this`):
    public FeatureFlagBuilder forUser(Id userId)
    public FeatureFlagBuilder withAttribute(String key, Object value)
    public FeatureFlagBuilder withAttributes(Map<String,Object> attrs)
    public FeatureFlagBuilder fallback(Object value)
    public FeatureFlagBuilder silent()
    public FeatureFlagBuilder inScenario(String scenario)
    public FeatureFlagBuilder whenEnabled(FeatureFlagHandler handler)
    public FeatureFlagBuilder whenDisabled(FeatureFlagHandler handler)

    // Terminal methods:
    public Boolean isEnabled()          // evaluate() then return result.isEnabled
    public String getVariant()          // evaluate() then return result.variant
    public Map<String,Object> getPayload()
    public FeatureFlagResult evaluate() // calls FeatureFlagEvaluator, logs, runs plugins
    public void execute()               // calls enabledHandler or disabledHandler after evaluate()
}
```

#### `force-app/main/default/classes/FeatureFlagBatchBuilder.cls`
Multi-flag builder returned by `FeatureFlag.flags()`:
- Single SOQL: loads ALL `Feature_Flag_Rule__c` records for all requested flag keys in one query
- `forUser()`, `withAttribute()` — shared context for all flags
- `evaluateAll()` → `Map<String, FeatureFlagResult>` — calls evaluator per flag using pre-loaded rules

#### `force-app/main/default/classes/FeatureFlag.cls`
Entry point with static API + factory + transaction controls:
```apex
public class FeatureFlag {
    public enum SaveMethod { EVENT_BUS, QUEUEABLE, SYNCHRONOUS }

    // Static convenience API
    public static Boolean isEnabled(String flagKey)
    public static String getVariant(String flagKey)

    // Factory methods
    public static FeatureFlagBuilder flag(String flagKey)
    public static FeatureFlagBatchBuilder flags(String... flagKeys)

    // Transaction controls (NebulaLogger pattern)
    public static void suspendLogging()
    public static void resumeLogging()
    public static void flushEvaluations()
    public static void setScenario(String scenario)
    public static void setSaveMethod(SaveMethod method)
}
```

#### `force-app/main/default/classes/CallableFeatureFlag.cls`
Implements `System.Callable` for loose coupling (ISV pattern from NebulaLogger):
```apex
public class CallableFeatureFlag implements System.Callable {
    public Object call(String action, Map<String, Object> args) {
        // Dispatch: 'isEnabled', 'getVariant', 'evaluate', 'setScenario'
    }
}
```

#### `force-app/main/default/classes/FeatureFlagFlowAction.cls`
```apex
public class FeatureFlagFlowAction {
    public class FlowInput {
        @InvocableVariable(label='Flag Key' required=true) public String flagKey;
        @InvocableVariable(label='User Id') public String userId;
    }
    public class FlowOutput {
        @InvocableVariable public Boolean isEnabled;
        @InvocableVariable public String variant;
    }
    @InvocableMethod(label='Evaluate Feature Flag' category='Feature Flags')
    public static List<FlowOutput> evaluate(List<FlowInput> inputs)
    // Bulkified: batch evaluates all inputs, single SOQL via FeatureFlagBatchBuilder
}
```

#### `force-app/main/default/classes/FeatureFlagExpirationJob.cls`
```apex
public class FeatureFlagExpirationJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        // Query Feature_Flag_Rule__c where End_Date__c <= NOW, deactivate
        // Query expired flags (read from Metadata API or custom config object)
        // Send Custom Notification to flag owner
    }
}
```

### Test Classes (target: 90%+ coverage each)

All test classes in: `force-app/main/default/classes/tests/`

#### `FeatureFlagHashTest.cls`
- `testHashReturnsValueBetween0And99()` — assert result in [0, 99]
- `testSameInputYieldsSameOutput()` — determinism: call 10x with same args
- `testDifferentInputsYieldDifferentResults()` — 100 unique user IDs, assert distribution
- `testNullSafety()` — null userId, null flagKey → no exception, returns integer

#### `FeatureFlagCacheTest.cls`
- `testCachePutAndGet()` — put value, get it back
- `testCacheMissReturnsNull()` — get non-existent key returns null
- `testCacheRemove()` — put then remove, get returns null
- `testGracefulFallbackWhenPartitionUnavailable()` — simulate unavailable cache, no exception thrown
- `testCacheClear()` — put multiple, clear, all return null

#### `FeatureFlagEvaluatorTest.cls`
```
testKillSwitchDisabledFlag()          — Is_Active__c = false → KILL_SWITCH reason
testExpiredFlagReturnsDefault()       — Expiration_Date__c in past → EXPIRED reason
testUserRuleMatchReturnsVariant()     — user ID in rule → RULE_MATCH
testProfileRuleMatch()
testPermissionSetRuleMatch()
testPercentageRuleConsistency()       — same user+flag → same result across 10 calls
testPercentageRuleDistribution()      — 1000 users at 50% → ~40-60% enabled
testNoRuleMatchReturnsDefault()       — no rules → DEFAULT reason
testRulePriorityOrder()               — lower priority number wins when multiple match
testCircuitBreakerReturnsDefault()    — force exception in evaluator → no throw, returns default
testQAOverrideEnableAll()             — Override_All_Flags__c = Enable_All → all enabled
testQAOverrideDisableAll()
testCustomKillSwitchRule()            — Rule_Type__c = Kill_Switch → immediately disabled
```

#### `FeatureFlagBuilderTest.cls`
```
testIsEnabledReturnsBooleanTrue()
testIsEnabledReturnsBooleanFalse()
testGetVariantReturnsString()
testFallbackOverridesDefault()
testForUserSetsEvaluationContext()
testWithAttributePassedToEvaluator()
testSilentSuppressesLogging()
testWhenEnabledCallbackFires()
testWhenDisabledCallbackFires()
testExecuteCallsCorrectHandler()
testInScenarioTagsEvaluation()
testChainedBuilderReturnsSelf()       — each fluent method returns FeatureFlagBuilder
```

#### `FeatureFlagBatchBuilderTest.cls`
```
testEvaluateAllReturnMapWithAllKeys()
testSingleSOQLForMultipleFlags()      — assert Limits.getQueries() = 1 for N flags
testSharedContextAppliedToAllFlags()
testBatchWithMixedRuleTypes()
testEmptyFlagListReturnsEmptyMap()
```

#### `FeatureFlagTest.cls` (entry point static API + transaction controls)
```
testStaticIsEnabled()
testStaticGetVariant()
testFlagFactoryReturnsBuilder()
testFlagsFactoryReturnsBatchBuilder()
testSuspendLoggingPreventsPublish()
testResumeLoggingRestoresPublish()
testFlushEvaluationsBulkPublishes()   — verify EventBus.publish called once, not N times
testSetScenarioTagsSubsequentCalls()
testSaveMethodEnum()
```

#### `FeatureFlagFlowActionTest.cls`
```
testSingleFlagEvaluation()
testBulkFlagEvaluation()              — 200 input records, verify all outputs populated
testNullUserIdDefaultsToRunningUser()
```

---

## Phase 3: Flow Support

**Depends on**: Phase 2 (`FeatureFlagFlowAction.cls` written in Phase 2)

Phase 3 adds supporting artifacts:

- `FeatureFlagFlowActionTest.cls` (if not completed in Phase 2)
- Sample Flow metadata in `force-app/main/default/flows/` demonstrating a Decision element
- `docs/flows.md` — admin guide showing how to wire the invocable action in Flow Builder

### Verification
- Flow action appears in Flow Builder under "Feature Flags" category
- Bulk collection flow (200 records) runs without hitting SOQL/DML governor limits
- Decision element correctly routes on `isEnabled` output

---

## Phase 4: LWC Components

**Depends on**: Phase 2 (Apex `@AuraEnabled` methods on `FeatureFlag.cls`)

### Files per Component

Each LWC component:
```
lwc/<componentName>/
├── <componentName>.html
├── <componentName>.js
├── <componentName>.css
├── <componentName>.js-meta.xml
└── __tests__/
    └── <componentName>.test.js
```

#### `featureFlagGate` — Conditional rendering
- **html**: Two named slots: `<slot name="enabled">` and `<slot name="disabled">`
- **js**: `@api flagKey`, `@wire(evaluateFlag, {flagKey: '$flagKey'}) wiredResult`; computed `get isEnabled()` toggles slot visibility
- **Required AuraEnabled method**: `@AuraEnabled(cacheable=true) static Boolean isEnabled(String flagKey)`

#### `featureFlagVariant` — Multi-variant rendering
- **html**: Dynamic slot rendering per variant key using `if:true`
- **js**: `@api flagKey`, wired to `@AuraEnabled(cacheable=true) static String getVariant(String flagKey)`

#### `featureFlagService` — JS service module
- Exports `isEnabled(flagKey)` and `getVariant(flagKey)` functions
- Batch-evaluates multiple flags into a single Apex call
- In-memory Map cache with configurable TTL for client-side dedup
- Usage: `import { isEnabled } from 'c/featureFlagService'`

#### `featureFlagAdmin` — Admin dashboard
- **Tabs**: Flag List | Flag Detail | Evaluation Logs | Rule Builder
- **Flag List**: Datatable of all `Feature_Flag__mdt` records + active rule counts
- **Kill Switch**: One-click button → Apex inserts `Feature_Flag_Rule__c` with `Rule_Type__c = 'Kill_Switch'`
- **Rule Builder**: Lightning Input fields → saves new `Feature_Flag_Rule__c` record
- **Evaluation Logs**: Datatable of Platform Event log records with flag/date filtering
- Hosted via `flexipages/Feature_Flag_Admin_App.flexipage-meta.xml` + `tabs/Feature_Flags.tab-meta.xml`

### LWC Test Pattern (Jest)
```js
// featureFlagGate.test.js
import { createElement } from 'lwc';
import FeatureFlagGate from 'c/featureFlagGate';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';

describe('featureFlagGate', () => {
    it('renders enabled slot when flag is on', () => { ... });
    it('renders disabled slot when flag is off', () => { ... });
    it('handles wire error gracefully', () => { ... });
});
```

### `package.json` for LWC tooling
```json
{
  "scripts": {
    "lint": "eslint force-app/main/default/lwc",
    "test:unit": "lwc-jest --coverage"
  },
  "devDependencies": {
    "@salesforce/sfdx-lwc-jest": "latest",
    "eslint": "latest",
    "prettier": "latest"
  }
}
```

### Verification
- `npm test` — all Jest tests pass
- `npm run lint` — zero ESLint errors
- Admin component deploys to scratch org and renders in Lightning App Builder

---

## Phase 5: Safety & Observability

**Depends on**: Phases 1–4

### Kill Switch Runtime Rule
- Supported via `Rule_Type__c = 'Kill_Switch'` in `FeatureFlagEvaluator` (implemented in Phase 2)
- Admin UI button (Phase 4) creates this rule without any deployment
- Instant effect: next evaluation hits the rule before any other targeting logic

### Auto-Expiration (`FeatureFlagExpirationJob.cls`)
- Schedule: daily at midnight `'0 0 0 * * ?'`
- Logic: query `Feature_Flag_Rule__c` where `End_Date__c <= NOW`, set `Is_Active__c = false`
- For CMDT-based flag definitions: document as manual step (CMDT cannot be DML'd at runtime)
- Notification: `Messaging.sendEmail()` or Custom Notification to flag category owner

### Circuit Breaker
- Already in `FeatureFlagEvaluator.cls` try/catch (implemented in Phase 2)
- Logs exception via `FeatureFlagLogger` with reason `ERROR`
- Returns `Default_Value__c` cast to appropriate type — caller never sees an exception
- Toggled via `Feature_Flag_Config__mdt.Circuit_Breaker_Enabled__c` (disable for debugging)

### Evaluation Analytics
- Trigger on `Feature_Flag_Evaluation__e` platform event
- Handler upserts `Feature_Flag_Metric__c`: evaluation count, variant distribution JSON, unique user count
- Standard Salesforce Reports on `Feature_Flag_Metric__c` power experiment analysis dashboards

### Files Added in Phase 5
```
force-app/main/default/
├── triggers/
│   └── FeatureFlagEvaluationTrigger.trigger
├── classes/
│   └── FeatureFlagEvaluationTriggerHandler.cls
└── classes/tests/
    ├── FeatureFlagExpirationJobTest.cls
    └── FeatureFlagEvaluationTriggerHandlerTest.cls
```

### Verification
- Create flag with `Expiration_Date__c = yesterday`, run job, assert rule is deactivated
- Trigger kill switch via admin UI, verify next evaluation returns disabled immediately
- Force evaluator exception, assert caller receives default value with no propagated exception

---

## Phase 6: Package & Distribution

**Depends on**: All phases complete with 90%+ test coverage

### Steps

1. **Create DevHub-connected package**:
   ```bash
   sf config set target-dev-hub <DevHub alias>
   sf package create --name FlipSwitch --package-type Unlocked --no-namespace --path force-app
   ```

2. **Update `sfdx-project.json`** with the generated package ID in `packageAliases`

3. **Create first version**:
   ```bash
   sf package version create -p FlipSwitch -d force-app -x --wait 20 --code-coverage
   ```

4. **Promote to released** (after CI passes):
   ```bash
   sf package version promote --package "FlipSwitch@1.0.0-1"
   ```

5. **GitHub Actions automation** (`build.yml`):
   - Feature branches: `sf package version create` → beta version
   - `main` branch: `sf package version create` → `sf package version promote`
   - DevHub authentication via `SF_AUTH_URL` GitHub secret

6. **README.md** install section:
   ```
   Sandbox install:    /packaging/installPackage.apexp?p0=<PACKAGE_VERSION_ID>
   Production install: /packaging/installPackage.apexp?p0=<PACKAGE_VERSION_ID>
   sf CLI:             sf package install --wait 20 --security-type AdminsOnly --package <PACKAGE_VERSION_ID>
   ```

7. **GitHub Release**: tag `v1.0.0`, include package version ID, write changelog

### `packageAliases` versioning strategy (NebulaLogger model)
Every released version gets a named alias in `sfdx-project.json`:
```json
"packageAliases": {
  "FlipSwitch": "0Ho...",
  "FlipSwitch@1.0.0-1": "04t...",
  "FlipSwitch@1.0.1-1": "04t..."
}
```
Consumers can pin to a specific version or install the latest.

### Post-install documentation
- Platform Cache partition setup (varies by org edition — manual step, not in package)
- Assign `Feature_Flag_Admin` or `Feature_Flag_User` permission set
- Schedule expiration job: `System.schedule('FlipSwitch Expiration', '0 0 0 * * ?', new FeatureFlagExpirationJob())`

### Verification
- `sf package version list` shows version with `Released` status
- Install to a fresh scratch org: `sf package install --package <ID>` succeeds
- Permission sets assignable; all 15 classes visible in installed org
- `sf apex run test` on installed org: 90%+ coverage, 0 failures

---

## Complete File Manifest

### Apex — Production (`force-app/main/default/classes/`)

| Class | Purpose |
|-------|---------|
| `FeatureFlag.cls` | Entry point — static API + factory + transaction controls |
| `FeatureFlagBuilder.cls` | Fluent single-flag builder |
| `FeatureFlagBatchBuilder.cls` | Multi-flag batch builder (single SOQL) |
| `FeatureFlagEvaluator.cls` | Core evaluation engine |
| `FeatureFlagContext.cls` | Internal evaluation context (user, profile, perms, attributes) |
| `FeatureFlagCache.cls` | Platform Cache integration with graceful fallback |
| `FeatureFlagLogger.cls` | Buffered async Platform Event logging |
| `FeatureFlagResult.cls` | Result wrapper (isEnabled, variant, reason, payload) |
| `FeatureFlagHash.cls` | Deterministic SHA-256 hashing for percentage rollouts |
| `FeatureFlagHandler.cls` | Callback interface for `.whenEnabled()` / `.whenDisabled()` |
| `FeatureFlagPlugin.cls` | Extensibility interface — post-evaluation hook |
| `FeatureFlagException.cls` | Custom exception type |
| `FeatureFlagFlowAction.cls` | `@InvocableMethod` for Flows (bulkified) |
| `FeatureFlagExpirationJob.cls` | Scheduled Apex — daily rule deactivation |
| `CallableFeatureFlag.cls` | `System.Callable` adapter for loose coupling |
| `FeatureFlagEvaluationTriggerHandler.cls` | Platform Event trigger handler → metrics |

### Apex — Tests (`force-app/main/default/classes/tests/`)

`FeatureFlagTest`, `FeatureFlagBuilderTest`, `FeatureFlagBatchBuilderTest`,
`FeatureFlagEvaluatorTest`, `FeatureFlagCacheTest`, `FeatureFlagHashTest`,
`FeatureFlagFlowActionTest`, `FeatureFlagExpirationJobTest`,
`FeatureFlagEvaluationTriggerHandlerTest`

### LWC (`force-app/main/default/lwc/`)
`featureFlagGate`, `featureFlagVariant`, `featureFlagService`, `featureFlagAdmin`

### Triggers (`force-app/main/default/triggers/`)
`FeatureFlagEvaluationTrigger.trigger` (on `Feature_Flag_Evaluation__e`)

---

## Implementation Sequence & Dependencies

```
Phase 0 (Scaffold)
    └─► Phase 1 (Data Model)
            └─► Phase 2 (Apex + Tests)  ◄─── Critical path: most complex
                    ├─► Phase 3 (Flows)         ─┐
                    ├─► Phase 4 (LWC)            ├─ can run in parallel
                    └─► Phase 5 (Safety)        ─┘
                            └─► Phase 6 (Package & Distribution)
```

Phases 3, 4, and 5 are independent of each other and can be developed in parallel after Phase 2 is complete.

---

## Testing Verification Summary

| Layer | Tool | Threshold |
|-------|------|-----------|
| Apex unit tests | `sf apex run test --code-coverage` | 90%+ per class |
| LWC unit tests | `npm test` (Jest) | All green |
| Static analysis | SFDX Scanner / PMD | Zero P1/P2 violations |
| Integration | Deploy to scratch org | Zero deployment errors |
| Package version | `sf package version create --code-coverage` | Fails build if < 75% |

**End-to-end smoke test** (run after each phase):
```bash
sf org create scratch -f config/project-scratch-def.json -a flipswitch-dev
sf project deploy start --target-org flipswitch-dev
sf apex run test --target-org flipswitch-dev --code-coverage --result-format human
# Assert: 0 failures, 90%+ overall coverage
sf org delete scratch --target-org flipswitch-dev --no-prompt
```
