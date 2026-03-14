/**
 * @description Fluent single-flag builder. Returned by FeatureFlag.flag().
 *
 *              Chain configuration methods then call a terminal method to
 *              trigger evaluation:
 *
 *              FeatureFlag.flag('NEW_CHECKOUT')
 *                  .forUser(userId)
 *                  .withAttribute('region', 'US')
 *                  .fallback(false)
 *                  .isEnabled()
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public inherited sharing class FeatureFlagBuilder {

    private final String flagKey;
    private Id targetUserId;
    private Id targetAccountId;
    private Map<String, Object> attributes = new Map<String, Object>();
    private Object fallbackValue;
    private Boolean silentMode = false;
    private Boolean dmlAllowed = false;
    private String scenario;
    private FeatureFlagHandler enabledHandler;
    private FeatureFlagHandler disabledHandler;
    private List<FlipSwitch_Rule__c> preloadedRules;

    /** @description Construct a builder for the given flag key.
     *  @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     */
    public FeatureFlagBuilder(String flagKey) {
        this.flagKey = flagKey;
    }

    // ─── Fluent configuration methods ─────────────────────────────────────

    /** @description Evaluate for a specific user (defaults to running user).
     *  @param userId  Target user Id
     *  @return        this builder for chaining
     */
    public FeatureFlagBuilder forUser(Id userId) {
        this.targetUserId = userId;
        return this;
    }

    /** @description Add a context attribute for segment / custom field matching.
     *  @param key    Attribute name
     *  @param value  Attribute value
     *  @return       this builder for chaining
     */
    public FeatureFlagBuilder withAttribute(String key, Object value) {
        this.attributes.put(key, value);
        return this;
    }

    /** @description Bulk add context attributes.
     *  @param attrs  Map of attribute key-value pairs
     *  @return       this builder for chaining
     */
    public FeatureFlagBuilder withAttributes(Map<String, Object> attrs) {
        this.attributes.putAll(attrs);
        return this;
    }

    /** @description Override the CMDT default value if no rules match.
     *  @param value  Boolean fallback value
     *  @return       this builder for chaining
     */
    public FeatureFlagBuilder fallback(Boolean value) {
        this.fallbackValue = value;
        return this;
    }

    /** @description Override the CMDT default value (String variant).
     *  @param value  String fallback variant
     *  @return       this builder for chaining
     */
    public FeatureFlagBuilder fallback(String value) {
        this.fallbackValue = value;
        return this;
    }

    /** @description Suppress evaluation logging for this call.
     *  @return  this builder for chaining
     */
    public FeatureFlagBuilder silent() {
        this.silentMode = true;
        return this;
    }

    /** @description Tag this evaluation with a business scenario.
     *  @param scenario  Human-readable scenario label
     *  @return          this builder for chaining
     */
    public FeatureFlagBuilder inScenario(String scenario) {
        this.scenario = scenario;
        return this;
    }

    /** @description Register callback to run when the flag is enabled.
     *  @param handler  FeatureFlagHandler to invoke
     *  @return         this builder for chaining
     */
    public FeatureFlagBuilder whenEnabled(FeatureFlagHandler handler) {
        this.enabledHandler = handler;
        return this;
    }

    /** @description Register callback to run when the flag is disabled.
     *  @param handler  FeatureFlagHandler to invoke
     *  @return         this builder for chaining
     */
    public FeatureFlagBuilder whenDisabled(FeatureFlagHandler handler) {
        this.disabledHandler = handler;
        return this;
    }

    /** @description Set the Account Id for account-level targeting rules.
     *  @param accountId  Target account Id
     *  @return           this builder for chaining
     */
    public FeatureFlagBuilder withAccount(Id accountId) {
        this.targetAccountId = accountId;
        return this;
    }

    /** @description Allow DML operations during evaluation (e.g. inventory checks).
     *  @return  this builder for chaining
     */
    public FeatureFlagBuilder allowDml() {
        this.dmlAllowed = true;
        return this;
    }

    /** @description Returns whether DML is allowed for this evaluation.
     *  @return  true if DML was enabled via allowDml()
     */
    public Boolean isDmlAllowed() {
        return this.dmlAllowed;
    }

    /** @description Expose the built context for test inspection.
     *  @return  the FeatureFlagContext that would be used for evaluation
     */
    @TestVisible
    private FeatureFlagContext getContext() {
        return buildContext();
    }

    /** @description Inject pre-loaded rules (used by FeatureFlagBatchBuilder).
     *  @param rules  Pre-loaded targeting rules
     *  @return       this builder for chaining
     */
    @TestVisible
    FeatureFlagBuilder withPreloadedRules(List<FlipSwitch_Rule__c> rules) {
        this.preloadedRules = rules;
        return this;
    }

    // ─── Terminal methods ─────────────────────────────────────────────────

    /** @description Evaluate and return whether the flag is enabled.
     *  @return  true if the flag is enabled
     */
    public Boolean isEnabled() {
        return evaluate().isEnabled;
    }

    /** @description Evaluate and return the variant key.
     *  @return  Variant key string
     */
    public String getVariant() {
        FeatureFlagResult result = evaluate();
        return result.variant != null ? result.variant
            : (result.isEnabled ? 'true' : 'false');
    }

    /** @description Evaluate and return the variant payload.
     *  @return  Payload map, or null
     */
    public Map<String, Object> getPayload() {
        return evaluate().payload;
    }

    /**
     * @description Evaluate and return the full result.
     *              This is the core terminal method — all others delegate here.
     * @return      FeatureFlagResult containing isEnabled, variant, reason, payload
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    public FeatureFlagResult evaluate() {
        FeatureFlagContext ctx = buildContext();
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(flagKey, ctx, preloadedRules);

        // Apply fallback if the default was used (or flag is not yet configured) and a fallback was specified
        if (fallbackValue != null
            && (result.reason == FeatureFlagResult.REASON_DEFAULT
                || result.reason == FeatureFlagResult.REASON_NOT_CONFIGURED)) {
            // Override isEnabled to honour the fallback
            if (fallbackValue instanceof Boolean) {
                result = (Boolean) fallbackValue
                    ? FeatureFlagResult.enabled(null, null, FeatureFlagResult.REASON_DEFAULT)
                    : FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);
            } else {
                String fallbackVariant = String.valueOf(fallbackValue);
                result = FeatureFlagResult.enabled(fallbackVariant, null, FeatureFlagResult.REASON_DEFAULT);
            }
        }

        if (!silentMode) {
            FeatureFlagLogger.log(result, ctx);
        }

        runPlugins(result, ctx);

        return result;
    }

    /**
     * @description Evaluate and run the appropriate whenEnabled / whenDisabled handler.
     */
    public void execute() {
        FeatureFlagResult result = evaluate();
        if (result.isEnabled && enabledHandler != null) {
            enabledHandler.handle();
        } else if (!result.isEnabled && disabledHandler != null) {
            disabledHandler.handle();
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────

    private FeatureFlagContext buildContext() {
        Id userId = targetUserId != null ? targetUserId : UserInfo.getUserId();
        FeatureFlagContext ctx = FeatureFlagContext.forUser(userId);
        ctx.withAttributes(attributes);
        ctx.withFlagKey(flagKey);
        if (targetAccountId != null) {
            ctx.accountId = targetAccountId;
        }
        if (String.isNotBlank(scenario)) {
            ctx.withScenario(scenario);
        } else if (String.isNotBlank(FeatureFlag.currentScenario)) {
            ctx.withScenario(FeatureFlag.currentScenario);
        }
        return ctx;
    }

    private void runPlugins(FeatureFlagResult result, FeatureFlagContext ctx) {
        List<FlipSwitch_Plugin__mdt> pluginConfigs = [
            SELECT Class_Name__c, Priority__c
            FROM FlipSwitch_Plugin__mdt
            WHERE Is_Enabled__c = TRUE
            ORDER BY Priority__c ASC NULLS LAST
        ];

        for (FlipSwitch_Plugin__mdt config : pluginConfigs) {
            try {
                Type pluginType = Type.forName(config.Class_Name__c);
                if (pluginType != null) {
                    FeatureFlagPlugin plugin = (FeatureFlagPlugin) pluginType.newInstance();
                    plugin.onEvaluate(result, ctx);
                }
            } catch (Exception e) { // NOPMD - EmptyCatchBlock: plugin errors must not break evaluation
            }
        }
    }
}
