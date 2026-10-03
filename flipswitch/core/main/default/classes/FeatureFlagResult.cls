/**
 * @description Immutable result wrapper returned by all FlipSwitch evaluation methods.
 *              Contains the evaluated value, variant key, reason for the result,
 *              and optional variant payload.
 */
public inherited sharing class FeatureFlagResult {

    /** Reason constants — why this result was returned */
    public static final String REASON_RULE_MATCH      = 'RULE_MATCH';
    public static final String REASON_DEFAULT         = 'DEFAULT';
    public static final String REASON_EMERGENCY_DISABLE = 'EMERGENCY_DISABLE';
    public static final String REASON_EXPIRED         = 'EXPIRED';
    public static final String REASON_CACHE_HIT       = 'CACHE_HIT';
    public static final String REASON_QA_OVERRIDE     = 'QA_OVERRIDE';
    public static final String REASON_ERROR           = 'ERROR';
    public static final String REASON_NOT_CONFIGURED  = 'NOT_CONFIGURED';

    /** @description Whether the flag evaluated to enabled. */
    public Boolean isEnabled { get; private set; }

    /** @description Variant key (e.g. 'control', 'treatment_a'). Null for boolean flags. */
    public String variant { get; private set; }

    /** @description Why this result was returned. */
    public String reason { get; private set; }

    /** @description Optional JSON payload for the matched variant. */
    public Map<String, Object> payload { get; private set; }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    private FeatureFlagResult() {
        // Private constructor — use factory methods enabled(), disabled(), fromDefault()
    }

    /**
     * @description Factory: flag is enabled, optionally with a variant and payload.
     * @param variant  Variant key or null for boolean flags
     * @param payload  Optional JSON payload map
     * @param reason   Evaluation reason constant
     * @return         Enabled FeatureFlagResult
     */
    public static FeatureFlagResult enabled(String variant, Map<String, Object> payload, String reason) {
        FeatureFlagResult r = new FeatureFlagResult();
        r.isEnabled = true;
        r.variant   = variant;
        r.payload   = payload;
        r.reason    = reason;
        return r;
    }

    /**
     * @description Factory: flag is disabled, falling back to default.
     * @param reason  Evaluation reason constant
     * @return        Disabled FeatureFlagResult
     */
    public static FeatureFlagResult disabled(String reason) {
        FeatureFlagResult r = new FeatureFlagResult();
        r.isEnabled = false;
        r.variant   = null;
        r.payload   = null;
        r.reason    = reason;
        return r;
    }

    /**
     * @description Factory: result from a safe default value when no rules matched.
     *              The default value string is parsed to determine isEnabled.
     * @param defaultValue  The CMDT/registry default value string
     * @return              FeatureFlagResult based on the default value
     */
    public static FeatureFlagResult fromDefault(String defaultValue) {
        FeatureFlagResult r = new FeatureFlagResult();
        r.isEnabled = (defaultValue != null && defaultValue.equalsIgnoreCase('true'));
        r.variant   = (defaultValue != null && !defaultValue.equalsIgnoreCase('true') &&
                       !defaultValue.equalsIgnoreCase('false')) ? defaultValue : null;
        r.payload   = null;
        r.reason    = REASON_DEFAULT;
        return r;
    }
}
