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
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.ExcessivePublicCount')
public inherited sharing class FeatureFlag {

    /**
     * @description How evaluation logs are persisted.
     *              EVENT_BUS   — default, async Platform Event (recommended)
     *              QUEUEABLE   — deferred via System.enqueueJob (high-volume)
     *              SYNCHRONOUS — direct DML, testing/debug only
     */
    public enum SaveMethod { EVENT_BUS, QUEUEABLE, SYNCHRONOUS }

    // Transaction-scoped scenario tag — applies to all evaluations in this transaction
    @TestVisible
    public static String currentScenario;

    // ─── Static convenience API ───────────────────────────────────────────

    /**
     * @description Quick boolean check for the running user.
     * @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     * @return         true if the flag is enabled
     */
    public static Boolean isEnabled(String flagKey) {
        return flag(flagKey).isEnabled();
    }

    /**
     * @description Quick variant check for the running user.
     * @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     * @return         Variant key, or 'true'/'false' for boolean flags
     */
    public static String getVariant(String flagKey) {
        return flag(flagKey).getVariant();
    }

    // ─── Factory methods ──────────────────────────────────────────────────

    /**
     * @description Create a fluent single-flag builder.
     * @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     * @return         FeatureFlagBuilder instance
     */
    public static FeatureFlagBuilder flag(String flagKey) {
        return new FeatureFlagBuilder(flagKey);
    }

    /**
     * @description Create a fluent multi-flag batch builder.
     * @param flagKey1  First flag DeveloperName
     * @param flagKey2  Second flag DeveloperName
     * @return          FeatureFlagBatchBuilder instance
     */
    public static FeatureFlagBatchBuilder flags(String flagKey1, String flagKey2) {
        return new FeatureFlagBatchBuilder(new List<String>{ flagKey1, flagKey2 });
    }

    /** @description Create a fluent multi-flag batch builder (3 args).
     *  @param flagKey1  First flag DeveloperName
     *  @param flagKey2  Second flag DeveloperName
     *  @param flagKey3  Third flag DeveloperName
     *  @return          FeatureFlagBatchBuilder instance
     */
    public static FeatureFlagBatchBuilder flags(String flagKey1, String flagKey2, String flagKey3) {
        return new FeatureFlagBatchBuilder(new List<String>{ flagKey1, flagKey2, flagKey3 });
    }

    /** @description Create a fluent multi-flag batch builder (list).
     *  @param flagKeys  List of flag DeveloperNames
     *  @return          FeatureFlagBatchBuilder instance
     */
    public static FeatureFlagBatchBuilder flags(List<String> flagKeys) {
        return new FeatureFlagBatchBuilder(flagKeys);
    }

    // ─── Flag definition API ──────────────────────────────────────────────

    /**
     * @description Create a fluent flag definition builder for inline declaration.
     *              Use this to self-document flag metadata in code and auto-register
     *              the flag in the runtime registry so the admin dashboard discovers
     *              it without a metadata deployment.
     *
     *              Idempotent — safe to call every transaction. Existing records
     *              are only updated for fields that are currently null/blank.
     *
     *              FeatureFlag.define('NEW_CHECKOUT')
     *                  .type('Boolean')
     *                  .category('Checkout')
     *                  .description('Redesigned checkout flow')
     *                  .register();
     *
     * @param flagKey  Unique flag identifier (DeveloperName convention)
     * @return         FeatureFlagDefinition fluent builder
     */
    public static FeatureFlagDefinition define(String flagKey) {
        return new FeatureFlagDefinition(flagKey);
    }

    /**
     * @description Register a flag key with safe defaults (Boolean, disabled).
     *              Shorthand for FeatureFlag.define(flagKey).register().
     *              Useful in setup scripts, post-install handlers, and test setup.
     * @param flagKey  Unique flag identifier (DeveloperName convention)
     */
    public static void register(String flagKey) {
        FeatureFlagRegistry.registerIfNew(flagKey);
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
     * @param method  The SaveMethod enum value to use
     */
    public static void setSaveMethod(SaveMethod method) {
        FeatureFlagLogger.setSaveMethod(method);
    }

    // ─── AuraEnabled methods for LWC ──────────────────────────────────────

    /**
     * @description Evaluate a flag for the running user. Used by featureFlagGate LWC.
     * @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     * @return         true if the flag is enabled
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isEnabledForCurrentUser(String flagKey) {
        return isEnabled(flagKey);
    }

    /**
     * @description Get the variant for the running user. Used by featureFlagVariant LWC.
     * @param flagKey  FlipSwitch_Flag__mdt DeveloperName
     * @return         Variant key string
     */
    @AuraEnabled(cacheable=true)
    public static String getVariantForCurrentUser(String flagKey) {
        return getVariant(flagKey);
    }

    /**
     * @description Batch evaluate multiple flags for LWC service module.
     *              Returns a JSON-serializable map.
     * @param flagKeys  List of flag DeveloperNames
     * @return          Map of flagKey to evaluation result
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
     * @return  List of all FlipSwitch_Flag__mdt records
     */
    @AuraEnabled(cacheable=true)
    public static List<FlipSwitch_Flag__mdt> getAllFlags() {
        return [
            SELECT DeveloperName, Label, Type__c, Default_Value__c,
                   Is_Active__c, Expiration_Date__c, Category__c, Description__c
            FROM FlipSwitch_Flag__mdt
            ORDER BY Category__c, Label
        ];
    }

    /**
     * @description Create an emergency disable rule for a flag.
     *              Called from the admin UI emergency disable button.
     * @param flagKey  DeveloperName of the flag to emergency-disable
     */
    @AuraEnabled
    public static void activateEmergencyDisable(String flagKey) {
        FlipSwitch_Rule__c disableRule = new FlipSwitch_Rule__c(
            Name                = 'Emergency Disable — ' + flagKey,
            Flag_Key__c = flagKey,
            Rule_Type__c        = 'Emergency_Disable',
            Priority__c         = 1,
            Is_Active__c        = true
        );
        insert disableRule;
        // Invalidate cache so the emergency disable takes effect immediately
        FeatureFlagCache.removeFlag(flagKey);
    }

    /**
     * @description Remove an emergency disable rule for a flag (re-enable).
     * @param flagKey  DeveloperName of the flag to re-enable
     */
    @AuraEnabled
    public static void deactivateEmergencyDisable(String flagKey) {
        List<FlipSwitch_Rule__c> disableRules = [
            SELECT Id FROM FlipSwitch_Rule__c
            WHERE Flag_Key__c = :flagKey
              AND Rule_Type__c = 'Emergency_Disable'
              AND Is_Active__c = TRUE
        ];
        if (!disableRules.isEmpty()) {
            delete disableRules;
        }
        FeatureFlagCache.removeFlag(flagKey);
    }
}
