/**
 * @description Invocable action for use in Salesforce Flows.
 *
 *              Appears in Flow Builder under the "Feature Flags" category.
 *              Supports both single evaluations and bulk collection inputs
 *              (e.g. Record-Triggered Flows processing 200 records at once).
 *
 *              Flow usage:
 *              1. Add an Action element to your Flow
 *              2. Search for "Evaluate Feature Flag"
 *              3. Set Flag Key (required) and User Id (optional)
 *              4. Use {!Is_Enabled} or {!Variant} outputs in a Decision element
 */
public class FeatureFlagFlowAction {

    /**
     * @description Input wrapper for Flow invocable variables.
     */
    public class FlowInput {
        @InvocableVariable(label='Flag Key' description='The DeveloperName of the Feature_Flag__mdt record' required=true)
        public String flagKey;

        @InvocableVariable(label='User Id' description='Salesforce User Id to evaluate for. Defaults to running user.')
        public String userId;
    }

    /**
     * @description Output wrapper for Flow invocable variables.
     */
    public class FlowOutput {
        @InvocableVariable(label='Is Enabled' description='True if the flag is enabled for this user')
        public Boolean isEnabled;

        @InvocableVariable(label='Variant' description='Variant key returned (e.g. control, treatment_a). Null for boolean flags.')
        public String variant;

        @InvocableVariable(label='Reason' description='Why this result was returned (RULE_MATCH, DEFAULT, KILL_SWITCH, etc.)')
        public String reason;
    }

    /**
     * @description Evaluate feature flags in bulk.
     *              Batch-evaluates all inputs using a single SOQL via FeatureFlagBatchBuilder
     *              to stay within governor limits for large collections.
     *
     * @param inputs  List of FlowInput (one per record in the triggering collection)
     * @return        List of FlowOutput in the same order as inputs
     */
    @InvocableMethod(
        label='Evaluate Feature Flag'
        description='Evaluates a FlipSwitch feature flag for a given user and returns whether it is enabled and the variant.'
        category='Feature Flags'
    )
    public static List<FlowOutput> evaluate(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();

        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }

        // Collect unique flag keys for batch loading
        Set<String> flagKeySet = new Set<String>();
        for (FlowInput input : inputs) {
            if (String.isNotBlank(input.flagKey)) {
                flagKeySet.add(input.flagKey);
            }
        }

        // Single SOQL: load all rules for all referenced flags
        List<Feature_Flag_Rule__c> allRules =
            FeatureFlagEvaluator.loadRulesForFlags(flagKeySet);

        for (FlowInput input : inputs) {
            FlowOutput output = new FlowOutput();

            if (String.isBlank(input.flagKey)) {
                output.isEnabled = false;
                output.reason    = FeatureFlagResult.REASON_ERROR;
                outputs.add(output);
                continue;
            }

            Id userId = String.isNotBlank(input.userId)
                ? (Id) input.userId
                : UserInfo.getUserId();

            FeatureFlagContext ctx = FeatureFlagContext.forUser(userId);
            ctx.withFlagKey(input.flagKey);

            FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
                input.flagKey, ctx, allRules
            );

            output.isEnabled = result.isEnabled;
            output.variant   = result.variant;
            output.reason    = result.reason;
            outputs.add(output);
        }

        return outputs;
    }
}
