/**
 * @description Internal evaluation context built by FeatureFlagBuilder.
 *              Captures everything needed to evaluate targeting rules:
 *              user identity, profile, permission sets, and custom attributes.
 *
 *              Consumers never instantiate this directly — it is built
 *              automatically by the builder chain.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public inherited sharing class FeatureFlagContext {

    /** @description The target user Id for evaluation. */
    public Id userId             { get; private set; }
    /** @description The user's profile Id. */
    public Id profileId          { get; private set; }
    /** @description Active permission set names for the user. */
    public Set<String> permissionSetNames { get; private set; }
    /** @description Custom key-value attributes for segment/custom field matching. */
    public Map<String, Object> customAttributes { get; private set; }
    /** @description Business scenario tag for logging. */
    public String scenario       { get; private set; }
    /** @description The flag key being evaluated. */
    public String flagKey        { get; private set; }
    /** @description Whether DML is permitted during this evaluation (required for Inventory flags). */
    public Boolean dmlAllowed    { get; set; }

    /** @description Account Id for account-level targeting rules. */
    public Id accountId { get; set; }

    private SObject cachedAccountRecord;
    /** @description Lazy-loaded Account record (Id, Industry, Type, AnnualRevenue, Name). Cached after first access. */
    public SObject accountRecord {
        get {
            if (cachedAccountRecord == null && accountId != null) {
                List<Account> rows = [
                    SELECT Id, Industry, Type, AnnualRevenue, Name FROM Account WHERE Id = :accountId LIMIT 1
                ];
                cachedAccountRecord = rows.isEmpty() ? null : rows[0];
            }
            return cachedAccountRecord;
        }
    }

    // Territory targeting (lazy-loaded, cached)
    private List<String> cachedTerritoryIds;

    /**
     * @description Inject territory IDs directly for test scenarios where
     *              UserTerritory2Association cannot be inserted.
     * @param ids  List of Territory2 Id strings to treat as the user's territories
     */
    @TestVisible
    private void setTerritoryIds(List<String> ids) {
        this.cachedTerritoryIds = ids;
    }

    /** @description Territory2 Ids for the context user. Lazy-loaded and cached. Empty when Territory Management is not enabled. */
    public List<String> territoryIds {
        get {
            if (cachedTerritoryIds == null) {
                cachedTerritoryIds = new List<String>();
                if (Schema.getGlobalDescribe().containsKey('UserTerritory2Association')) {
                    List<SObject> assocs = Database.query(
                        'SELECT Territory2Id FROM UserTerritory2Association WHERE UserId = :userId AND IsActive = true'
                    );
                    for (SObject assoc : assocs) {
                        cachedTerritoryIds.add(String.valueOf(assoc.get('Territory2Id')));
                    }
                }
            }
            return cachedTerritoryIds;
        }
    }

    private FeatureFlagContext() {
        this.permissionSetNames = new Set<String>();
        this.customAttributes   = new Map<String, Object>();
    }

    /**
     * @description Build a minimal context for a specific user (no SOQL).
     *              Intended for test scenarios that need direct property access.
     * @param userId  The target user Id
     */
    @TestVisible
    private FeatureFlagContext(Id userId) {
        this.userId             = userId;
        this.permissionSetNames = new Set<String>();
        this.customAttributes   = new Map<String, Object>();
    }

    /**
     * @description Build context for the running user.
     * @return  FeatureFlagContext for the current user
     */
    public static FeatureFlagContext forRunningUser() {
        return forUser(UserInfo.getUserId());
    }

    /**
     * @description Build context for a specific user.
     *              Queries profile and active permission set assignments.
     * @param userId  The target user Id
     * @return        FeatureFlagContext populated with user data
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

    /**
     * @description Add or overwrite a custom context attribute.
     * @param key    Attribute name
     * @param value  Attribute value
     * @return       This context instance for chaining
     */
    public FeatureFlagContext withAttribute(String key, Object value) {
        this.customAttributes.put(key, value);
        return this;
    }

    /**
     * @description Merge a map of attributes.
     * @param attrs  Map of attribute key-value pairs
     * @return       This context instance for chaining
     */
    public FeatureFlagContext withAttributes(Map<String, Object> attrs) {
        this.customAttributes.putAll(attrs);
        return this;
    }

    /**
     * @description Set the business scenario tag.
     * @param scenario  Scenario name for logging
     * @return          This context instance for chaining
     */
    public FeatureFlagContext withScenario(String scenario) {
        this.scenario = scenario;
        return this;
    }

    /**
     * @description Set the flag key being evaluated.
     * @param flagKey  The flag DeveloperName
     * @return         This context instance for chaining
     */
    public FeatureFlagContext withFlagKey(String flagKey) {
        this.flagKey = flagKey;
        return this;
    }
}
