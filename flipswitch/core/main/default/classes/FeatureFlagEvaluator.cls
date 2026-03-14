/**
 * @description Core evaluation engine for FlipSwitch.
 *
 *              Evaluation order (highest to lowest priority):
 *              1. Emergency disable — Is_Active__c = false on CMDT
 *              2. Expiration  — Expiration_Date__c < TODAY
 *              3. QA override — FlipSwitch_Settings__c.Override_All_Flags__c
 *              4. Emergency disable rule — Rule_Type__c = Emergency_Disable
 *              5. Targeting rules by Priority__c ASC:
 *                 User → Profile → Permission_Set → Segment → Custom_Field → Percentage
 *                 → Account → Account_Segment → Territory
 *              6. Default value from CMDT
 *
 *              All exceptions are caught by the circuit breaker; callers
 *              always receive a safe default result, never an exception.
 */
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public inherited sharing class FeatureFlagEvaluator {

    /**
     * @description Evaluate a single flag for the given context.
     *              Pre-loaded rules (from batch builder) can be passed to
     *              avoid an extra SOQL query.
     *
     * @param flagKey       The FlipSwitch_Flag__mdt DeveloperName
     * @param ctx           Evaluation context (user, attributes, etc.)
     * @param preloadedRules Optional pre-loaded rules (null triggers a fresh query)
     * @return              FeatureFlagResult — never null, never throws
     */
    public static FeatureFlagResult evaluate(
        String flagKey,
        FeatureFlagContext ctx,
        List<FlipSwitch_Rule__c> preloadedRules
    ) {
        try {
            return doEvaluate(flagKey, ctx, preloadedRules);
        } catch (Exception e) {
            // Circuit breaker — return safe default
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_ERROR);
        }
    }

    // ─── Core evaluation logic ────────────────────────────────────────────

    private static FeatureFlagResult doEvaluate(
        String flagKey,
        FeatureFlagContext ctx,
        List<FlipSwitch_Rule__c> preloadedRules
    ) {
        // 1. Load flag definition from CMDT
        FlipSwitch_Flag__mdt flag = loadFlag(flagKey);
        if (flag == null) {
            return evaluateWithoutCmdt(flagKey, ctx, preloadedRules);
        }

        // 2. Emergency disable — CMDT Is_Active__c = false
        if (!flag.Is_Active__c) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_EMERGENCY_DISABLE);
        }

        // 3. Expiration check
        if (flag.Expiration_Date__c != null && flag.Expiration_Date__c < Date.today()) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_EXPIRED);
        }

        // 4. QA override → rules → default
        return evaluateWithRules(flagKey, ctx, preloadedRules, flag.Default_Value__c);
    }

    private static FeatureFlagResult evaluateWithoutCmdt(
        String flagKey,
        FeatureFlagContext ctx,
        List<FlipSwitch_Rule__c> preloadedRules
    ) {
        FeatureFlagRegistry.registerIfNew(flagKey);
        FlipSwitch_Flag_Registry__c regFlag = FeatureFlagRegistry.getRegistryFlag(flagKey);
        if (regFlag != null) {
            return evaluateRegistryFlag(regFlag, flagKey, ctx, preloadedRules);
        }
        return FeatureFlagResult.disabled(FeatureFlagResult.REASON_NOT_CONFIGURED);
    }

    // ─── Rule matching ────────────────────────────────────────────────────

    private static Boolean ruleMatches(
        FlipSwitch_Rule__c rule,
        FeatureFlagContext ctx,
        String flagKey
    ) {
        String ruleValue = rule.Rule_Value__c;

        switch on rule.Rule_Type__c {
            when 'User' {
                return matchesDelimitedList(ruleValue, String.valueOf(ctx.userId));
            }
            when 'Profile' {
                return matchesDelimitedList(ruleValue, String.valueOf(ctx.profileId));
            }
            when 'Permission_Set' {
                if (ctx.permissionSetNames == null || ctx.permissionSetNames.isEmpty()) {
                    return false;
                }
                List<String> requiredSets = ruleValue.split(';');
                for (String ps : requiredSets) {
                    if (ctx.permissionSetNames.contains(ps.trim())) {
                        return true;
                    }
                }
                return false;
            }
            when 'Percentage' {
                Integer threshold = Integer.valueOf(ruleValue.trim());
                Integer percentile = FeatureFlagHash.getHashedPercentile(ctx.userId, flagKey);
                return percentile < threshold;
            }
            when 'Segment' {
                return matchesSegment(ruleValue, ctx.customAttributes);
            }
            when 'Custom_Field' {
                return matchesCustomField(ruleValue, ctx.customAttributes);
            }
            when 'Account' {
                if (ctx.accountId == null) {
                    return false;
                }
                List<String> targetIds = ruleValue.split(';');
                for (String tid : targetIds) {
                    if (tid.trim().equalsIgnoreCase(String.valueOf(ctx.accountId))) {
                        return true;
                    }
                }
                return false;
            }
            when 'Account_Segment' {
                if (ctx.accountRecord == null || String.isBlank(ruleValue)) {
                    return false;
                }
                // Rule_Value__c format: "FieldApiName:Value"
                List<String> parts = ruleValue.split(':');
                if (parts.size() != 2) {
                    return false;
                }
                String fieldName = parts[0].trim();
                String expectedValue = parts[1].trim();
                Object actualValue = ctx.accountRecord.get(fieldName);
                return actualValue != null && String.valueOf(actualValue) == expectedValue;
            }
            when 'Territory' {
                if (ctx.territoryIds.isEmpty()) {
                    return false;
                }
                List<String> targetTerritories = ruleValue.split(';');
                for (String tid : targetTerritories) {
                    if (ctx.territoryIds.contains(tid.trim())) {
                        return true;
                    }
                }
                return false;
            }
            when else {
                return false;
            }
        }
    }

    private static Boolean matchesDelimitedList(String ruleValue, String target) {
        if (String.isBlank(ruleValue) || String.isBlank(target)) {
            return false;
        }
        List<String> values = ruleValue.split(';');
        for (String v : values) {
            if (v.trim().equalsIgnoreCase(target)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Segment matching: Rule_Value__c is a JSON object of
     *              required key-value pairs. ALL pairs must match the context attributes.
     *              Example rule value: {"region":"US","tier":"Enterprise"}
     * @param ruleValue   JSON string of required attribute pairs
     * @param attributes  Context attributes to match against
     * @return            True if all segment conditions match
     */
    private static Boolean matchesSegment(String ruleValue, Map<String, Object> attributes) {
        if (String.isBlank(ruleValue) || attributes == null || attributes.isEmpty()) {
            return false;
        }
        try {
            Map<String, Object> required = (Map<String, Object>) JSON.deserializeUntyped(ruleValue);
            for (String key : required.keySet()) {
                if (!attributes.containsKey(key)) {
                    return false;
                }
                if (String.valueOf(attributes.get(key)) != String.valueOf(required.get(key))) {
                    return false;
                }
            }
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Custom field matching: Rule_Value__c is a JSON object with
     *              a "field" key and "value" key. Matches if the context attribute
     *              with that field name equals the expected value.
     *              Example: {"field":"account_type","value":"Partner"}
     * @param ruleValue   JSON string with field and value keys
     * @param attributes  Context attributes to match against
     * @return            True if the custom field matches
     */
    private static Boolean matchesCustomField(String ruleValue, Map<String, Object> attributes) {
        if (String.isBlank(ruleValue) || attributes == null) {
            return false;
        }
        try {
            Map<String, Object> rule = (Map<String, Object>) JSON.deserializeUntyped(ruleValue);
            String fieldName  = String.valueOf(rule.get('field'));
            String expected   = String.valueOf(rule.get('value'));
            if (!attributes.containsKey(fieldName)) {
                return false;
            }
            return String.valueOf(attributes.get(fieldName)) == expected;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isRuleScheduleActive(FlipSwitch_Rule__c rule) {
        Datetime now = Datetime.now();
        if (rule.Start_Date__c != null && now < rule.Start_Date__c) {
            return false;
        }
        if (rule.End_Date__c != null && now > rule.End_Date__c) {
            return false;
        }
        return true;
    }

    // ─── Registry flag evaluation ─────────────────────────────────────────

    /**
     * @description Evaluate a code-defined flag from the runtime registry.
     *              Mirrors the CMDT evaluation path: emergency disable → expiration → rules → default.
     * @param regFlag        The registry flag record
     * @param flagKey        The flag DeveloperName
     * @param ctx            Evaluation context
     * @param preloadedRules Optional pre-loaded rules
     * @return               FeatureFlagResult
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static FeatureFlagResult evaluateRegistryFlag(
        FlipSwitch_Flag_Registry__c regFlag,
        String flagKey,
        FeatureFlagContext ctx,
        List<FlipSwitch_Rule__c> preloadedRules
    ) {
        if (!regFlag.Is_Active__c) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_NOT_CONFIGURED);
        }

        if (regFlag.Expiration_Date__c != null && regFlag.Expiration_Date__c < Date.today()) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_EXPIRED);
        }

        return evaluateWithRules(flagKey, ctx, preloadedRules, regFlag.Default_Value__c);
    }

    // ─── Shared evaluation helpers ────────────────────────────────────────

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static FeatureFlagResult evaluateWithRules(
        String flagKey,
        FeatureFlagContext ctx,
        List<FlipSwitch_Rule__c> preloadedRules,
        String defaultValue
    ) {
        FeatureFlagResult qaResult = checkQAOverride(ctx, defaultValue);
        if (qaResult != null) {
            return qaResult;
        }

        List<FlipSwitch_Rule__c> rules = preloadedRules != null
            ? filterRulesForFlag(preloadedRules, flagKey)
            : loadRules(flagKey);

        return evaluateTargetingRules(rules, ctx, flagKey, defaultValue);
    }

    private static FeatureFlagResult checkQAOverride(FeatureFlagContext ctx, String defaultValue) {
        FlipSwitch_Settings__c settings = FlipSwitch_Settings__c.getInstance(ctx.userId);
        if (settings != null && String.isNotBlank(settings.Override_All_Flags__c)) {
            if (settings.Override_All_Flags__c == 'Enable_All') {
                return FeatureFlagResult.enabled(defaultValue, null, FeatureFlagResult.REASON_QA_OVERRIDE);
            }
            if (settings.Override_All_Flags__c == 'Disable_All') {
                return FeatureFlagResult.disabled(FeatureFlagResult.REASON_QA_OVERRIDE);
            }
        }
        return null;
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static FeatureFlagResult evaluateTargetingRules(
        List<FlipSwitch_Rule__c> rules,
        FeatureFlagContext ctx,
        String flagKey,
        String defaultValue
    ) {
        for (FlipSwitch_Rule__c rule : rules) {
            if (rule.Is_Active__c && rule.Rule_Type__c == 'Emergency_Disable' && isRuleScheduleActive(rule)) {
                return FeatureFlagResult.disabled(FeatureFlagResult.REASON_EMERGENCY_DISABLE);
            }
        }

        for (FlipSwitch_Rule__c rule : rules) {
            if (!rule.Is_Active__c || rule.Rule_Type__c == 'Emergency_Disable') {
                continue;
            }
            if (!isRuleScheduleActive(rule)) {
                continue;
            }
            if (ruleMatches(rule, ctx, flagKey)) {
                String variant = String.isNotBlank(rule.Variant_Value__c)
                    ? rule.Variant_Value__c
                    : defaultValue;
                return FeatureFlagResult.enabled(variant, null, FeatureFlagResult.REASON_RULE_MATCH);
            }
        }

        return FeatureFlagResult.fromDefault(defaultValue);
    }

    // ─── Data loading ─────────────────────────────────────────────────────

    private static FlipSwitch_Flag__mdt loadFlag(String flagKey) {
        List<FlipSwitch_Flag__mdt> flags = [
            SELECT DeveloperName, Type__c, Default_Value__c, Is_Active__c,
                   Expiration_Date__c, Category__c, Description__c
            FROM FlipSwitch_Flag__mdt
            WHERE DeveloperName = :flagKey
            LIMIT 1
        ];
        return flags.isEmpty() ? null : flags[0];
    }

    /**
     * @description Load active rules for a single flag, ordered by Priority__c.
     * @param flagKey  The flag DeveloperName
     * @return         List of targeting rules sorted by priority
     */
    public static List<FlipSwitch_Rule__c> loadRules(String flagKey) {
        return [
            SELECT Flag_Key__c, Rule_Type__c, Rule_Value__c,
                   Variant_Value__c, Priority__c, Is_Active__c,
                   Start_Date__c, End_Date__c
            FROM FlipSwitch_Rule__c
            WHERE Flag_Key__c = :flagKey
            ORDER BY Priority__c ASC NULLS LAST
        ];
    }

    /**
     * @description Load active rules for a set of flags in a single SOQL query.
     *              Used by FeatureFlagBatchBuilder.
     * @param flagKeys  Set of flag DeveloperNames
     * @return          List of targeting rules for all requested flags
     */
    public static List<FlipSwitch_Rule__c> loadRulesForFlags(Set<String> flagKeys) {
        return [
            SELECT Flag_Key__c, Rule_Type__c, Rule_Value__c,
                   Variant_Value__c, Priority__c, Is_Active__c,
                   Start_Date__c, End_Date__c
            FROM FlipSwitch_Rule__c
            WHERE Flag_Key__c IN :flagKeys
            ORDER BY Flag_Key__c, Priority__c ASC NULLS LAST
        ];
    }

    private static List<FlipSwitch_Rule__c> filterRulesForFlag(
        List<FlipSwitch_Rule__c> allRules,
        String flagKey
    ) {
        List<FlipSwitch_Rule__c> filtered = new List<FlipSwitch_Rule__c>();
        for (FlipSwitch_Rule__c rule : allRules) {
            if (rule.Flag_Key__c == flagKey) {
                filtered.add(rule);
            }
        }
        return filtered;
    }
}
