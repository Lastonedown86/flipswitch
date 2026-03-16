# FlipSwitch — AppExchange Publishing Plan

## Overview

This document covers the strategy, architecture, and execution plan for publishing FlipSwitch to the Salesforce AppExchange as a managed package with **Free** (Community) and **Pro** (Paid) tiers. This plan supplements `plan.md` (core technical specification) and is considered Phase 6+ work following the initial unlocked package v1.

---

## Strategic Rationale

The unlocked package on GitHub (v1) builds community adoption. The managed package on AppExchange (v2) monetizes that adoption and serves ISV/enterprise buyers who need:

- **Namespace protection** — no conflicts with customer org metadata
- **`global` API stability** — safe to extend from managed packages
- **Support SLA** — required by enterprise procurement
- **AppExchange security trust signal** — required by some security review policies
- **License management** — metered usage, per-org billing, automated enforcement

The two models complement each other: the GitHub unlocked package is the community/developer funnel; AppExchange is the enterprise/ISV monetization layer.

---

## Package Architecture

### Option A: Single Managed Package (Recommended)

One managed package with license-gated features. Free tier capabilities are always available; Pro capabilities check a custom permission at runtime.

```
Namespace: flipswitch
Package:   FlipSwitch — Feature Flag Framework
Listing:   AppExchange (free to install, license upgrades in-app)

  ┌─────────────────────────────────────────────────────┐
  │  FlipSwitch Managed Package (flipswitch namespace)  │
  │                                                     │
  │  Free Tier (all orgs)                               │
  │  ─────────────────────────────────────────────────  │
  │  • Boolean flags, kill switches, expiration         │
  │  • User + Profile targeting rules                   │
  │  • LWC gate + variant components                    │
  │  • Flow invocable action                            │
  │  • Basic evaluation logging                         │
  │  • Up to 25 active flags                            │
  │  • Community support                                │
  │                                                     │
  │  Pro Tier (license key required)                    │
  │  ─────────────────────────────────────────────────  │
  │  • Unlimited flags                                  │
  │  • Permission set, segment, custom field targeting  │
  │  • Percentage rollouts (deterministic hashing)      │
  │  • Multi-variant experiments with weights           │
  │  • Admin dashboard LWC app                         │
  │  • Analytics + FlipSwitch_Metric__c                 │
  │  • Batch evaluation API                             │
  │  • Plugin framework + Callable interface            │
  │  • Auto-expiration job + notifications              │
  │  • NebulaLogger + New Relic integration             │
  │  • Priority email support + SLA                     │
  └─────────────────────────────────────────────────────┘
```

**Rationale for single package:** Simpler install experience, single Security Review, one post-install script, shared namespace. License enforcement happens in Apex at evaluation time using Salesforce's License Management App (LMA).

### Option B: Two Packages (Alternative)

Separate `FlipSwitch` (free, core) and `FlipSwitch Pro` (paid, extension) managed packages. More complex dependency management, two Security Reviews, but cleaner separation. Defer this model unless Option A creates technical complications.

---

## Free vs Pro Feature Matrix

| Feature | Free | Pro |
|---------|------|-----|
| Boolean flags | ✓ | ✓ |
| Kill switch (CMDT + runtime rule) | ✓ | ✓ |
| Flag expiration dates | ✓ | ✓ |
| User targeting rules | ✓ | ✓ |
| Profile targeting rules | ✓ | ✓ |
| LWC `featureFlagGate` component | ✓ | ✓ |
| LWC `featureFlagVariant` component | ✓ | ✓ |
| Flow invocable action | ✓ | ✓ |
| Basic `FlipSwitch_Evaluation__e` logging | ✓ | ✓ |
| Static API (`FeatureFlag.isEnabled`) | ✓ | ✓ |
| Fluent builder API | ✓ | ✓ |
| Circuit breaker (errors → default) | ✓ | ✓ |
| Active flag limit | 25 | Unlimited |
| Permission set targeting | — | ✓ |
| Segment + custom field targeting | — | ✓ |
| Percentage rollout targeting | — | ✓ |
| Multi-variant experiments + weights | — | ✓ |
| Batch evaluation (`FeatureFlag.flags()`) | — | ✓ |
| Platform Cache integration | — | ✓ |
| `FlipSwitch_Admin` LWC dashboard | — | ✓ |
| Analytics (`FlipSwitch_Metric__c`) | — | ✓ |
| Evaluation log viewer in admin UI | — | ✓ |
| Plugin framework (`FeatureFlagPlugin`) | — | ✓ |
| `CallableFeatureFlag` (System.Callable) | — | ✓ |
| `suspendLogging` / `flushEvaluations` | — | ✓ |
| Scenario tagging (`setScenario`) | — | ✓ |
| Auto-expiration scheduled job | — | ✓ |
| Flag hygiene / stale flag report | — | ✓ |
| NebulaLogger integration | — | ✓ |
| New Relic dashboard templates | — | ✓ |
| PagerDuty kill switch alerts | — | ✓ |
| Priority support + SLA | — | ✓ |

