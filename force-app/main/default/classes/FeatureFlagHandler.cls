/**
 * @description Callback interface for the conditional execution pattern.
 *              Implement this interface and pass to .whenEnabled() / .whenDisabled()
 *              on FeatureFlagBuilder, then call .execute() to run the appropriate handler.
 *
 * @example
 *   FeatureFlag.flag('NEW_CHECKOUT')
 *       .whenEnabled(new NewCheckoutHandler())
 *       .whenDisabled(new LegacyCheckoutHandler())
 *       .execute();
 */
public interface FeatureFlagHandler {
    void handle();
}
