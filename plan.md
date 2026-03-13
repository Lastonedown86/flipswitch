# Plan: Salesforce Progressive Delivery Feature Flag Framework

## TL;DR
Build an unlocked-package-based Progressive Delivery framework for Salesforce that brings feature flags, percentage rollouts, user targeting, multi-variant experiments, and kill switches to Apex, LWC, and Flows. Uses a hybrid storage model: Custom Metadata Types for CI/CD-deployable flag definitions + Custom Objects for runtime targeting rules and overrides. Includes an admin LWC UI, evaluation logging via Platform Events, and a clean static API (`FeatureFlag.isEnabled('MY_FLAG')`).

---

## Phase 1: Data Model & Storage

### Recommended Storage: Hybrid Custom Metadata + Custom Objects
- **Custom Metadata Types** for flag *definitions* — deployable, no data storage limits, available in formulas, CI/CD friendly
- **Custom Objects** for runtime *targeting rules* and *overrides* — editable by admins without deployments
- **Platform Events** for evaluation logging — async, non-blocking, decoupled

### Objects to Create

1. **`FlipSwitch_Flag__mdt`** (Custom Metadata Type) — Flag definitions
   - `DeveloperName` (inherited) — unique flag key (e.g. `DARK_MODE`, `NEW_CHECKOUT_FLOW`)
   - `Label` (inherited) — human-readable name
   - `Description__c` (LongTextArea) — purpose and owner
   - `Type__c` (Picklist) — `Boolean` | `Variant` | `Percentage`
   - `Default_Value__c` (Text) — default when no targeting rules match (e.g. `false`, `control`)
   - `Is_Active__c` (Checkbox) — master kill switch
   - `Expiration_Date__c` (Date) — auto-expiration date (null = never)
   - `Category__c` (Text) — grouping for admin UI (e.g. `Checkout`, `UI`, `Backend`)

2. **`FlipSwitch_Rule__c`** (Custom Object) — Runtime targeting rules
   - `Flag_Key__c` (Text, indexed) — references `DeveloperName` of the CMDT
   - `Rule_Type__c` (Picklist) — `User` | `Profile` | `Permission_Set` | `Percentage` | `Custom_Field` | `Segment`
   - `Rule_Value__c` (LongTextArea) — JSON or semicolon-delimited values (user IDs, profile names, %, etc.)
   - `Variant_Value__c` (Text) — value to return when rule matches (for multi-variant)
   - `Priority__c` (Number) — evaluation order (lower = higher priority)
   - `Is_Active__c` (Checkbox) — enable/disable individual rules
   - `Start_Date__c` (DateTime) — scheduled activation
   - `End_Date__c` (DateTime) — scheduled deactivation

3. **`FlipSwitch_Variant__c`** (Custom Object) — Variant definitions for multi-variant flags
   - `Flag_Key__c` (Text, indexed)
   - `Variant_Key__c` (Text) — e.g. `control`, `treatment_a`, `treatment_b`
   - `Weight__c` (Number) — percentage weight for random assignment (all weights for a flag should sum to 100)
   - `Payload__c` (LongTextArea) — optional JSON payload for variant-specific config

4. **`FlipSwitch_Evaluation__e`** (Platform Event) — Evaluation audit trail
   - `Flag_Key__c` (Text)
   - `User_Id__c` (Text)
   - `Result__c` (Text) — evaluated value
   - `Context__c` (LongTextArea) — serialized evaluation context
   - `Timestamp__c` (DateTime)
   - `Evaluation_Reason__c` (Text) — why this result (e.g. `RULE_MATCH`, `DEFAULT`, `KILL_SWITCH`, `EXPIRED`)

5. **`FlipSwitch_Assignment__c`** (Custom Object) — Sticky assignments for percentage/variant rollouts
   - `Flag_Key__c` (Text, indexed)
   - `User_Id__c` (Text, indexed)
   - `Assigned_Variant__c` (Text) — sticky variant for this user
   - Unique constraint on `Flag_Key__c` + `User_Id__c`

