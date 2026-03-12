/**
 * @description Fluent multi-flag builder. Returned by FeatureFlag.flags().
 *
 *              Loads ALL targeting rules for the requested flags in a single
 *              SOQL query, then evaluates each flag using the pre-loaded rules.
 *              Use this when checking multiple flags in the same transaction.
 *
 *              Map<String, FeatureFlagResult> results =
 *                  FeatureFlag.flags('FLAG_A', 'FLAG_B', 'FLAG_C')
 *                      .forUser(userId)
 *                      .evaluateAll();
 */
public inherited sharing class FeatureFlagBatchBuilder {

    private final List<String> flagKeys;
    private Id targetUserId;
    private Map<String, Object> attributes = new Map<String, Object>();
    private String scenario;

    public FeatureFlagBatchBuilder(List<String> flagKeys) {
        this.flagKeys = flagKeys;
    }

    // ─── Fluent configuration methods ─────────────────────────────────────

    /** @description Evaluate all flags for a specific user (defaults to running user). */
    public FeatureFlagBatchBuilder forUser(Id userId) {
        this.targetUserId = userId;
        return this;
    }

    /** @description Add a shared context attribute applied to all flag evaluations. */
    public FeatureFlagBatchBuilder withAttribute(String key, Object value) {
        this.attributes.put(key, value);
        return this;
    }

    /** @description Bulk add shared context attributes. */
    public FeatureFlagBatchBuilder withAttributes(Map<String, Object> attrs) {
        this.attributes.putAll(attrs);
        return this;
    }

    /** @description Tag all evaluations with a business scenario. */
    public FeatureFlagBatchBuilder inScenario(String scenario) {
        this.scenario = scenario;
        return this;
    }

    // ─── Terminal method ──────────────────────────────────────────────────

    /**
     * @description Evaluate all flags and return a map of flagKey → result.
     *              Uses a single SOQL query for all rules.
     */
    public Map<String, FeatureFlagResult> evaluateAll() {
        Map<String, FeatureFlagResult> results = new Map<String, FeatureFlagResult>();

        if (flagKeys == null || flagKeys.isEmpty()) {
            return results;
        }

        // Single SOQL: load all rules for all requested flags
        Set<String> flagKeySet = new Set<String>(flagKeys);
        List<FlipSwitch_Rule__c> allRules = FeatureFlagEvaluator.loadRulesForFlags(flagKeySet);

        // Build shared context once
        Id userId = targetUserId != null ? targetUserId : UserInfo.getUserId();
        FeatureFlagContext sharedCtx = FeatureFlagContext.forUser(userId);
        sharedCtx.withAttributes(attributes);
        if (String.isNotBlank(scenario)) {
            sharedCtx.withScenario(scenario);
        } else if (String.isNotBlank(FeatureFlag.currentScenario)) {
            sharedCtx.withScenario(FeatureFlag.currentScenario);
        }

        for (String flagKey : flagKeys) {
            FeatureFlagContext ctx = FeatureFlagContext.forUser(userId);
            ctx.withAttributes(attributes);
            ctx.withFlagKey(flagKey);
            if (String.isNotBlank(sharedCtx.scenario)) {
                ctx.withScenario(sharedCtx.scenario);
            }

            FeatureFlagResult result = FeatureFlagEvaluator.evaluate(flagKey, ctx, allRules);
            FeatureFlagLogger.log(result, ctx);
            results.put(flagKey, result);
        }

        return results;
    }
}