---

## License Enforcement Architecture

### Salesforce License Management App (LMA)

The LMA is the standard Salesforce mechanism for ISV license management. It links AppExchange installs to your Partner Business Org (PBO) and allows per-org license assignment.

```
AppExchange Install
        │
        ▼
  LMA records license in Partner Business Org
        │
        ▼
  Post-install script assigns:
    • Free: FlipSwitch_User permission set
    • Pro:  FlipSwitch_User + FlipSwitch_Pro permission sets
        │
        ▼
  Apex license check at evaluation time:
    FeatureFlagLicense.isPro()
      → FeatureManagement.checkPermission('FlipSwitch_Pro_Features')
```

### Custom Permission-Based Gating

```apex
// flipswitch namespace — internal only
public class FeatureFlagLicense {
    public static Boolean isPro() {
        return FeatureManagement.checkPermission('FlipSwitch_Pro_Features');
    }

    public static void assertPro(String featureName) {
        if (!isPro()) {
            throw new FeatureFlagException(
                featureName + ' requires FlipSwitch Pro. ' +
                'Upgrade at https://appexchange.salesforce.com/...'
            );
        }
    }

    public static Integer getActiveFlag Limit() {
        return isPro() ? Integer.MAX_VALUE : 25;
    }
}
```

Custom permissions:
- `FlipSwitch_Pro_Features` — gates all Pro-tier Apex paths
- `FlipSwitch_Admin_Access` — gates the admin dashboard LWC
- `FlipSwitch_User_Access` — base permission for any evaluation

License check happens in `FeatureFlagEvaluator` before Pro-only evaluation paths (percentage rollout, segment matching, batch evaluation).

---

## Namespace Strategy

| Item | Value |
|------|-------|
| Namespace prefix | `flipswitch` |
| Package name | FlipSwitch — Feature Flag Framework |
| API name prefix (Apex) | `flipswitch__FeatureFlag` (runtime), `FeatureFlag` (dev) |
| Object API names | `flipswitch__FlipSwitch_Rule__c`, etc. |
| CMDT names | `flipswitch__FlipSwitch_Flag__mdt`, etc. |

### Impact on Apex Class Access Modifiers

All public API classes must become `global` for the managed package to expose them to subscriber org Apex:

```apex
// Unlocked package (v1)
public class FeatureFlag { ... }
public interface FeatureFlagHandler { ... }

// Managed package (v2 AppExchange)
global class FeatureFlag { ... }
global interface FeatureFlagHandler { ... }
global class FeatureFlagResult { ... }
global class FeatureFlagBuilder { ... }
global class FeatureFlagBatchBuilder { ... }
```

Internal engine classes (`FeatureFlagEvaluator`, `FeatureFlagCache`, `FeatureFlagHash`, `FeatureFlagContext`, `FeatureFlagLogger`) remain `public` and use `@namespaceAccessible` only if needed by extension packages.

### Dual SFDX Package Directory Structure

```
sfdx-project.json
force-app/
├── main/default/          ← shared core source
└── managed/default/       ← managed-only overrides (global modifiers, etc.)

packages/
├── unlocked/              ← v1 GitHub distribution
└── managed/               ← v2 AppExchange distribution
```

---

## AppExchange Requirements & Checklist

### 1. Salesforce Partner Account