---

## Phase 2: Apex Service Layer — Dual API (Static + Fluent)

### Quick Static API — `FeatureFlag.cls`
Simple one-liners for common checks. All static methods delegate to the fluent builder internally.

```
FeatureFlag.isEnabled('NEW_CHECKOUT')                    // → Boolean (running user)
FeatureFlag.getVariant('HOMEPAGE_EXPERIMENT')             // → String
```

### Fluent Builder API — `FeatureFlag.flag()` / `FeatureFlag.flags()`
Developer-friendly chaining for contextual evaluations, targeting, and batch loading.

```
// Simple with fallback
FeatureFlag.flag('NEW_CHECKOUT').fallback(false).isEnabled()

// User-targeted with context attributes
FeatureFlag.flag('HOMEPAGE_EXPERIMENT')
    .forUser(someUserId)
    .withAttribute('region', 'US')
    .withAttribute('tier', 'Enterprise')
    .fallback('control')
    .getVariant()

// Full result with reason, silent (no logging)
FeatureFlagResult result = FeatureFlag.flag('PRICING_V2')
    .forUser(someUserId)
    .withAttribute('account_type', 'Partner')
    .silent()
    .evaluate()

// Multi-flag batch evaluation (single SOQL trip)
Map<String, FeatureFlagResult> results = FeatureFlag.flags('FLAG_A', 'FLAG_B', 'FLAG_C')
    .forUser(someUserId)
    .evaluateAll()

// Conditional execution (callback pattern)
FeatureFlag.flag('NEW_CHECKOUT')
    .whenEnabled(new NewCheckoutHandler())
    .whenDisabled(new LegacyCheckoutHandler())
    .execute()
```

### Public Classes

1. **`FeatureFlag.cls`** — Entry point with static convenience methods + `flag()` / `flags()` factory methods
   - `static Boolean isEnabled(String flagKey)` — quick check for running user
   - `static String getVariant(String flagKey)` — quick variant for running user
   - `static FeatureFlagBuilder flag(String flagKey)` — returns fluent builder
   - `static FeatureFlagBatchBuilder flags(String... flagKeys)` — returns batch builder

2. **`FeatureFlagBuilder.cls`** — Fluent single-flag builder (returned by `FeatureFlag.flag()`)
   - `.forUser(Id userId)` — evaluate for specific user (defaults to running user)
   - `.withAttribute(String key, Object value)` — add context attribute for segment matching
   - `.withAttributes(Map<String,Object> attrs)` — bulk add context attributes
   - `.fallback(Boolean|String value)` — override CMDT default value
   - `.silent()` — suppress evaluation logging for this call
   - `.whenEnabled(FeatureFlagHandler handler)` — register callback for enabled
   - `.whenDisabled(FeatureFlagHandler handler)` — register callback for disabled
   - `.isEnabled()` — **terminal** → Boolean
   - `.getVariant()` — **terminal** → String
   - `.getPayload()` — **terminal** → Map<String,Object>
   - `.evaluate()` — **terminal** → FeatureFlagResult
   - `.execute()` — **terminal** → runs whenEnabled/whenDisabled handler

3. **`FeatureFlagBatchBuilder.cls`** — Fluent multi-flag builder (returned by `FeatureFlag.flags()`)
   - `.forUser(Id userId)` — shared user for all flags
   - `.withAttribute(String key, Object value)` — shared context
   - `.evaluateAll()` — **terminal** → Map<String, FeatureFlagResult>
   - Loads all rules for requested flags in a single SOQL query

4. **`FeatureFlagHandler`** (Interface) — Callback for `.whenEnabled()` / `.whenDisabled()` / `.execute()`
   - `void handle()` — implementation contains feature-specific logic

5. **`FeatureFlagResult.cls`** — Result wrapper
   - `Boolean isEnabled`
   - `String variant`
   - `String reason` (RULE_MATCH, DEFAULT, KILL_SWITCH, EXPIRED, CACHE_HIT)
   - `Map<String,Object> payload`

