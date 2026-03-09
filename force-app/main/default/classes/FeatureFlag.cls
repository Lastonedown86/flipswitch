/**
 * @description FlipSwitch entry point.
 *
 *              Provides:
 *              1. Static convenience API — one-liners for common checks
 *              2. Factory methods — fluent builder entry points
 *              3. Transaction controls — NebulaLogger-inspired buffering
 *              4. AuraEnabled methods for LWC wire adapters
 *
 *              Quick reference:
 *              FeatureFlag.isEnabled('MY_FLAG')
 *              FeatureFlag.flag('MY_FLAG').forUser(id).withAttribute('k','v').isEnabled()
 *              FeatureFlag.flags('A','B').forUser(id).evaluateAll()
 */
public class FeatureFlag {

    /**
     * @description How evaluation logs are persisted.
     *              EVENT_BUS   — default, async Platform Event (recommended)
     *              QUEUEABLE   — deferred via System.enqueueJob (high-volume)
     *              SYNCHRONOUS — direct DML, testing/debug only
     */
    public enum SaveMethod { EVENT_BUS, QUEUEABLE, SYNCHRONOUS }

    // Transaction-scoped scenario tag — applies to all evaluations in this transaction
    @TestVisible
    static String currentScenario;

    // ─── Static convenience API ───────────────────────────────────────────

    /**
     * @description Quick boolean check for the running user.
     * @param flagKey  Feature_Flag__mdt DeveloperName
     * @return         true if the flag is enabled
     */
    public static Boolean isEnabled(String flagKey) {
        return flag(flagKey).isEnabled();
    }

    /**
     * @description Quick variant check for the running user.
     * @param flagKey  Feature_Flag__mdt DeveloperName
     * @return         Variant key, or 'true'/'false' for boolean flags
     */
    public static String getVariant(String flagKey) {
        return flag(flagKey).getVariant();
    }

    // ─── Factory methods ──────────────────────────────────────────────────

    /**
     * @description Create a fluent single-flag builder.
     * @param flagKey  Feature_Flag__mdt DeveloperName
     */
    public static FeatureFlagBuilder flag(String flagKey) {
        return new FeatureFlagBuilder(flagKey);
    }

    /**
     * @description Create a fluent multi-flag batch builder.
     * @param flagKeys  Comma-separated or List of DeveloperNames
     */
    public static FeatureFlagBatchBuilder flags(String flagKey1, String flagKey2) {
        return new FeatureFlagBatchBuilder(new List<String>{ flagKey1, flagKey2 });
    }

    public static FeatureFlagBatchBuilder flags(String flagKey1, String flagKey2, String flagKey3) {
        return new FeatureFlagBatchBuilder(new List<String>{ flagKey1, flagKey2, flagKey3 });
    }

    public static FeatureFlagBatchBuilder flags(List<String> flagKeys) {
        return new FeatureFlagBatchBuilder(flagKeys);
    }

    // ─── Transaction controls (NebulaLogger pattern) ──────────────────────

    /**
     * @description Stop buffering evaluation logs. Use in performance-critical paths
     *              where you don't need analytics for specific evaluations.
     */
    public static void suspendLogging() {
        FeatureFlagLogger.suspend();
    }

    /**
     * @description Resume buffering evaluation logs.
     */
    public static void resumeLogging() {
        FeatureFlagLogger.resume();
    }

    /**
     * @description Publish all buffered evaluation events as a single DML call.
     *              Call this at the end of a transaction (or in a trigger after handler).
     */
    public static void flushEvaluations() {
        FeatureFlagLogger.flush();
    }

    /**
     * @description Tag all subsequent evaluations in this transaction with a scenario.
     *              Enables per-business-flow analytics.
     * @param scenario  Human-readable label (e.g. 'Checkout Flow', 'Lead Assignment')
     */
    public static void setScenario(String scenario) {
        currentScenario = scenario;
        FeatureFlagLogger.setScenario(scenario);
    }

    /**
     * @description Override the save method for this transaction.
     */
    public static void setSaveMethod(SaveMethod method) {
        FeatureFlagLogger.setSaveMethod(method);
    }

    // ─── AuraEnabled methods for LWC ──────────────────────────────────────

    /**
     * @description Evaluate a flag for the running user. Used by featureFlagGate LWC.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isEnabledForCurrentUser(String flagKey) {
        return isEnabled(flagKey);
    }

    /**
     * @description Get the variant for the running user. Used by featureFlagVariant LWC.
     */
    @AuraEnabled(cacheable=true)
    public static String getVariantForCurrentUser(String flagKey) {
        return getVariant(flagKey);
    }

    /**
     * @description Batch evaluate multiple flags for LWC service module.
     *              Returns a JSON-serializable map.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> evaluateFlagsForCurrentUser(List<String> flagKeys) {
        Map<String, FeatureFlagResult> results = flags(flagKeys).evaluateAll();
        Map<String, Object> response = new Map<String, Object>();
        for (String key : results.keySet()) {
            FeatureFlagResult r = results.get(key);
            response.put(key, new Map<String, Object>{
                'isEnabled' => r.isEnabled,
                'variant'   => r.variant,
                'reason'    => r.reason
            });
        }
        return response;
    }

    /**
     * @description Get all feature flags for the admin dashboard.
     */
    @AuraEnabled(cacheable=true)
    public static List<Feature_Flag__mdt> getAllFlags() {
        return [
            SELECT DeveloperName, Label, Type__c, Default_Value__c,
                   Is_Active__c, Expiration_Date__c, Category__c, Description__c
            FROM Feature_Flag__mdt
            ORDER BY Category__c, Label
        ];
    }

    /**
     * @description Create a kill switch rule for a flag.
     *              Called from the admin UI kill switch button.
     */
    @AuraEnabled
    public static void activateKillSwitch(String flagKey) {
        Feature_Flag_Rule__c killRule = new Feature_Flag_Rule__c(
            Name                = 'Kill Switch — ' + flagKey,
            Feature_Flag_Key__c = flagKey,
            Rule_Type__c        = 'Kill_Switch',
            Priority__c         = 1,
            Is_Active__c        = true
        );
        insert killRule;
        // Invalidate cache so the kill switch takes effect immediately
        FeatureFlagCache.removeFlag(flagKey);
    }

    /**
     * @description Remove a kill switch rule for a flag (re-enable).
     */
    @AuraEnabled
    public static void deactivateKillSwitch(String flagKey) {
        List<Feature_Flag_Rule__c> killRules = [
            SELECT Id FROM Feature_Flag_Rule__c
            WHERE Feature_Flag_Key__c = :flagKey
              AND Rule_Type__c = 'Kill_Switch'
              AND Is_Active__c = TRUE
        ];
        if (!killRules.isEmpty()) {
            delete killRules;
        }
        FeatureFlagCache.removeFlag(flagKey);
    }
}
