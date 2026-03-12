/**
 * @description Extensibility interface for post-evaluation hooks.
 *              Implement and register via Feature_Flag_Plugin__mdt to run
 *              custom logic after every flag evaluation (e.g. external analytics,
 *              audit logging, Slack alerts on kill switch).
 *
 *              Available in unlocked package only.
 */
public interface FeatureFlagPlugin {
    /**
     * @description Called after each flag evaluation completes.
     * @param result  The evaluation result
     * @param ctx     The evaluation context (user, attributes, scenario)
     */
    void onEvaluate(FeatureFlagResult result, FeatureFlagContext ctx);
}
