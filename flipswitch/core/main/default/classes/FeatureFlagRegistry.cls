/**
 * @description Runtime registry for code-defined feature flags.
 *
 *              When Apex code evaluates a flag key that has no FlipSwitch_Flag__mdt
 *              definition, the registry auto-creates a FlipSwitch_Flag_Registry__c
 *              record so the admin dashboard discovers it immediately.
 *
 *              Registration is:
 *              - Synchronous — the record exists in the same transaction
 *              - Deduplicated — each flag key is processed at most once per transaction
 *              - Idempotent — upserts on Flag_Key__c (External ID) for concurrency safety
 *              - Safe — registration failures are swallowed; evaluation always proceeds
 *
 *              Usage:
 *              // Auto-register (called by the evaluator):
 *              FeatureFlagRegistry.registerIfNew('MY_FLAG');
 *
 *              // Rich registration (called by the define builder):
 *              FeatureFlagRegistry.registerWithMetadata('MY_FLAG', 'Boolean', 'false', 'UI', 'Dark mode toggle');
 *
 *              // Query:
 *              FlipSwitch_Flag_Registry__c reg = FeatureFlagRegistry.getRegistryFlag('MY_FLAG');
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public inherited sharing class FeatureFlagRegistry {

    /** Transaction-scoped dedup set — prevents duplicate DML within a single transaction. */
    @SuppressWarnings('PMD.FieldNamingConventions, PMD.VariableNamingConventions')
    private static final Set<String> processedThisTransaction = new Set<String>();

    /** Lazy-loaded cache of all registry records keyed by Flag_Key__c. */
    private static Map<String, FlipSwitch_Flag_Registry__c> registryCache;

    /** Lazy-loaded set of CMDT flag DeveloperNames. */
    private static Set<String> cmdtFlagKeys;

    // ─── Registration API ─────────────────────────────────────────────────

    /**
     * @description Register a flag key with minimal defaults if it does not already exist
     *              in CMDT or the registry. Called automatically by the evaluator.
     * @param flagKey  The flag DeveloperName to register
     */
    public static void registerIfNew(String flagKey) {
        if (String.isBlank(flagKey) || processedThisTransaction.contains(flagKey)) {
            return;
        }
        processedThisTransaction.add(flagKey);

        // Skip if the flag already exists in CMDT
        if (getCmdtFlagKeys().contains(flagKey)) {
            return;
        }

        // Skip if already in the registry
        if (getRegistryCache().containsKey(flagKey)) {
            return;
        }

        // Create new registry record with safe defaults
        FlipSwitch_Flag_Registry__c reg = new FlipSwitch_Flag_Registry__c(
            Name               = flagKey.left(80),
            Flag_Key__c        = flagKey,
            Type__c            = 'Boolean',
            Default_Value__c   = 'false',
            Is_Active__c       = false,
            Source__c           = 'Code',
            First_Seen_Date__c = Datetime.now()
        );

        doUpsert(reg);
    }

    /**
     * @description Register a flag key with developer-supplied metadata.
     *              Called by the FeatureFlagDefinition builder. Follows a
     *              fill-not-overwrite strategy: only populates fields that
     *              are currently null/blank on an existing record, so admin
     *              edits are never clobbered.
     *
     * @param flagKey       Unique flag identifier
     * @param type          Boolean | Variant | Percentage (null = keep existing or default to Boolean)
     * @param defaultValue  Default evaluation result (null = keep existing or default to 'false')
     * @param category      Dashboard grouping label (null = keep existing)
     * @param description   Purpose and owner (null = keep existing)
     * @param expirationDate Auto-disable after this date (null = keep existing)
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void registerWithMetadata(
        String flagKey,
        String type,
        String defaultValue,
        String category,
        String description,
        Date expirationDate
    ) {
        if (String.isBlank(flagKey) || processedThisTransaction.contains(flagKey)) {
            return;
        }
        processedThisTransaction.add(flagKey);

        // Skip if the flag already exists in CMDT
        if (getCmdtFlagKeys().contains(flagKey)) {
            return;
        }

        FlipSwitch_Flag_Registry__c existing = getRegistryCache().get(flagKey);

        if (existing != null) {
            fillExistingRecord(existing, type, defaultValue, category, description, expirationDate);
            return;
        }

        // New registration with full metadata
        FlipSwitch_Flag_Registry__c reg = new FlipSwitch_Flag_Registry__c(
            Name                = flagKey.left(80),
            Flag_Key__c         = flagKey,
            Type__c             = String.isNotBlank(type) ? type : 'Boolean',
            Default_Value__c    = String.isNotBlank(defaultValue) ? defaultValue : 'false',
            Is_Active__c        = false,
            Category__c         = category,
            Description__c      = description,
            Expiration_Date__c  = expirationDate,
            Source__c            = 'Code',
            First_Seen_Date__c  = Datetime.now()
        );

        doUpsert(reg);
    }

    /**
     * @description Fill-not-overwrite: populate only null/blank fields on an existing record.
     * @param existing       The existing registry record to update
     * @param type           Flag type
     * @param defaultValue   Default value
     * @param category       Category
     * @param description    Description
     * @param expirationDate Expiration date
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static void fillExistingRecord(
        FlipSwitch_Flag_Registry__c existing,
        String type,
        String defaultValue,
        String category,
        String description,
        Date expirationDate
    ) {
        Boolean needsUpdate = false;
        needsUpdate = fillIfBlank(existing, 'Type__c', type) || needsUpdate;
        needsUpdate = fillIfBlank(existing, 'Default_Value__c', defaultValue) || needsUpdate;
        needsUpdate = fillIfBlank(existing, 'Category__c', category) || needsUpdate;
        needsUpdate = fillIfBlank(existing, 'Description__c', description) || needsUpdate;
        if (expirationDate != null && existing.Expiration_Date__c == null) {
            existing.Expiration_Date__c = expirationDate;
            needsUpdate = true;
        }
        if (needsUpdate) {
            doUpsert(existing);
        }
    }

    /**
     * @description Fill a string field only if the current value is blank and the new value is not.
     * @param rec        Registry record to update
     * @param fieldName  API name of the field
     * @param newValue   New value to set
     * @return True if the field was updated
     */
    private static Boolean fillIfBlank(FlipSwitch_Flag_Registry__c rec, String fieldName, String newValue) {
        if (String.isBlank(newValue)) {
            return false;
        }
        String currentValue = (String) rec.get(fieldName);
        if (String.isBlank(currentValue)) {
            rec.put(fieldName, newValue);
            return true;
        }
        return false;
    }

    // ─── Query API ────────────────────────────────────────────────────────

    /**
     * @description Get a single registry flag by key. Returns null if not found.
     * @param flagKey  The flag DeveloperName
     * @return         Registry record or null
     */
    public static FlipSwitch_Flag_Registry__c getRegistryFlag(String flagKey) {
        return getRegistryCache().get(flagKey);
    }

    /**
     * @description Get registry flags for a set of keys. Only returns keys that exist.
     * @param flagKeys  Set of flag DeveloperNames
     * @return          Map of flagKey → registry record
     */
    public static Map<String, FlipSwitch_Flag_Registry__c> getRegistryFlags(Set<String> flagKeys) {
        Map<String, FlipSwitch_Flag_Registry__c> result = new Map<String, FlipSwitch_Flag_Registry__c>();
        Map<String, FlipSwitch_Flag_Registry__c> cache = getRegistryCache();
        for (String key : flagKeys) {
            if (cache.containsKey(key)) {
                result.put(key, cache.get(key));
            }
        }
        return result;
    }

    /**
     * @description Get all registry flags. Used by the admin dashboard to merge
     *              with CMDT flag definitions.
     * @return  List of all FlipSwitch_Flag_Registry__c records
     */
    public static List<FlipSwitch_Flag_Registry__c> getAllRegistryFlags() {
        return getRegistryCache().values();
    }

    // ─── Promotion API ────────────────────────────────────────────────────

    /**
     * @description Mark a registry flag as promoted. Called when the admin confirms
     *              a CMDT definition has been deployed for this flag key.
     * @param flagKey  The flag DeveloperName to promote
     */
    public static void promoteFlag(String flagKey) {
        FlipSwitch_Flag_Registry__c reg = getRegistryCache().get(flagKey);
        if (reg != null && !reg.Is_Promoted__c) {
            reg.Is_Promoted__c = true;
            doUpsert(reg);
        }
    }

    /**
     * @description Clear the registry cache. Call after modifying registry records
     *              outside of this class (e.g., admin controller CRUD).
     */
    public static void clearCache() {
        registryCache = null;
    }

    // ─── Internal helpers ─────────────────────────────────────────────────

    private static Map<String, FlipSwitch_Flag_Registry__c> getRegistryCache() {
        if (registryCache == null) {
            registryCache = new Map<String, FlipSwitch_Flag_Registry__c>();
            for (FlipSwitch_Flag_Registry__c reg : [
                SELECT Id, Name, Flag_Key__c, Type__c, Default_Value__c,
                       Is_Active__c, Category__c, Description__c,
                       Expiration_Date__c, Source__c, First_Seen_Date__c,
                       First_Seen_Class__c, Last_Evaluated_Date__c, Is_Promoted__c
                FROM   FlipSwitch_Flag_Registry__c
                ORDER BY Flag_Key__c ASC
            ]) {
                registryCache.put(reg.Flag_Key__c, reg);
            }
        }
        return registryCache;
    }

    private static Set<String> getCmdtFlagKeys() {
        if (cmdtFlagKeys == null) {
            cmdtFlagKeys = new Set<String>();
            for (FlipSwitch_Flag__mdt f : [
                SELECT DeveloperName FROM FlipSwitch_Flag__mdt
            ]) {
                cmdtFlagKeys.add(f.DeveloperName);
            }
        }
        return cmdtFlagKeys;
    }

    private static void doUpsert(FlipSwitch_Flag_Registry__c reg) {
        try {
            Database.upsert(reg, FlipSwitch_Flag_Registry__c.Flag_Key__c, false);
            // Refresh cache entry
            if (registryCache != null) {
                registryCache.put(reg.Flag_Key__c, reg);
            }
        } catch (Exception e) { // NOPMD - EmptyCatchBlock: registration failures never break the caller
        }
    }
}
