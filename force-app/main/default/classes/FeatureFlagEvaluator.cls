/**
 * @description Core evaluation engine for FlipSwitch.
 *
 *              Evaluation order (highest to lowest priority):
 *              1. Kill switch — Is_Active__c = false on CMDT
 *              2. Expiration  — Expiration_Date__c < TODAY
 *              3. QA override — Feature_Flag_Settings__c.Override_All_Flags__c
 *              4. Kill switch rule — Rule_Type__c = Kill_Switch
 *              5. Targeting rules by Priority__c ASC:
 *                 User → Profile → Permission_Set → Segment → Custom_Field → Percentage
 *              6. Default value from CMDT
 *
 *              All exceptions are caught by the circuit breaker; callers
 *              always receive a safe default result, never an exception.
 */
public inherited sharing class FeatureFlagEvaluator {

    /**
     * @description Evaluate a single flag for the given context.
     *              Pre-loaded rules (from batch builder) can be passed to
     *              avoid an extra SOQL query.
     *
     * @param flagKey       The Feature_Flag__mdt DeveloperName
     * @param ctx           Evaluation context (user, attributes, etc.)
     * @param preloadedRules Optional pre-loaded rules (null triggers a fresh query)
     * @return              FeatureFlagResult — never null, never throws
     */
    public static FeatureFlagResult evaluate(
        String flagKey,
        FeatureFlagContext ctx,
        List<Feature_Flag_Rule__c> preloadedRules
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
        List<Feature_Flag_Rule__c> preloadedRules
    ) {
        // 1. Load flag definition from CMDT
        Feature_Flag__mdt flag = loadFlag(flagKey);
        if (flag == null) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_ERROR);
        }

        // 2. Kill switch — CMDT Is_Active__c = false
        if (!flag.Is_Active__c) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_KILL_SWITCH);
        }

        // 3. Expiration check
        if (flag.Expiration_Date__c != null && flag.Expiration_Date__c < Date.today()) {
            return FeatureFlagResult.disabled(FeatureFlagResult.REASON_EXPIRED);
        }

        // 4. QA override from hierarchy custom settings
        Feature_Flag_Settings__c settings = Feature_Flag_Settings__c.getInstance(ctx.userId);
        if (settings != null && String.isNotBlank(settings.Override_All_Flags__c)) {
            if (settings.Override_All_Flags__c == 'Enable_All') {
                return FeatureFlagResult.enabled(flag.Default_Value__c, null, FeatureFlagResult.REASON_QA_OVERRIDE);
            }
            if (settings.Override_All_Flags__c == 'Disable_All') {
                return FeatureFlagResult.disabled(FeatureFlagResult.REASON_QA_OVERRIDE);
            }
        }

        // 5. Load targeting rules (or use pre-loaded set from batch builder)
        List<Feature_Flag_Rule__c> rules = preloadedRules != null
            ? filterRulesForFlag(preloadedRules, flagKey)
            : loadRules(flagKey);

        // 6. Kill switch rule (checked before other targeting rules)
        for (Feature_Flag_Rule__c rule : rules) {
            if (rule.Is_Active__c && rule.Rule_Type__c == 'Kill_Switch' && isRuleScheduleActive(rule)) {
                return FeatureFlagResult.disabled(FeatureFlagResult.REASON_KILL_SWITCH);
            }
        }

        // 7. Evaluate targeting rules in Priority__c order
        for (Feature_Flag_Rule__c rule : rules) {
            if (!rule.Is_Active__c || rule.Rule_Type__c == 'Kill_Switch') {
                continue;
            }
            if (!isRuleScheduleActive(rule)) {
                continue;
            }
            if (ruleMatches(rule, ctx, flagKey)) {
                String variant = String.isNotBlank(rule.Variant_Value__c)
                    ? rule.Variant_Value__c
                    : flag.Default_Value__c;
                return FeatureFlagResult.enabled(variant, null, FeatureFlagResult.REASON_RULE_MATCH);
            }
        }

        // 8. Fall through to CMDT default
        return FeatureFlagResult.fromDefault(flag.Default_Value__c);
    }

    // ─── Rule matching ────────────────────────────────────────────────────

    private static Boolean ruleMatches(
        Feature_Flag_Rule__c rule,
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

    private static Boolean isRuleScheduleActive(Feature_Flag_Rule__c rule) {
        Datetime now = Datetime.now();
        if (rule.Start_Date__c != null && now < rule.Start_Date__c) {
            return false;
        }
        if (rule.End_Date__c != null && now > rule.End_Date__c) {
            return false;
        }
        return true;
    }

    // ─── Data loading ─────────────────────────────────────────────────────

    private static Feature_Flag__mdt loadFlag(String flagKey) {
        List<Feature_Flag__mdt> flags = [
            SELECT DeveloperName, Type__c, Default_Value__c, Is_Active__c,
                   Expiration_Date__c, Category__c, Description__c
            FROM Feature_Flag__mdt
            WHERE DeveloperName = :flagKey
            LIMIT 1
        ];
        return flags.isEmpty() ? null : flags[0];
    }

    /**
     * @description Load active rules for a single flag, ordered by Priority__c.
     */
    public static List<Feature_Flag_Rule__c> loadRules(String flagKey) {
        return [
            SELECT Feature_Flag_Key__c, Rule_Type__c, Rule_Value__c,
                   Variant_Value__c, Priority__c, Is_Active__c,
                   Start_Date__c, End_Date__c
            FROM Feature_Flag_Rule__c
            WHERE Feature_Flag_Key__c = :flagKey
            ORDER BY Priority__c ASC NULLS LAST
        ];
    }

    /**
     * @description Load active rules for a set of flags in a single SOQL query.
     *              Used by FeatureFlagBatchBuilder.
     */
    public static List<Feature_Flag_Rule__c> loadRulesForFlags(Set<String> flagKeys) {
        return [
            SELECT Feature_Flag_Key__c, Rule_Type__c, Rule_Value__c,
                   Variant_Value__c, Priority__c, Is_Active__c,
                   Start_Date__c, End_Date__c
            FROM Feature_Flag_Rule__c
            WHERE Feature_Flag_Key__c IN :flagKeys
            ORDER BY Feature_Flag_Key__c, Priority__c ASC NULLS LAST
        ];
    }

    private static List<Feature_Flag_Rule__c> filterRulesForFlag(
        List<Feature_Flag_Rule__c> allRules,
        String flagKey
    ) {
        List<Feature_Flag_Rule__c> filtered = new List<Feature_Flag_Rule__c>();
        for (Feature_Flag_Rule__c rule : allRules) {
            if (rule.Feature_Flag_Key__c == flagKey) {
                filtered.add(rule);
            }
        }
        return filtered;
    }
}
