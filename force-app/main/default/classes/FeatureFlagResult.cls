/**
 * @description Immutable result wrapper returned by all FlipSwitch evaluation methods.
 *              Contains the evaluated value, variant key, reason for the result,
 *              and optional variant payload.
 */
public class FeatureFlagResult {

    /** Reason constants — why this result was returned */
    public static final String REASON_RULE_MATCH  = 'RULE_MATCH';
    public static final String REASON_DEFAULT     = 'DEFAULT';
    public static final String REASON_KILL_SWITCH = 'KILL_SWITCH';
    public static final String REASON_EXPIRED     = 'EXPIRED';
    public static final String REASON_CACHE_HIT   = 'CACHE_HIT';
    public static final String REASON_QA_OVERRIDE = 'QA_OVERRIDE';
    public static final String REASON_ERROR       = 'ERROR';

    /** Whether the flag evaluated to enabled */
    public Boolean isEnabled { get; private set; }

    /** Variant key (e.g. 'control', 'treatment_a'). Null for boolean flags. */
    public String variant { get; private set; }

    /** Why this result was returned */
    public String reason { get; private set; }

    /** Optional JSON payload for the matched variant */
    public Map<String, Object> payload { get; private set; }

    private FeatureFlagResult() {}

    /**
     * @description Factory: flag is enabled, optionally with a variant and payload.
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