- [ ] Register at [Salesforce Partner Community](https://partners.salesforce.com)
- [ ] Sign ISV Agreement (Technology Partner track for free/paid apps)
- [ ] Obtain a Partner Business Org (PBO) — production org for LMA and package publishing
- [ ] Enable namespace registration in PBO: Setup → App Manager → Namespaces

### 2. Managed Package Creation

- [ ] Create namespace `flipswitch` in PBO
- [ ] Create managed package in PBO: Setup → Package Manager → New
- [ ] Set up second-generation packaging (2GP) in scratch org with namespace
  ```bash
  sf package create --name "FlipSwitch" --package-type Managed \
    --path force-app --target-dev-hub <PBO_alias>
  ```
- [ ] Add License Management App (LMA) to PBO
- [ ] Configure `sfdx-project.json` with namespace and package ID

### 3. Security Review Preparation

The Salesforce Security Review is the primary gate for AppExchange publishing. Plan for 4–8 weeks minimum.

#### Required Code Practices

- [ ] No hardcoded credentials, IDs, or URLs
- [ ] All user input sanitized — SOQL injection prevention:
  ```apex
  // Bad
  [SELECT Id FROM FlipSwitch_Rule__c WHERE Flag_Key__c = :userInput]
  // Good — already parameterized, but verify no dynamic SOQL in evaluator
  ```
- [ ] No `without sharing` unless explicitly documented and justified
- [ ] All `@AuraEnabled` methods use `with sharing`
- [ ] XSS prevention in all LWC components (no `innerHTML` or `lwc:ref` with raw HTML)
- [ ] No `Crypto` key material stored or logged
- [ ] CRUD/FLS enforcement on all DML and SOQL operations:
  ```apex
  // Use Schema.SObjectType.FlipSwitch_Rule__c.isAccessible() checks
  // Or use WITH SECURITY_ENFORCED in SOQL
  ```
- [ ] No deprecated APIs
- [ ] All remote site settings documented
- [ ] No external callouts from synchronous Apex (async only)

#### Security Review Submission Artifacts

- [ ] Application Overview document (1–2 pages explaining what the app does)
- [ ] Architecture diagram
- [ ] Data flow diagram (especially for Platform Events)
- [ ] List of all external endpoints (none for v1 — zero dependencies)
- [ ] Test org with the package pre-installed
- [ ] All test credentials for the review team
- [ ] User guide / admin guide

#### Automated Security Scanning

Run before submission:
```bash
# Salesforce CLI Scanner
sf scanner run --target force-app --engine pmd,eslint --format table

# RetireJS for LWC dependencies
sf scanner run --target force-app/main/default/lwc --engine retire-js

# AppExchange Security Scanner (in Partner Community)
# Upload package zip → automated scan → fix all Critical/High findings
```

### 4. AppExchange Listing Setup

- [ ] Create listing in [AppExchange Publishing Console](https://appexchangedev.salesforce.com)
- [ ] Write listing copy (see Listing Content section below)
- [ ] Upload screenshots (min 3, max 10; 1280×960 recommended)
- [ ] Upload demo video (2–4 minutes recommended)
- [ ] Configure pricing: Free tier + Pro tier (see Pricing section)
- [ ] Set compatibility matrix (Salesforce editions, API version)
- [ ] Submit for AppExchange review (separate from Security Review)

---

## Pricing Model

### Free Tier (Community Edition)
- **Price**: $0 forever
- **Install**: Direct from AppExchange, no credit card
- **Support**: Community (Trailblazer Community group, GitHub Issues)
- **Upgrades**: In-app link to Pro listing page

### Pro Tier
Pricing options (choose based on market research):

| Model | Price | Notes |
|-------|-------|-------|
| Per-org flat rate | $99–$299/org/year | Simple, predictable |
| Per-user | $3–$8/user/month | Scales with org size |
| Tiered by active flags | $149 (50 flags) / $299 (unlimited) | Feature-based |
| Enterprise | Custom quote | 100+ users, SLA, SSO |

**Recommended starting point**: $199/org/year flat rate. Simple, matches common developer tooling pricing (similar to Copado, Gearset tier pricing). Revisit after first 50 Pro customers.

### Trial
- 30-day full Pro trial on install (no credit card required)
- LMA auto-assigns `FlipSwitch_Pro_Features` custom permission for 30 days
- Trial-to-paid conversion prompt via in-app banner in admin dashboard

---

## AppExchange Listing Content

### Tagline
> Deploy anytime. Release when ready. Roll back in seconds.

### Short Description (165 chars)
> Native Salesforce feature flags, percentage rollouts, and kill switches for Apex, LWC, and Flows. No deployment needed to toggle features.

### Long Description (sections)

**The Problem**
Every Salesforce deployment is all-or-nothing. No gradual rollout. No instant rollback. No production testing without affecting all users. One bad release means 30–90 minutes of emergency redeployment.

**The Solution**
FlipSwitch brings progressive delivery to Salesforce. Toggle features without deploying. Roll out to 5% of users before going to 100%. Kill a broken feature in under 60 seconds.

**Key Features**
- Feature flags controlled via CMDT (deployable) and Custom Objects (runtime, no deploy needed)
- Percentage rollouts using deterministic hashing — same user always gets the same result
- User, profile, and permission set targeting
- Multi-variant A/B experiments with weighted distribution
- One-click kill switches from the admin dashboard
- Native LWC components for conditional rendering (`<c-feature-flag-gate>`)
- Flow invocable action for no-code feature decisions
- Clean Apex API: `FeatureFlag.isEnabled('MY_FEATURE')` — one line

**Why Native?**
No external SaaS dependency. No data leaves your org. No per-evaluation API calls. Runs entirely in your Salesforce org with zero latency overhead.

### Categories
- Developer Tools
- Admin Tools
- Productivity

### Industries
- All industries (cross-vertical)

---

## Technical Differences: Unlocked vs Managed

| Aspect | Unlocked (v1, GitHub) | Managed (v2, AppExchange) |
|--------|----------------------|--------------------------|
| Namespace | None | `flipswitch` |
| Apex access | `public` | `global` (API classes) |
| Object API names | `FlipSwitch_Rule__c` | `flipswitch__FlipSwitch_Rule__c` |
| Plugin framework | Full (interface extensible) | Limited (ISVs extend via `global` interface) |
| Source visible | Yes (MIT, open-source) | No (compiled) |
| Upgradeable | Manual reinstall | Managed upgrades via AppExchange |
| License enforcement | None | LMA + custom permissions |
| Security Review | Not required | Required |
| SOQL from consumer | Direct object access | Namespace-qualified access |

### Migration Path: Unlocked → Managed

Orgs that installed the unlocked v1 package cannot automatically migrate to the managed package (different namespace, different object API names). Migration options:

1. **Side-by-side install**: Install managed package in parallel, migrate flags manually via admin UI export/import tool (build this in Pro tier).
2. **Migration script**: Apex batch job that reads unlocked objects and creates managed package records.
3. **Clean install**: For new orgs or orgs willing to rebuild their flag definitions.

Document this prominently in the AppExchange listing and migration guide.

---

## Implementation Phases for AppExchange

This extends the 7-phase plan in `plan.md` with AppExchange-specific phases:

| Phase | Scope | Prerequisite |
|-------|-------|-------------|
| 1–5 | Core implementation (per `plan.md`) | — |
| 6a | Unlocked package v1 (GitHub launch) | Phases 1–5 |
| 6b | Namespace + managed package setup | Phase 6a stable |
| 6c | License enforcement (`FeatureFlagLicense`) | Phase 6b |
| 6d | `global` access modifiers + `@namespaceAccessible` | Phase 6c |
| 6e | Migration tooling (export/import for unlocked → managed) | Phase 6d |
| 7a | Security Review preparation + automated scanning | Phase 6e |
| 7b | AppExchange listing creation + screenshots + video | Phase 7a |
| 7c | Security Review submission | Phase 7b |
| 7d | LMA setup + pricing configuration | Phase 7c |
| 7e | AppExchange go-live | Phase 7d (approval) |

### Estimated Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| 1–5 (core) | 8–12 weeks | Per existing plan |
| 6a (GitHub launch) | 1 week | Package publish + README |
| 6b–6e (managed setup) | 3–4 weeks | Namespace, license, migration tool |
| 7a (security prep) | 2–3 weeks | Fix scanner findings |
| 7b (listing) | 1 week | Copy, screenshots, video |
| 7c (security review) | 4–8 weeks | Salesforce review SLA |
| 7d–7e (go-live) | 1–2 weeks | LMA config, final checks |
| **Total** | **~6 months** | From start to AppExchange live |

---

## Partner Program Requirements

### Technology Partner Track
- Annual fee: $0 (free tier) or ISV royalty model depending on revenue
- ISV royalty: Salesforce takes 15% of AppExchange revenue (via Checkout)
- Alternatively: Direct billing (invoice customers outside Salesforce Checkout) — no royalty, but less frictionless for buyers

### Salesforce Checkout vs Direct Billing

| Aspect | Salesforce Checkout | Direct Billing |
|--------|--------------------|-|
| Royalty to Salesforce | 15% | 0% |
| Buyer friction | Low (in-app, existing payment) | Higher (separate invoice) |
| LMA integration | Automatic | Manual license provisioning |
| Recommended for | B2C, low-touch sales | Enterprise, custom contracts |

**Recommendation**: Start with Salesforce Checkout for simplicity. Move enterprise deals to direct billing as sales motion matures.

---

## Go-to-Market Strategy

### Phase 1: Community (GitHub v1)
- Open-source launch on GitHub (MIT license)
- Blog post: "Building Feature Flags for Salesforce with FlipSwitch"
- Trailblazer Community post in Apex and Developer groups
- Demo at local Salesforce user group meetup

### Phase 2: AppExchange Launch
- Free tier AppExchange listing (zero barrier to install)
- Product Hunt launch (Salesforce developer audience present there)
- Salesforce Ben / Admin article (approach for editorial coverage)
- Dreamforce/TDX demo session submission

### Phase 3: Pro Conversion
- In-app trial banner in admin dashboard after 15 days
- Email drip to trial users (via LMA install notifications)
- Case studies from early adopters
- Comparison page vs LaunchDarkly (native vs SaaS cost)

---

## Support Model

### Free Tier
- GitHub Issues (best-effort, community-driven)
- Trailblazer Community group: `FlipSwitch Feature Flags`
- Documentation site (GitHub Pages or Gitbook)

### Pro Tier
- Email support: support@flipswitch.io (target 24-hour response, business days)
- SLA: P1 (data loss/evaluation broken) → 4-hour response; P2 (feature broken) → 1 business day; P3 (question) → 3 business days
- Dedicated Slack channel for Enterprise tier ($499+/org/year)
- Quarterly roadmap calls for Enterprise customers

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Security Review rejection | Medium | High (delays launch 4–8 wks) | Run automated scanners early; fix all Critical/High before submission |
| Namespace squatting (`flipswitch` taken) | Low | High (rename everything) | Check namespace availability in Partner Community before any code using namespace |
| Unlocked → managed migration friction | High | Medium | Build migration tool in Phase 6e; document clearly in listing |
| Low Pro conversion rate (<5%) | Medium | Medium | Add more compelling Pro-only features; improve in-app upgrade prompts |
| AppExchange listing buried | Medium | Medium | Solicit early reviews; optimize listing SEO; partner with Salesforce Ben |
| LMA/license complexity | Medium | Low | Test license gating thoroughly in scratch orgs with simulated trial/expired states |

---

## Key Decisions Required

1. **Namespace**: Confirm `flipswitch` is available in Partner Community before proceeding. Alternatives: `fswitch`, `progressivedelivery`, `featureflags`.

2. **Pricing model**: Flat per-org ($199/year) vs per-user vs tiered. Needs market validation.

3. **Billing**: Salesforce Checkout (15% royalty, easy) vs direct invoicing (0% royalty, more work). Start with Checkout.

4. **Free flag limit**: 25 active flags recommended. Validate this creates meaningful upgrade pressure without frustrating legitimate free users.

5. **Plugin framework in managed**: `global` interfaces in managed packages cannot be changed without breaking subscribers. Finalize the `FeatureFlagPlugin` interface contract before managed package v1.0 release — it's effectively permanent.

6. **Migration tooling priority**: Build the unlocked → managed migration tool before AppExchange launch, or accept that early adopters will need to manually rebuild their flag definitions.

---

## References

- [Salesforce ISV Guide](https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/)
- [AppExchange Security Review Guide](https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/security_review_overview.htm)
- [License Management App (LMA)](https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/lma_intro.htm)
- [Salesforce CLI: Managed Packages](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_dev2gp_create_pkg.htm)
- [NebulaLogger (comparable project)](https://github.com/jongpie/NebulaLogger)
- `plan.md` — core technical specification (source of truth)
