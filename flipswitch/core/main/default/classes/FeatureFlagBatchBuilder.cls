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
    private Id targetAccountId;
    private Map<String, Object> attributes = new Map<String, Object>();
    private String scenario;

    /** @description Construct a batch builder for the given flag keys.
     *  @param flagKeys  List of flag DeveloperNames
     */
    public FeatureFlagBatchBuilder(List<String> flagKeys) {
        this.flagKeys = flagKeys;
    }

    // ─── Fluent configuration methods ─────────────────────────────────────

    /** @description Evaluate all flags for a specific user (defaults to running user).
     *  @param userId  Target user Id
     *  @return        this builder for chaining
     */
    public FeatureFlagBatchBuilder forUser(Id userId) {
        this.targetUserId = userId;
        return this;
    }

    /** @description Add a shared context attribute applied to all flag evaluations.
     *  @param key    Attribute name
     *  @param value  Attribute value
     *  @return       this builder for chaining
     */
    public FeatureFlagBatchBuilder withAttribute(String key, Object value) {
        this.attributes.put(key, value);
        return this;
    }

    /** @description Bulk add shared context attributes.
     *  @param attrs  Map of attribute key-value pairs
     *  @return       this builder for chaining
     */
    public FeatureFlagBatchBuilder withAttributes(Map<String, Object> attrs) {
        this.attributes.putAll(attrs);
        return this;
    }

    /** @description Set the Account Id for account-level targeting rules applied to all flag evaluations.
     *  @param accountId  Target account Id
     *  @return           this builder for chaining
     */
    public FeatureFlagBatchBuilder withAccount(Id accountId) {
        this.targetAccountId = accountId;
        return this;
    }

    /** @description Tag all evaluations with a business scenario.
     *  @param scenario  Human-readable scenario label
     *  @return          this builder for chaining
     */
    public FeatureFlagBatchBuilder inScenario(String scenario) {
        this.scenario = scenario;
        return this;
    }

    // ─── Terminal method ──────────────────────────────────────────────────

    /**
     * @description Evaluate all flags and return a map of flagKey to result.
     *              Uses a single SOQL query for all rules.
     * @return  Map of flagKey to FeatureFlagResult
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
            if (targetAccountId != null) {
                ctx.accountId = targetAccountId;
            }
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
