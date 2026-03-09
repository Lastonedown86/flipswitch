/**
 * @description Internal evaluation context built by FeatureFlagBuilder.
 *              Captures everything needed to evaluate targeting rules:
 *              user identity, profile, permission sets, and custom attributes.
 *
 *              Consumers never instantiate this directly — it is built
 *              automatically by the builder chain.
 */
public class FeatureFlagContext {

    public Id userId             { get; private set; }
    public Id profileId          { get; private set; }
    public Set<String> permissionSetNames { get; private set; }
    public Map<String, Object> customAttributes { get; private set; }
    public String scenario       { get; private set; }
    public String flagKey        { get; private set; }

    private FeatureFlagContext() {
        this.permissionSetNames = new Set<String>();
        this.customAttributes   = new Map<String, Object>();
    }

    /**
     * @description Build context for the running user.
     */
    public static FeatureFlagContext forRunningUser() {
        return forUser(UserInfo.getUserId());
    }

    /**
     * @description Build context for a specific user.
     *              Queries profile and active permission set assignments.
     */
    public static FeatureFlagContext forUser(Id userId) {
        FeatureFlagContext ctx = new FeatureFlagContext();
        ctx.userId = userId;

        List<User> users = [
            SELECT ProfileId, Profile.Name
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];

        if (!users.isEmpty()) {
            ctx.profileId = users[0].ProfileId;
        }

        List<PermissionSetAssignment> psas = [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
              AND PermissionSet.IsOwnedByProfile = FALSE
        ];

        for (PermissionSetAssignment psa : psas) {
            ctx.permissionSetNames.add(psa.PermissionSet.Name);
        }

        return ctx;
    }

    /** @description Add or overwrite a custom context attribute. */
    public FeatureFlagContext withAttribute(String key, Object value) {
        this.customAttributes.put(key, value);
        return this;
    }

    /** @description Merge a map of attributes. */
    public FeatureFlagContext withAttributes(Map<String, Object> attrs) {
        this.customAttributes.putAll(attrs);
        return this;
    }

    /** @description Set the business scenario tag. */
    public FeatureFlagContext withScenario(String scenario) {
        this.scenario = scenario;
        return this;
    }

    /** @description Set the flag key being evaluated. */
    public FeatureFlagContext withFlagKey(String flagKey) {
        this.flagKey = flagKey;
        return this;
    }
}