### Internal Engine Classes

6. **`FeatureFlagEvaluator.cls`** — Core evaluation engine (called by both builders)
   - Loads flag definition from CMDT
   - Checks kill switch (`Is_Active__c = false` → return default)
   - Checks expiration (`Expiration_Date__c < TODAY` → return default, mark inactive)
   - Evaluates targeting rules in priority order:
     1. Exact user match
     2. Profile match
     3. Permission Set match
     4. Segment match
     5. Custom field match
     6. Percentage rollout (deterministic hash of userId + flagKey for consistency)
   - Falls through to `Default_Value__c` if no rules match
   - Returns `FeatureFlagResult` with value + reason

7. **`FeatureFlagContext.cls`** — Internal evaluation context (built by `FeatureFlagBuilder`)
   - User ID, profile, permission sets, custom attributes
   - Built automatically from builder chain — developers never instantiate directly

8. **`FeatureFlagCache.cls`** — Platform Cache integration
   - Org-level cache for CMDT flag definitions (rarely change)
   - Session-level cache for user evaluations (per-request dedup)
   - Cache invalidation on rule changes (via trigger on `FlipSwitch_Rule__c`)
   - Graceful fallback if cache partition unavailable

9. **`FeatureFlagLogger.cls`** — Async logging
   - Publishes `FlipSwitch_Evaluation__e` platform events
   - Sampling rate config (don't log 100% in high-volume orgs)
   - Respects `.silent()` flag from builder
   - Trigger subscriber writes to `FlipSwitch_Evaluation_Log__c` (optional Big Object for retention)

10. **`FeatureFlagHash.cls`** — Deterministic hashing util
    - Consistent hashing for percentage rollouts: `hash(userId + flagKey) % 100`
    - Ensures same user always gets same flag value (sticky without storage)
    - Uses `Crypto.generateDigest('SHA-256', ...)` for uniform distribution

11. **`FeatureFlagException.cls`** — Custom exception type

### NebulaLogger-Inspired Enhancements

12. **Transaction Controls** (mirrors Logger's `suspendSaving()`/`resumeSaving()`)
    - `FeatureFlag.suspendLogging()` — stop buffering evaluations (perf-sensitive code paths)
    - `FeatureFlag.resumeLogging()` — re-enable evaluation buffering
    - `FeatureFlag.flushEvaluations()` — publish all buffered Platform Events in one DML call
    - Evaluations buffer in-memory during transaction, flush at end (reduces PE publish calls from N to 1)

13. **Save Method Enum** (mirrors Logger's `SaveMethod`)
    - `FeatureFlag.SaveMethod.EVENT_BUS` — default, publish Platform Events
    - `FeatureFlag.SaveMethod.QUEUEABLE` — defer logging to async job
    - `FeatureFlag.SaveMethod.SYNCHRONOUS` — direct DML (testing/debug only)
    - Configurable per-user via `FlipSwitch_Settings__c.Default_Save_Method__c`

14. **Scenario Tagging** (mirrors Logger's `setScenario()`)
    - `FeatureFlag.setScenario('Checkout Flow')` — tags all subsequent evaluations in the transaction
    - Enables per-business-flow analytics in New Relic dashboards
    - Fluent: `FeatureFlag.flag('X').inScenario('Checkout').isEnabled()`

15. **`CallableFeatureFlag.cls`** — implements `System.Callable` for dynamic invocation
    - ISVs/packages can use flags without hard dependency
    - Actions: `isEnabled`, `getVariant`, `evaluate`, `setScenario`
    - Same pattern as NebulaLogger's `CallableLogger`

16. **`FeatureFlagPlugin`** (Interface) + `FlipSwitch_Plugin__mdt` — extensibility framework
    - `void onEvaluate(FeatureFlagResult result, FeatureFlagContext context)` — hook after each evaluation
    - Configured via CMDT — orgs add custom logic (Slack alerts on kill switch, external analytics sync)
    - Plugin framework available in unlocked package only (managed package platform limitation)

17. **`FlipSwitch_Settings__c`** (Hierarchy Custom Setting) — per-user/profile framework config
    - `Is_Logging_Enabled__c` — disable evaluation logging per user
    - `Override_All_Flags__c` (Picklist: None/Enable/Disable) — force all flags for QA/testing
    - `Default_Save_Method__c` — per-user save strategy override

### Test Classes
- `FeatureFlagTest.cls` — Unit tests covering both static and fluent API paths
- `FeatureFlagBuilderTest.cls` — Fluent builder chaining, context attributes, fallbacks, callbacks
- `FeatureFlagBatchBuilderTest.cls` — Multi-flag batch evaluation, single SOQL verification
- `FeatureFlagEvaluatorTest.cls` — Edge cases: expired flags, kill switches, rule priority
- `FeatureFlagCacheTest.cls` — Cache hit/miss/invalidation
- `FeatureFlagHashTest.cls` — Distribution uniformity tests

---

## Phase 3: Flow Support

1. **`FeatureFlagFlowAction.cls`** — Invocable Method
   - `@InvocableMethod(label='Evaluate Feature Flag')`
   - Input: `flagKey` (String), optional `userId` (String)
   - Output: `isEnabled` (Boolean), `variant` (String)
   - Bulkified for collection handling in Flows

2. **Flow-Friendly Design**
   - Admins can use the invocable action in Decision elements
   - Works in Record-Triggered Flows, Screen Flows, Autolaunched Flows
   - Example: Decision → "Is NEW_CHECKOUT enabled?" → Yes path / No path

---

## Phase 4: LWC Components

### 1. `featureFlagGate` — Conditional rendering component
```html
<c-feature-flag-gate flag-key="DARK_MODE">
    <div slot="enabled">New dark mode UI</div>
    <div slot="disabled">Classic UI</div>
</c-feature-flag-gate>
```
- Wire adapter calls Apex `@AuraEnabled(cacheable=true)` method
- Client-side caching with configurable TTL
- Slot-based rendering for clean template usage

### 2. `featureFlagVariant` — Multi-variant rendering
```html
<c-feature-flag-variant flag-key="HOMEPAGE_EXPERIMENT">
    <div slot="control">Control version</div>
    <div slot="treatment_a">Treatment A</div>
    <div slot="treatment_b">Treatment B</div>
</c-feature-flag-variant>
```

### 3. `featureFlagService` (LWC service/module) — Imperative API
- `import { isEnabled, getVariant } from 'c/featureFlagService'`
- Batch multiple flag evaluations into single Apex call
- Client-side evaluation cache (session storage or in-memory)

### 4. `featureFlagAdmin` — Admin management LWC app (shell)
Decomposed into 5 focused child components. Hosted on a Lightning App Page / Tab (desktop only).

#### Shell (`featureFlagAdmin`)
- `lightning-tabset` with 4 tabs: Dashboard / Flag Detail / Eval Logs / Analytics
- **Sticky kill-switch alert banner** — red banner when any flag is kill-switched; click navigates to affected flags
- **Org health summary strip** — 4 KPI tiles: Active Flags / Expiring This Week / Kill-Switched / Circuit Breaker Trips
- Cross-tab state: `selectedFlagKey` propagated to Detail / Logs / Analytics tabs
- `errorCallback` surfaces child errors as toast messages

#### Dashboard (`featureFlagDashboard`)
- Searchable flag list (name, key, description)
- **Status badges**: Active (green) / Disabled (gray) / Expiring Soon (yellow) / Expired (red) / Kill Switch (dark red)
- **Type icons**: Boolean toggle / Percentage pie / Variant beaker
- **Rollout progress bar** for Percentage flags
- **Variant chip list** for Variant flags
- **Expiration countdown** (days remaining, color-coded urgency)
- Category filter pills + status filter pills
- Column sorting (name, status, expiration)
- Row-level kill-switch toggle button (no navigation required)
- Row double-click or preview icon navigates to Flag Detail tab
- **Bulk actions**: Enable Selected / Disable Selected with checkbox selection
- Public `filterByStatus(status)` method called by shell banner
- `isExposed: false` — internal child component

#### Flag Detail (`featureFlagDetail`)
- Flag metadata panel: key, type, default value, category, expiration countdown
- **Flag key copy-to-clipboard** button
- **Kill-switch toggle** button (contextual label + variant)
- **Usage snippet generator** panel — Apex and LWC tabs, code populated from flag metadata
- Delegates rule + variant management to `featureFlagRuleBuilder`
- **Simulation / preview panel**: input User ID + JSON attributes → calls `previewEvaluation()` Apex → shows isEnabled, variant, reason, payload with color-coded reason badge

#### Rule Builder (`featureFlagRuleBuilder`)
- **Drag-to-reorder** rules using HTML5 Drag and Drop API (native, no library)
  - `dragstart` / `dragenter` / `dragleave` / `dragover` / `drop` / `dragend` handlers
  - Array splice on drop, sequential priority re-assignment
  - "Save Rule Order" / "Discard" strip appears only after a drag
  - Calls `reorderRules()` bulk DML on save
- **Rule rows**: drag handle, priority badge, rule type badge, scheduled badge, variant chip, value preview, active toggle, edit/delete actions
- **Rule modal**: context-aware inputs by type (User ID text / Profile text / Percentage slider / Segment tags / Custom Field expression); scheduled date pickers; variant assignment picker for Variant flags; active toggle
- **Inline active toggle** saves immediately via `saveRule()`
- **Variant weight visualizer** (Variant flags only):
  - Segmented color bar showing weight distribution
  - Total weight counter with red/green coloring, over/under warning
  - Inline variant rows with key + weight inputs + save/delete per row
  - Validates total = 100%
- `isExposed: false` — internal child component

#### Eval Logs (`featureFlagEvalLogs`)
- **Real-time EMP API subscription** to `/event/FlipSwitch_Evaluation__e` (replay -1, new events only)
- **Live streaming indicator** with animated pulse dot
- Events prepended (newest first), capped at 500 in-memory entries
- Filter bar: flag key search, reason combobox, date-from / date-to
- **Reason badges** color-coded: RULE_MATCH (blue) / DEFAULT (gray) / KILL_SWITCH (dark red) / EXPIRED (orange) / CACHE_HIT (purple) / CIRCUIT_BREAKER (red)
- **Export to CSV** button (client-side Blob download of filtered rows)
- Sampling rate notice (informational)
- `isExposed: false` — internal child component

#### Analytics (`featureFlagAnalytics`)
- Date range picker (default last 30 days) controls all charts simultaneously
- Wired to `getMetrics()` Apex — data source: `FlipSwitch_Metric__c`
- **4 KPI tiles**: Total Evaluations / Unique Users / Circuit Breaker Trips / Variant Count
- **Variant distribution donut** — pure inline SVG (no external library); `stroke-dasharray` segments; center total label; color legend with count + %
- **Unique users per variant** — horizontal bar chart (CSS `width` transitions)
- **Daily evaluation volume sparkline** — CSS flex bar chart with date axis labels
- All charts use 10-color SEGMENT_COLORS palette
- `isExposed: false` — internal child component

#### Apex Controller (`FeatureFlagAdminController`)
Key `@AuraEnabled` methods (all `with sharing`):
| Method | Cacheable | Purpose |
|---|---|---|
| `getFlags(category, status)` | ✓ | Dashboard list with enriched status |
| `getOrgHealth()` | ✓ | Shell KPI strip counts |
| `getFlagDetail(flagKey)` | ✓ | Full flag + rules + variants |
| `saveRule(rule)` | — | Upsert targeting rule |
| `deleteRule(ruleId)` | — | Delete targeting rule |
| `reorderRules(rules)` | — | Bulk priority update after drag |
| `toggleKillSwitch(flagKey, active)` | — | Create / delete kill-switch rule |
| `bulkUpdateFlags(flagKeys, action)` | — | Bulk enable/disable |
| `saveVariant(variant)` | — | Upsert variant definition |
| `deleteVariant(variantId)` | — | Delete variant |
| `previewEvaluation(flagKey, userId, attrsJson)` | — | Simulation preview (silent, no cache) |
| `getMetrics(flagKey, startDate, endDate)` | ✓ | Aggregated analytics from FlipSwitch_Metric__c |
| `getCategories()` | ✓ | Deduplicated category list for filter pills |

---

## Phase 5: Safety & Observability

### Kill Switches
- `Is_Active__c = false` on CMDT immediately disables (requires deployment or Metadata API)
- **Runtime kill switch**: Special rule with `Rule_Type__c = 'Kill_Switch'` on `FlipSwitch_Rule__c` (no deployment needed)
- Admin UI one-click kill switch creates this rule instantly

### Auto-Expiration
- Scheduled Apex job (`FeatureFlagExpirationJob.cls`) runs daily
- Deactivates flags past `Expiration_Date__c`
- Sends notification (Custom Notification or email) to flag owner

### Circuit Breaker
- If evaluation throws exception, return default value (never break the caller)
- Log errors but don't propagate — feature flags must be safe to use everywhere
- Configurable via `FlipSwitch_Config__mdt` custom metadata for framework settings

### Evaluation Analytics
- Platform Event subscriber aggregates into `FlipSwitch_Metric__c`
- Tracks: evaluation count per flag, variant distribution, unique users per variant
- Powers reports/dashboards for experiment analysis

---

## Phase 6: Package & Distribution Strategy

### v1: Unlocked Package Only (Open-Source on Personal GitHub)

Following the NebulaLogger distribution model — open-source on GitHub, no AppExchange. Users install via package install link or `sf package install` CLI command.

| Aspect | Detail |
|--------|--------|
| **Package type** | Unlocked (no namespace) |
| **Distribution** | GitHub repo + install links (sandbox + production) |
| **License** | MIT (same as NebulaLogger) |
| **Ownership** | Personal GitHub — you own the IP |
| **API access** | `public` — all classes accessible, forkable |
| **Plugin framework** | Full support |
| **Test coverage** | 90%+ target |

### Why No AppExchange
- Security Review is expensive and slow (weeks/months per major version)
- Free tools get buried — AppExchange is optimized for paid products
- Target audience is developers — they find tools on GitHub, not browsing AppExchange
- NebulaLogger (900+ stars, widespread adoption) has never been on AppExchange
- Maintenance overhead (screenshots, descriptions, compatibility re-certification)

### Why No Managed Package (v1)
- Adds complexity without clear demand
- Managed packages restrict plugin framework (platform limitation)
- Namespace lock-in is permanent and irreversible
- If ISVs or orgs later need namespace protection / `global` API stability, add managed package as v2

### Future: Managed Package (v2, Only If Demand)
- Add only when ISVs specifically request namespace protection or `global` API guarantees
- Same codebase with `global` access modifiers on public API classes
- `@namespaceAccessible` on internal classes needing cross-namespace access
- Separate SFDX package directory alongside unlocked

### SFDX Project Structure (Unlocked Only — v1)
```
sfdx-project.json
force-app/
└── main/default/
    ├── classes/
    │   ├── FeatureFlag.cls
    │   ├── FeatureFlagBuilder.cls
    │   ├── FeatureFlagBatchBuilder.cls
    │   ├── FeatureFlagEvaluator.cls
    │   ├── FeatureFlagContext.cls
    │   ├── FeatureFlagCache.cls
    │   ├── FeatureFlagLogger.cls
    │   ├── FeatureFlagResult.cls
    │   ├── FeatureFlagHash.cls
    │   ├── FeatureFlagHandler.cls          (interface)
    │   ├── FeatureFlagPlugin.cls           (interface)
    │   ├── FeatureFlagException.cls
    │   ├── FeatureFlagFlowAction.cls
    │   ├── FeatureFlagExpirationJob.cls
    │   ├── CallableFeatureFlag.cls          (System.Callable impl)
    │   └── tests/
    │       ├── FeatureFlagTest.cls
    │       ├── FeatureFlagBuilderTest.cls
    │       ├── FeatureFlagBatchBuilderTest.cls
    │       ├── FeatureFlagEvaluatorTest.cls
    │       ├── FeatureFlagCacheTest.cls
    │       └── FeatureFlagHashTest.cls
    ├── customMetadata/
    │   ├── FlipSwitch_Flag__mdt/
    │   ├── FlipSwitch_Config__mdt/
    │   └── FlipSwitch_Plugin__mdt/
    ├── customSettings/
    │   └── FlipSwitch_Settings__c/         (hierarchy)
    ├── objects/
    │   ├── FlipSwitch_Rule__c/
    │   ├── FlipSwitch_Variant__c/
    │   ├── FlipSwitch_Assignment__c/
    │   └── FlipSwitch_Metric__c/
    ├── platformEventChannelMembers/
    │   └── FlipSwitch_Evaluation__e/
    ├── lwc/
    │   ├── featureFlagGate/
    │   ├── featureFlagVariant/
    │   ├── featureFlagService/
    │   └── featureFlagAdmin/
    ├── permissionsets/
    │   ├── FlipSwitch_Admin.permissionset-meta.xml
    │   └── FlipSwitch_User.permissionset-meta.xml
    ├── tabs/
    └── flexipages/
```

### Adoption Playbook (NebulaLogger Model)
1. Build v1 on personal GitHub, personal DevHub, personal time
2. Open-source under MIT license
3. Strong GitHub README with clear install links (sandbox + production URLs)
4. `sf package install --wait 20 --security-type AdminsOnly --package <ID>` one-liner
5. Pitch adoption at work: "Same model as NebulaLogger — community open-source, zero cost"
6. Promote via blog posts, Trailblazer Community, conference talks

### Dependencies
- Zero external dependencies
- Optional integration: NebulaLogger (if present, evaluation logs route through Logger)
- `CallableFeatureFlag` enables loose coupling from consumer packages

## Phase 7: Observability & Integration

### New Relic Integration (mirrors NebulaLogger pattern)
- `FlipSwitch_Evaluation__e` Platform Events → subscriber trigger → New Relic via same pub/sub path
- Dashboard templates: flag evaluation counts, variant distribution, kill switch activations
- PagerDuty alerts: kill switch triggers, evaluation error rate spikes
- Scenario tagging (`FeatureFlag.setScenario('Checkout Flow')`) enables per-flow dashboards

### NebulaLogger Integration (Optional)
- When NebulaLogger is detected (`Type.forName('Logger') != null`):
  - Flag evaluations logged via `Logger.fine()` instead of raw Platform Events
  - Evaluation context attached as structured log data
  - Kill switch activations logged as `Logger.warn()`
- When not present: fallback to native Platform Event logging

## Business Case Summary

### Problem
Every Salesforce deployment is all-or-nothing. No gradual rollout, no instant rollback, no production testing. This is an industry-standard gap that Salesforce does not natively address.

### Solution
Native feature flag framework — same architecture patterns as NebulaLogger (Platform Events, CMDT config, fluent API) — bringing progressive delivery to Salesforce. Open-source, MIT-licensed, distributed via GitHub (same model as NebulaLogger).

### Key Metrics
- Blast radius: 100% → 5% canary
- Rollback time: 30-90 min (redeploy) → <1 min (kill switch)
- Emergency deploys: monthly → near-zero
- Release velocity: deploy anytime, release when ready

### Strategic Value
- Companion to NebulaLogger: observability (what broke) + progressive delivery (prevent breaking)
- Integrates with existing New Relic/PagerDuty stack
- Same adoption model as NebulaLogger: personal open-source project, company installs as consumer
- Managed package / AppExchange can be added later if ISV demand materializes

---

## Verification

1. **Unit Tests** — 90%+ Apex code coverage with tests covering:
   - Boolean flag evaluation (enabled/disabled)
   - Multi-variant evaluation with correct weight distribution
   - Targeting rule priority and matching (user, profile, permission set, percentage)
   - Kill switch and expiration behavior
   - Cache hit/miss/invalidation
   - Deterministic hashing consistency
   - Flow invocable action (single + bulk)
   - Circuit breaker (evaluation errors return default)

2. **Integration Tests** — Deploy to scratch org:
   - Create flag via CMDT, add rules via Custom Object, evaluate via Apex
   - LWC gate component renders correct slot
   - Admin UI CRUD operations on rules
   - Flow decision element with feature flag action
   - Kill switch disables flag immediately

3. **Manual Verification**:
   - Admin UI: create flag, add targeting rules, verify evaluation
   - LWC gate: embed in Lightning page, toggle flag, verify re-render
   - Flow: build test Flow with feature flag decision, verify paths
   - Percentage rollout: verify same user gets consistent result across evaluations

---

## Decisions

- **Storage: Hybrid CMDT + Custom Objects** — CMDTs for flag definitions (deployable, CI/CD friendly, no storage limits) + Custom Objects for runtime rules (admin-editable without deployment). This is the recommended pattern because pure CMDT would require deployments for any rule change, and pure Custom Objects would lose CI/CD deployability.
- **Percentage rollout: Deterministic hash** — `SHA-256(userId + flagKey) % 100` gives consistent assignment without storing per-user records. `FlipSwitch_Assignment__c` exists as optional sticky assignment table for cases where hash-based assignment isn't sufficient (e.g., when percentage changes and you want to preserve existing assignments).
- **Logging: Platform Events** — Async, non-blocking, decoupled. Won't impact DML limits or transaction performance. Subscriber writes to reportable object.
- **Scope included**: Apex API (static + fluent), LWC components (gate + variant + admin), Flow invocable action, evaluation logging, kill switches, auto-expiration, percentage rollouts, multi-variant support, plugin framework, Callable interface, New Relic/NebulaLogger integration.
- **Scope excluded**: Aura components (legacy, not prioritized), Visualforce support, external integrations (LaunchDarkly sync), mobile SDK, real-time streaming of flag changes, AppExchange listing, managed package (deferred to v2 if demand).
- **Distribution**: Personal GitHub, MIT license, unlocked package only (v1). Same model as NebulaLogger.
- **Starting from scratch** — no existing patterns to migrate from.
- **Object naming**: All Salesforce metadata (CMDT, Custom Objects, Platform Events, Custom Settings, permission sets) uses the `FlipSwitch_` prefix to avoid naming conflicts with orgs that already have `Feature_Flag_*` objects. Apex classes retain the `FeatureFlag` prefix (no conflict risk since classes are scoped to the package).

---

## Further Considerations

1. **Platform Cache Partition** — The framework needs a Platform Cache partition for performance. Should we include partition creation in the package, or document it as a post-install step? *Recommendation: Post-install step, since cache allocation varies by org edition.*

2. **Governor Limit Safety** — High-volume orgs may evaluate many flags per transaction. Should we batch-evaluate all flags upfront (one SOQL for rules) and cache in-memory for the transaction, or evaluate lazily per-flag? *Recommendation: Lazy evaluation with in-transaction memoization — most transactions only check 1-3 flags.*

3. **Flag Cleanup Workflow** — Expired/stale flags accumulate technical debt. Should we add a "flag hygiene" scheduled report that notifies owners of flags past expiration? *Recommendation: Yes, include in Phase 5 as part of the expiration job.*
