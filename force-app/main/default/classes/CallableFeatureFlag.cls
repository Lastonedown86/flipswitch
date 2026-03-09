/**
 * @description System.Callable adapter for FlipSwitch.
 *
 *              Allows ISVs and managed packages to use feature flags
 *              without a hard compile-time dependency on FlipSwitch.
 *              Follows the same pattern as NebulaLogger's CallableLogger.
 *
 *              Usage from a package with no dependency:
 *              Type t = Type.forName('CallableFeatureFlag');
 *              if (t != null) {
 *                  System.Callable ff = (System.Callable) t.newInstance();
 *                  Boolean enabled = (Boolean) ff.call('isEnabled', new Map<String,Object>{
 *                      'flagKey' => 'MY_FLAG'
 *                  });
 *              }
 *
 *              Supported actions:
 *              - 'isEnabled'    { flagKey }                  → Boolean
 *              - 'getVariant'   { flagKey }                  → String
 *              - 'evaluate'     { flagKey, userId }          → Map (isEnabled, variant, reason)
 *              - 'setScenario'  { scenario }                 → null
 *              - 'flushLogs'    {}                           → null
 */
public class CallableFeatureFlag implements System.Callable {

    public Object call(String action, Map<String, Object> args) {
        switch on action.toLowerCase() {
            when 'isenabled' {
                String flagKey = (String) args.get('flagKey');
                Id userId = args.containsKey('userId')
                    ? (Id) args.get('userId')
                    : null;
                FeatureFlagBuilder builder = FeatureFlag.flag(flagKey);
                if (userId != null) {
                    builder.forUser(userId);
                }
                return builder.isEnabled();
            }
            when 'getvariant' {
                String flagKey = (String) args.get('flagKey');
                Id userId = args.containsKey('userId')
                    ? (Id) args.get('userId')
                    : null;
                FeatureFlagBuilder builder = FeatureFlag.flag(flagKey);
                if (userId != null) {
                    builder.forUser(userId);
                }
                return builder.getVariant();
            }
            when 'evaluate' {
                String flagKey = (String) args.get('flagKey');
                Id userId = args.containsKey('userId')
                    ? (Id) args.get('userId')
                    : null;
                FeatureFlagBuilder builder = FeatureFlag.flag(flagKey);
                if (userId != null) {
                    builder.forUser(userId);
                }
                FeatureFlagResult result = builder.evaluate();
                return new Map<String, Object>{
                    'isEnabled' => result.isEnabled,
                    'variant'   => result.variant,
                    'reason'    => result.reason,
                    'payload'   => result.payload
                };
            }
            when 'setscenario' {
                String scenario = (String) args.get('scenario');
                FeatureFlag.setScenario(scenario);
                return null;
            }
            when 'flushlogs' {
                FeatureFlag.flushEvaluations();
                return null;
            }
            when else {
                throw new FeatureFlagException(
                    'CallableFeatureFlag: unknown action "' + action + '"'
                );
            }
        }
    }
}
