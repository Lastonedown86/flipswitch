/**
 * @description AuraEnabled controller for the featureFlagAdmin LWC suite.
 *              Provides flag dashboard data, rule CRUD, emergency-disable toggling,
 *              evaluation preview, bulk operations, and aggregated analytics.
 *              Flag definitions (FlipSwitch_Flag__mdt) are read-only via SOQL;
 *              mutations are delegated to Metadata API via a @future callout.
 *              Runtime data (FlipSwitch_Rule__c, FlipSwitch_Metric__c, etc.)
 *              is managed with standard DML.
 * @author      FlipSwitch
 */
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.CyclomaticComplexity, PMD.StdCyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class FeatureFlagAdminController {

    // ─── Inner wrapper types ────────────────────────────────────────────────

    /** @description Lightweight flag summary for the dashboard list. */
    public class FlagSummary {
        /** @description Flag DeveloperName */ @AuraEnabled public String  developerName   { get; set; }
        /** @description Flag label */ @AuraEnabled public String  label           { get; set; }
        /** @description Flag description */ @AuraEnabled public String  description     { get; set; }
        /** @description Flag type (Boolean, Percentage, etc.) */ @AuraEnabled public String  type            { get; set; }
        /** @description Default value string */ @AuraEnabled public String  defaultValue    { get; set; }
        /** @description Whether the flag is active */ @AuraEnabled public Boolean isActive        { get; set; }
        /** @description Category for grouping */ @AuraEnabled public String  category        { get; set; }
        /** @description ISO expiration date string */ @AuraEnabled public String  expirationDate  { get; set; }
        /** @description Whether an emergency disable rule is active */ @AuraEnabled public Boolean isEmergencyDisabled  { get; set; }
        /** @description Whether the flag has expired */ @AuraEnabled public Boolean isExpired       { get; set; }
        /** @description Whether the flag expires within 7 days */ @AuraEnabled public Boolean isExpiringSoon  { get; set; }
        /** @description Percentage rollout value */ @AuraEnabled public Integer rolloutPercent  { get; set; }
        /** @description Variant keys for multi-variant flags */ @AuraEnabled public List<String> variantKeys { get; set; }
        /** @description Count of active targeting rules */ @AuraEnabled public Integer activeRuleCount { get; set; }
        /** @description Flag source (Deployed or Code) */ @AuraEnabled public String  source          { get; set; }
    }

    /** @description Full flag detail including all rules and variants. */
    public class FlagDetail {
        /** @description Flag summary */ @AuraEnabled public FlagSummary              summary  { get; set; }
        /** @description Targeting rules */ @AuraEnabled public List<FlipSwitch_Rule__c> rules    { get; set; }
        /** @description Variant definitions */ @AuraEnabled public List<FlipSwitch_Variant__c> variants { get; set; }
        /** @description Flag source */ @AuraEnabled public String                   source   { get; set; }
    }

    /** @description Result of a simulated evaluation (preview panel). */
    public class EvalPreviewResult {
        /** @description Whether the flag is enabled */ @AuraEnabled public Boolean isEnabled { get; set; }
        /** @description Variant key */ @AuraEnabled public String  variant   { get; set; }
        /** @description Evaluation reason */ @AuraEnabled public String  reason    { get; set; }
        /** @description JSON payload */ @AuraEnabled public String  payload   { get; set; }
    }

    /** @description Aggregated analytics for the analytics tab. */
    public class FlagAnalytics {
        /** @description Flag DeveloperName */ @AuraEnabled public String              flagKey           { get; set; }
        /** @description Total evaluation count */ @AuraEnabled public Integer             totalEvaluations  { get; set; }
        /** @description Unique users evaluated */ @AuraEnabled public Integer             uniqueUsers       { get; set; }
        /** @description Circuit breaker trip count */ @AuraEnabled public Integer             circuitBreakerTrips { get; set; }
        /** @description Per-variant statistics */ @AuraEnabled public List<VariantStat>   variantStats      { get; set; }
        /** @description Daily evaluation statistics */ @AuraEnabled public List<DailyStat>     dailyStats        { get; set; }
    }

    /** @description Per-variant statistics wrapper. */
    public class VariantStat {
        /** @description Variant key identifier */ @AuraEnabled public String  variantKey   { get; set; }
        /** @description Evaluation count for this variant */ @AuraEnabled public Integer count        { get; set; }
        /** @description Unique users for this variant */ @AuraEnabled public Integer uniqueUsers  { get; set; }
        /** @description Percentage of total evaluations */ @AuraEnabled public Decimal percentage   { get; set; }
    }

    /** @description Daily evaluation count for sparkline display. */
    public class DailyStat {
        /** @description ISO date string */ @AuraEnabled public String  evalDate { get; set; }
        /** @description Evaluation count for this date */ @AuraEnabled public Integer count    { get; set; }
    }

    /** Org-level health counts for the admin shell summary strip. */
    /** @description Org-level health counts for the admin shell summary strip. */
    public class OrgHealth {
        /** @description Count of active flags */ @AuraEnabled public Integer totalActive      { get; set; }
        /** @description Count of flags expiring within 7 days */ @AuraEnabled public Integer expiringSoon     { get; set; }
        /** @description Count of emergency-disabled flags */ @AuraEnabled public Integer emergencyDisabled { get; set; }
        /** @description Count of circuit breaker trips */ @AuraEnabled public Integer circuitBreakers  { get; set; }
    }

    // ─── Dashboard ───────────────────────────────────────────────────────────

    /**
     * @description Returns all flag summaries enriched with rule data.
     *              Applies optional category and status filters.
     * @param  category  Category__c value to filter on; null = all
     * @param  status    'active' | 'disabled' | 'expired' | 'emergencydisable' | null = all
     * @return           List<FlagSummary>
     */
    @SuppressWarnings('PMD.NcssMethodCount')
    @AuraEnabled(cacheable=true)
    public static List<FlagSummary> getFlags(String category, String status) {
        // Load all CMDT flag definitions
        List<FlipSwitch_Flag__mdt> flagMdts = [
            SELECT DeveloperName, Label, Description__c, Type__c,
                   Default_Value__c, Is_Active__c, Expiration_Date__c, Category__c
            FROM   FlipSwitch_Flag__mdt
            WITH   SECURITY_ENFORCED
            ORDER BY Label ASC
        ];

        // Collect CMDT flag keys for rule/variant queries and registry dedup
        Set<String> flagKeys = new Set<String>();
        for (FlipSwitch_Flag__mdt f : flagMdts) {
            flagKeys.add(f.DeveloperName);
        }

        // Load registry flags (code-defined, not yet deployed as CMDT)
        List<FlipSwitch_Flag_Registry__c> registryFlags = FeatureFlagRegistry.getAllRegistryFlags();

        // Add registry flag keys (that don't duplicate a CMDT key) to the query set
        Set<String> registryOnlyKeys = new Set<String>();
        for (FlipSwitch_Flag_Registry__c reg : registryFlags) {
            if (!flagKeys.contains(reg.Flag_Key__c)) {
                registryOnlyKeys.add(reg.Flag_Key__c);
                flagKeys.add(reg.Flag_Key__c);
            }
            // Auto-promote: mark registry flags that now have a CMDT definition
            if (!registryOnlyKeys.contains(reg.Flag_Key__c)
                && !reg.Is_Promoted__c
                && flagKeys.contains(reg.Flag_Key__c)) {
                FeatureFlagRegistry.promoteFlag(reg.Flag_Key__c);
            }
        }

        if (flagKeys.isEmpty()) {
            return new List<FlagSummary>();
        }

        // Emergency-disable rules (Rule_Type__c = 'Emergency_Disable', Is_Active__c = true)
        Map<String, Boolean> emergencyDisabledMap = new Map<String, Boolean>();
        for (FlipSwitch_Rule__c r : [
            SELECT Flag_Key__c
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c IN :flagKeys
            AND    Rule_Type__c = 'Emergency_Disable'
            AND    Is_Active__c = true
            WITH   SECURITY_ENFORCED
        ]) {
            emergencyDisabledMap.put(r.Flag_Key__c, true);
        }

        // Active rule counts
        Map<String, Integer> ruleCounts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Flag_Key__c fk, COUNT(Id) cnt
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c IN :flagKeys
            AND    Is_Active__c = true
            WITH   SECURITY_ENFORCED
            GROUP BY Flag_Key__c
        ]) {
            ruleCounts.put((String) ar.get('fk'), (Integer) ar.get('cnt'));
        }

        // Variant keys per flag
        Map<String, List<String>> variantMap = new Map<String, List<String>>();
        for (FlipSwitch_Variant__c v : [
            SELECT Flag_Key__c, Variant_Key__c
            FROM   FlipSwitch_Variant__c
            WHERE  Flag_Key__c IN :flagKeys
            WITH   SECURITY_ENFORCED
            ORDER BY Flag_Key__c, Variant_Key__c
        ]) {
            if (!variantMap.containsKey(v.Flag_Key__c)) {
                variantMap.put(v.Flag_Key__c, new List<String>());
            }
            variantMap.get(v.Flag_Key__c).add(v.Variant_Key__c);
        }

        Date today = Date.today();
        Date soonThreshold = today.addDays(7);

        List<FlagSummary> results = new List<FlagSummary>();

        // Build summaries from CMDT flags (source = 'Deployed')
        for (FlipSwitch_Flag__mdt f : flagMdts) {
            FlagSummary s = buildCmdtSummary(
                f, emergencyDisabledMap, ruleCounts, variantMap, today, soonThreshold
            );
            s.source = 'Deployed';

            if (!passesFilter(s, category, status)) {
                continue;
            }
            results.add(s);
        }

        // Build summaries from registry-only flags (source = 'Code')
        for (FlipSwitch_Flag_Registry__c reg : registryFlags) {
            if (!registryOnlyKeys.contains(reg.Flag_Key__c)) {
                continue; // CMDT exists — skip
            }

            FlagSummary s = buildRegistrySummary(
                reg, emergencyDisabledMap, ruleCounts, variantMap, today, soonThreshold
            );
            s.source = 'Code';

            if (!passesFilter(s, category, status)) {
                continue;
            }
            results.add(s);
        }

        return results;
    }

    // ─── Summary builder helpers ──────────────────────────────────────────

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static FlagSummary buildCmdtSummary(
        FlipSwitch_Flag__mdt f,
        Map<String, Boolean> emergencyDisabledMap,
        Map<String, Integer> ruleCounts,
        Map<String, List<String>> variantMap,
        Date today,
        Date soonThreshold
    ) {
        FlagSummary s = new FlagSummary();
        s.developerName  = f.DeveloperName;
        s.label          = f.Label;
        s.description    = f.Description__c;
        s.type           = f.Type__c;
        s.defaultValue   = f.Default_Value__c;
        s.isActive       = f.Is_Active__c;
        s.category       = f.Category__c;
        s.expirationDate = f.Expiration_Date__c != null
                           ? String.valueOf(f.Expiration_Date__c) : null;
        s.isEmergencyDisabled  = emergencyDisabledMap.containsKey(f.DeveloperName);
        s.isExpired       = f.Expiration_Date__c != null && f.Expiration_Date__c < today;
        s.isExpiringSoon  = f.Expiration_Date__c != null
                           && f.Expiration_Date__c >= today
                           && f.Expiration_Date__c <= soonThreshold;
        s.variantKeys     = variantMap.containsKey(f.DeveloperName)
                           ? variantMap.get(f.DeveloperName) : new List<String>();
        s.activeRuleCount = ruleCounts.containsKey(f.DeveloperName)
                           ? ruleCounts.get(f.DeveloperName) : 0;

        if (f.Type__c == 'Percentage' && String.isNotBlank(f.Default_Value__c)) {
            try {
                s.rolloutPercent = Integer.valueOf(f.Default_Value__c);
            } catch (Exception ex) {
                s.rolloutPercent = 0;
            }
        }
        return s;
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static FlagSummary buildRegistrySummary(
        FlipSwitch_Flag_Registry__c reg,
        Map<String, Boolean> emergencyDisabledMap,
        Map<String, Integer> ruleCounts,
        Map<String, List<String>> variantMap,
        Date today,
        Date soonThreshold
    ) {
        FlagSummary s = new FlagSummary();
        s.developerName  = reg.Flag_Key__c;
        s.label          = reg.Name;
        s.description    = reg.Description__c;
        s.type           = reg.Type__c;
        s.defaultValue   = reg.Default_Value__c;
        s.isActive       = reg.Is_Active__c;
        s.category       = reg.Category__c;
        s.expirationDate = reg.Expiration_Date__c != null
                           ? String.valueOf(reg.Expiration_Date__c) : null;
        s.isEmergencyDisabled  = emergencyDisabledMap.containsKey(reg.Flag_Key__c);
        s.isExpired       = reg.Expiration_Date__c != null && reg.Expiration_Date__c < today;
        s.isExpiringSoon  = reg.Expiration_Date__c != null
                           && reg.Expiration_Date__c >= today
                           && reg.Expiration_Date__c <= soonThreshold;
        s.variantKeys     = variantMap.containsKey(reg.Flag_Key__c)
                           ? variantMap.get(reg.Flag_Key__c) : new List<String>();
        s.activeRuleCount = ruleCounts.containsKey(reg.Flag_Key__c)
                           ? ruleCounts.get(reg.Flag_Key__c) : 0;

        if (reg.Type__c == 'Percentage' && String.isNotBlank(reg.Default_Value__c)) {
            try {
                s.rolloutPercent = Integer.valueOf(reg.Default_Value__c);
            } catch (Exception ex) {
                s.rolloutPercent = 0;
            }
        }
        return s;
    }

    private static Boolean passesFilter(FlagSummary s, String category, String status) {
        if (String.isNotBlank(category) && s.category != category) {
            return false;
        }
        if (String.isNotBlank(status)) {
            if (status == 'active'     && (!s.isActive || s.isEmergencyDisabled || s.isExpired)) { return false; }
            if (status == 'disabled'   && (s.isActive || s.isEmergencyDisabled))                 { return false; }
            if (status == 'expired'    && !s.isExpired)                                      { return false; }
            if ((status == 'emergencydisable' || status == 'emergencydisabled') && !s.isEmergencyDisabled) { return false; }
            if (status == 'expiring'   && !s.isExpiringSoon)                                 { return false; }
        }
        return true;
    }

    /**
     * @description Returns org-level health counts for the admin shell strip.
     * @return  OrgHealth wrapper with counts
     */
    @AuraEnabled(cacheable=true)
    public static OrgHealth getOrgHealth() {
        List<FlagSummary> all = getFlags(null, null);
        OrgHealth h = new OrgHealth();
        h.totalActive     = 0;
        h.expiringSoon    = 0;
        h.emergencyDisabled = 0;
        h.circuitBreakers = 0;

        for (FlagSummary s : all) {
            if (s.isActive && !s.isEmergencyDisabled && !s.isExpired) { h.totalActive++; }
            if (s.isExpiringSoon)  { h.expiringSoon++; }
            if (s.isEmergencyDisabled)  { h.emergencyDisabled++; }
        }

        // Circuit breaker trips are not tracked per-row in FlipSwitch_Metric__c
        // (that object stores one aggregated row per flag).
        // This count is intentionally 0 until a separate circuit-breaker counter field is added.
        h.circuitBreakers = 0;

        return h;
    }

    // ─── Flag detail ─────────────────────────────────────────────────────────

    /**
     * @description Returns full flag detail including all rules and variants.
     * @param  flagKey  DeveloperName of the FlipSwitch_Flag__mdt record
     * @return          FlagDetail wrapper
     */
    @AuraEnabled(cacheable=true)
    public static FlagDetail getFlagDetail(String flagKey) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        // Determine source: CMDT or registry
        String source = 'Deployed';
        List<FlipSwitch_Flag__mdt> flagMdts = [
            SELECT DeveloperName, Label, Description__c, Type__c,
                   Default_Value__c, Is_Active__c, Expiration_Date__c, Category__c
            FROM   FlipSwitch_Flag__mdt
            WHERE  DeveloperName = :flagKey
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (flagMdts.isEmpty()) {
            // Fall back to registry for code-defined flags
            FlipSwitch_Flag_Registry__c regFlag = FeatureFlagRegistry.getRegistryFlag(flagKey);
            if (regFlag == null) {
                throw new AuraHandledException('Flag not found: ' + flagKey);
            }
            source = 'Code';
        }

        // Enrich summary via getFlags (reuse merged logic)
        List<FlagSummary> summaries = getFlags(null, null);
        FlagSummary matchedSummary;
        for (FlagSummary s : summaries) {
            if (s.developerName == flagKey) {
                matchedSummary = s;
                break;
            }
        }

        List<FlipSwitch_Rule__c> rules = [
            SELECT Id, Flag_Key__c, Rule_Type__c, Rule_Value__c, Variant_Value__c,
                   Priority__c, Is_Active__c, Start_Date__c, End_Date__c
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c = :flagKey
            WITH   SECURITY_ENFORCED
            ORDER BY Priority__c ASC NULLS LAST
        ];

        List<FlipSwitch_Variant__c> variants = [
            SELECT Id, Flag_Key__c, Variant_Key__c, Weight__c, Payload__c
            FROM   FlipSwitch_Variant__c
            WHERE  Flag_Key__c = :flagKey
            WITH   SECURITY_ENFORCED
            ORDER BY Variant_Key__c ASC
        ];

        FlagDetail detail = new FlagDetail();
        detail.summary  = matchedSummary;
        detail.rules    = rules;
        detail.variants = variants;
        detail.source   = source;
        return detail;
    }

    // ─── Registry management ─────────────────────────────────────────────────

    /**
     * @description Update a code-defined flag's metadata from the admin dashboard.
     *              Only applicable to FlipSwitch_Flag_Registry__c records; CMDT flags
     *              must be updated via deployment.
     * @param flag  The updated registry record
     */
    @AuraEnabled
    public static void updateRegistryFlag(FlipSwitch_Flag_Registry__c flag) {
        if (flag == null) {
            throw new AuraHandledException('flag is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Flag_Registry__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient access to update registry flags');
        }
        try {
            update flag;
            FeatureFlagRegistry.clearCache();
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Mark a code-defined flag as promoted (CMDT equivalent has been deployed).
     * @param flagKey  The flag DeveloperName to promote
     */
    @AuraEnabled
    public static void promoteRegistryFlag(String flagKey) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }
        FeatureFlagRegistry.promoteFlag(flagKey);
    }

    /**
     * @description Delete a stale or unused code-defined flag from the registry.
     * @param flagKey  The flag DeveloperName to delete
     */
    @AuraEnabled
    public static void deleteRegistryFlag(String flagKey) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Flag_Registry__c.isDeletable()) {
            throw new AuraHandledException('Insufficient access to delete registry flags');
        }
        List<FlipSwitch_Flag_Registry__c> toDelete = [
            SELECT Id FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c = :flagKey
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
            FeatureFlagRegistry.clearCache();
        }
    }

    // ─── Rule management ─────────────────────────────────────────────────────

    /**
     * @description Upserts a single targeting rule.
     * @param  rule  FlipSwitch_Rule__c to insert or update
     * @return       Saved rule with Id populated
     */
    @AuraEnabled
    public static FlipSwitch_Rule__c saveRule(FlipSwitch_Rule__c rule) {
        if (rule == null) {
            throw new AuraHandledException('rule is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Rule__c.isCreateable()
            || !Schema.sObjectType.FlipSwitch_Rule__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient access to manage rules');
        }
        try {
            upsert rule;
            return rule;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes a targeting rule by Id.
     * @param  ruleId  Id of the FlipSwitch_Rule__c to delete
     */
    @AuraEnabled
    public static void deleteRule(Id ruleId) {
        if (ruleId == null) {
            throw new AuraHandledException('ruleId is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Rule__c.isDeletable()) {
            throw new AuraHandledException('Insufficient access to delete rules');
        }
        try {
            delete new FlipSwitch_Rule__c(Id = ruleId);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Bulk-updates Priority__c for a list of rules (drag-to-reorder).
     *              Accepts a list of records with Id + Priority__c populated.
     * @param  rules  List of FlipSwitch_Rule__c with updated priorities
     */
    @AuraEnabled
    public static void reorderRules(List<FlipSwitch_Rule__c> rules) {
        if (rules == null || rules.isEmpty()) {
            return;
        }
        if (!Schema.sObjectType.FlipSwitch_Rule__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient access to reorder rules');
        }
        try {
            update rules;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Emergency disable ───────────────────────────────────────────────────────────

    /**
     * @description Toggles the runtime emergency disable for a flag.
     *              Creates an Emergency_Disable rule when activating; deletes it when deactivating.
     * @param  flagKey  DeveloperName of the flag
     * @param  active   true = enable emergency disable, false = remove it
     */
    @AuraEnabled
    public static void toggleEmergencyDisable(String flagKey, Boolean active) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        List<FlipSwitch_Rule__c> existing = [
            SELECT Id
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c    = :flagKey
            AND    Rule_Type__c   = 'Emergency_Disable'
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        if (active) {
            // Create if it doesn't already exist
            if (!existing.isEmpty()) {
                return;
            }
            if (!Schema.sObjectType.FlipSwitch_Rule__c.isCreateable()) {
                throw new AuraHandledException('Insufficient access to create emergency disable');
            }
            insertEmergencyDisableRule(flagKey);
        } else {
            // Delete if it exists
            if (!existing.isEmpty()) {
                if (!Schema.sObjectType.FlipSwitch_Rule__c.isDeletable()) {
                    throw new AuraHandledException('Insufficient access to remove emergency disable');
                }
                deleteEmergencyDisableRules(existing);
            }
            // Always activate code-defined flags (no-op if already active or CMDT)
            activateRegistryFlagIfNeeded(flagKey);
        }

        FeatureFlagCache.removeFlag(flagKey);
    }

    /**
     * @description When removing emergency disable from a code-defined flag,
     *              activate it so the UI shows 'Active' instead of 'Disabled'.
     *              CMDT flags are unaffected — their Is_Active__c is deployment-controlled.
     */
    private static void activateRegistryFlagIfNeeded(String flagKey) {
        FlipSwitch_Flag_Registry__c reg = FeatureFlagRegistry.getRegistryFlag(flagKey);
        if (reg != null && !reg.Is_Active__c) {
            reg.Is_Active__c = true;
            try {
                update reg;
            } catch (DmlException e) {
                throw new AuraHandledException(e.getMessage());
            }
            FeatureFlagRegistry.clearCache();
        }
    }

    private static void insertEmergencyDisableRule(String flagKey) {
        FlipSwitch_Rule__c ed = new FlipSwitch_Rule__c(
            Flag_Key__c   = flagKey,
            Rule_Type__c  = 'Emergency_Disable',
            Is_Active__c  = true,
            Priority__c   = 0
        );
        try {
            insert ed;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static void deleteEmergencyDisableRules(List<FlipSwitch_Rule__c> rules) {
        try {
            delete rules;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Bulk operations ─────────────────────────────────────────────────────

    /**
     * @description Bulk-enables or bulk-disables multiple flags via emergency-disable rules.
     *              action = 'enable' removes all emergency-disable rules for the given keys.
     *              action = 'disable' creates emergency-disable rules for the given keys.
     * @param  flagKeys  List of DeveloperName values
     * @param  action    'enable' | 'disable'
     */
    @AuraEnabled
    public static void bulkUpdateFlags(List<String> flagKeys, String action) {
        if (flagKeys == null || flagKeys.isEmpty()) {
            return;
        }
        if (action != 'enable' && action != 'disable') {
            throw new AuraHandledException('action must be "enable" or "disable"');
        }

        for (String key : flagKeys) {
            toggleEmergencyDisable(key, action == 'disable');
        }
    }

    // ─── Variants ────────────────────────────────────────────────────────────

    /**
     * @description Upserts a variant definition.
     * @param  variant  FlipSwitch_Variant__c to insert or update
     * @return          Saved variant with Id populated
     */
    @AuraEnabled
    public static FlipSwitch_Variant__c saveVariant(FlipSwitch_Variant__c variant) {
        if (variant == null) {
            throw new AuraHandledException('variant is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Variant__c.isCreateable()
            || !Schema.sObjectType.FlipSwitch_Variant__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient access to manage variants');
        }
        try {
            upsert variant;
            return variant;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes a variant by Id.
     * @param  variantId  Id of the FlipSwitch_Variant__c to delete
     */
    @AuraEnabled
    public static void deleteVariant(Id variantId) {
        if (variantId == null) {
            throw new AuraHandledException('variantId is required');
        }
        if (!Schema.sObjectType.FlipSwitch_Variant__c.isDeletable()) {
            throw new AuraHandledException('Insufficient access to delete variants');
        }
        try {
            delete new FlipSwitch_Variant__c(Id = variantId);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Evaluation preview ──────────────────────────────────────────────────

    /**
     * @description Simulates a flag evaluation for a given user + attributes
     *              without persisting any data (no cache, no logging).
     *              Delegates to FeatureFlagEvaluator with silent mode.
     * @param  flagKey   DeveloperName of the flag to preview
     * @param  userId    Id of the user to simulate for (null = running user)
     * @param  attrsJson JSON-serialized Map<String,String> of context attributes
     * @return           EvalPreviewResult with isEnabled, variant, reason
     */
    @AuraEnabled
    public static EvalPreviewResult previewEvaluation(
        String flagKey,
        String userId,
        String attrsJson
    ) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        Id targetUserId = String.isNotBlank(userId)
            ? (Id) userId
            : UserInfo.getUserId();

        Map<String, Object> attrs = new Map<String, Object>();
        if (String.isNotBlank(attrsJson)) {
            try {
                attrs = (Map<String, Object>) JSON.deserializeUntyped(attrsJson);
            } catch (Exception ex) {
                throw new AuraHandledException('Invalid attrs JSON: ' + ex.getMessage());
            }
        }

        EvalPreviewResult result = new EvalPreviewResult();
        try {
            // Delegate to the evaluation engine with silent flag
            FeatureFlagResult evalResult = FeatureFlag.flag(flagKey)
                .forUser(targetUserId)
                .withAttributes(attrs)
                .silent()
                .evaluate();

            result.isEnabled = evalResult.isEnabled;
            result.variant   = evalResult.variant;
            result.reason    = evalResult.reason;
            result.payload   = evalResult.payload != null
                               ? JSON.serialize(evalResult.payload) : null;
        } catch (Exception ex) {
            // Surface error in the preview panel rather than throwing to the UI
            result.isEnabled = false;
            result.variant   = null;
            result.reason    = 'ERROR: ' + ex.getMessage();
            result.payload   = null;
        }

        return result;
    }

    // ─── Analytics ───────────────────────────────────────────────────────────

    /**
     * @description Returns aggregated analytics for a flag from FlipSwitch_Metric__c.
     * @param  flagKey    DeveloperName of the flag
     * @param  startDateStr  ISO date string (yyyy-MM-dd), null = last 30 days
     * @param  endDateStr    ISO date string (yyyy-MM-dd), null = today
     * @return            FlagAnalytics wrapper
     */
    @AuraEnabled(cacheable=true)
    public static FlagAnalytics getMetrics(
        String flagKey,
        String startDateStr,
        String endDateStr
    ) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        // FlipSwitch_Metric__c stores ONE aggregated row per flag.
        // Variant_Distribution__c contains a JSON map: {"control":450,"treatment_a":550}
        // Evaluation_Count__c and Unique_Users__c are the totals.
        // Date range parameters are accepted for API compatibility but the object
        // stores cumulative totals (not time-series); daily stats require a
        // separate log object or Platform Event subscriber enhancement.
        List<FlipSwitch_Metric__c> metrics = [
            SELECT Flag_Key__c, Evaluation_Count__c, Unique_Users__c,
                   Variant_Distribution__c, Last_Evaluated__c
            FROM   FlipSwitch_Metric__c
            WHERE  Flag_Key__c = :flagKey
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        FlagAnalytics analytics = new FlagAnalytics();
        analytics.flagKey             = flagKey;
        analytics.totalEvaluations    = 0;
        analytics.uniqueUsers         = 0;
        analytics.circuitBreakerTrips = 0;
        analytics.variantStats        = new List<VariantStat>();
        analytics.dailyStats          = new List<DailyStat>();

        if (metrics.isEmpty()) {
            return analytics;
        }

        FlipSwitch_Metric__c m = metrics[0];
        analytics.totalEvaluations = m.Evaluation_Count__c != null
            ? m.Evaluation_Count__c.intValue() : 0;
        analytics.uniqueUsers = m.Unique_Users__c != null
            ? m.Unique_Users__c.intValue() : 0;

        // Parse Variant_Distribution__c JSON map → VariantStat list
        if (String.isNotBlank(m.Variant_Distribution__c)) {
            try {
                Map<String, Object> distMap =
                    (Map<String, Object>) JSON.deserializeUntyped(m.Variant_Distribution__c);
                Integer total = analytics.totalEvaluations > 0
                    ? analytics.totalEvaluations : 1;

                List<VariantStat> stats = new List<VariantStat>();
                for (String varKey : distMap.keySet()) {
                    VariantStat vs = new VariantStat();
                    vs.variantKey  = varKey;
                    vs.count       = ((Decimal) distMap.get(varKey)).intValue();
                    vs.uniqueUsers = 0; // not tracked per-variant in this schema
                    vs.percentage  = ((Decimal) vs.count / total * 100).setScale(1);
                    stats.add(vs);
                }
                // Sort descending by count
                stats.sort(new VariantStatComparator());
                analytics.variantStats = stats;
            } catch (Exception ex) { // NOPMD - EmptyCatchBlock: invalid JSON returns empty stats
            }
        }

        // Daily stats: not available from the aggregated metric object.
        // Stub a single data point using Last_Evaluated__c for sparkline display.
        if (m.Last_Evaluated__c != null) {
            DailyStat ds = new DailyStat();
            ds.evalDate = String.valueOf(m.Last_Evaluated__c.date());
            ds.count    = analytics.totalEvaluations;
            analytics.dailyStats.add(ds);
        }

        return analytics;
    }

    /** @description Comparator for VariantStat sort descending by count. */
    private class VariantStatComparator implements Comparator<VariantStat> {
        /** @description Compare two VariantStats by count descending.
         *  @param a  First stat
         *  @param b  Second stat
         *  @return   Negative if b < a, positive if b > a, zero if equal
         */
        public Integer compare(VariantStat a, VariantStat b) {
            return b.count - a.count;
        }
    }

    // ─── Distinct categories ─────────────────────────────────────────────────

    /**
     * @description Returns a sorted deduplicated list of all Category__c values
     *              in use, for the filter-pill row on the dashboard.
     * @return  List of distinct category strings
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getCategories() {
        Set<String> cats = new Set<String>();
        for (FlipSwitch_Flag__mdt f : [
            SELECT Category__c
            FROM   FlipSwitch_Flag__mdt
            WHERE  Category__c != null
            WITH   SECURITY_ENFORCED
        ]) {
            cats.add(f.Category__c);
        }
        List<String> sorted = new List<String>(cats);
        sorted.sort();
        return sorted;
    }

    // ─── Rule value lookup methods ──────────────────────────────────────────

    /** @description Option wrapper for combobox/lookup dropdowns. */
    public class LookupOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String sublabel { get; set; }
        public LookupOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        public LookupOption(String label, String value, String sublabel) {
            this.label = label;
            this.value = value;
            this.sublabel = sublabel;
        }
    }

    /**
     * @description Returns all active profiles for the Profile rule type dropdown.
     *              The evaluator matches on Profile ID, so value = Id.
     */
    @AuraEnabled(cacheable=true)
    public static List<LookupOption> getProfiles() {
        List<LookupOption> options = new List<LookupOption>();
        for (Profile p : [
            SELECT Id, Name
            FROM   Profile
            WHERE  UserType = 'Standard'
            ORDER BY Name
        ]) {
            options.add(new LookupOption(p.Name, p.Id));
        }
        return options;
    }

    /**
     * @description Returns non-profile-owned permission sets for the Permission Set rule type.
     *              The evaluator matches on PermissionSet Name, so value = Name.
     */
    @AuraEnabled(cacheable=true)
    public static List<LookupOption> getPermissionSets() {
        List<LookupOption> options = new List<LookupOption>();
        for (PermissionSet ps : [
            SELECT Id, Name, Label
            FROM   PermissionSet
            WHERE  IsOwnedByProfile = false
            ORDER BY Label
        ]) {
            options.add(new LookupOption(
                String.isNotBlank(ps.Label) ? ps.Label : ps.Name,
                ps.Name,
                ps.Name
            ));
        }
        return options;
    }

    /**
     * @description Typeahead search for Users. Returns top 20 matches.
     *              The evaluator matches on User ID, so value = Id.
     */
    @AuraEnabled
    public static List<LookupOption> searchUsers(String searchTerm) {
        List<LookupOption> options = new List<LookupOption>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return options;
        }
        String sanitized = String.escapeSingleQuotes(searchTerm.trim());
        List<List<SObject>> results = Search.query(
            'FIND \'' + sanitized + '*\' IN NAME FIELDS RETURNING User(Id, Name, Email WHERE IsActive = true) LIMIT 20'
        );
        if (!results.isEmpty()) {
            for (SObject s : results[0]) {
                User u = (User) s;
                String lbl = u.Name;
                String sub = u.Email != null ? u.Email : '';
                options.add(new LookupOption(lbl, u.Id, sub));
            }
        }
        return options;
    }

    /**
     * @description Typeahead search for Accounts. Returns top 20 matches.
     *              The evaluator matches on Account ID, so value = Id.
     */
    @AuraEnabled
    public static List<LookupOption> searchAccounts(String searchTerm) {
        List<LookupOption> options = new List<LookupOption>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return options;
        }
        String sanitized = String.escapeSingleQuotes(searchTerm.trim());
        List<List<SObject>> results = Search.query(
            'FIND \'' + sanitized + '*\' IN NAME FIELDS RETURNING Account(Id, Name) LIMIT 20'
        );
        if (!results.isEmpty()) {
            for (SObject s : results[0]) {
                Account a = (Account) s;
                options.add(new LookupOption(a.Name, a.Id));
            }
        }
        return options;
    }

    /**
     * @description Returns territories for the Territory rule type dropdown.
     *              Uses dynamic SOQL to gracefully handle orgs without Territory Management.
     *              The evaluator matches on Territory2 ID, so value = Id.
     */
    @AuraEnabled(cacheable=true)
    public static List<LookupOption> getTerritories() {
        List<LookupOption> options = new List<LookupOption>();
        try {
            List<SObject> territories = Database.query(
                'SELECT Id, Name FROM Territory2 ORDER BY Name LIMIT 1000'
            );
            for (SObject t : territories) {
                options.add(new LookupOption(
                    (String) t.get('Name'),
                    (String) t.get('Id')
                ));
            }
        } catch (Exception e) {
            // Territory Management not enabled — return empty list
        }
        return options;
    }

    /**
     * @description Resolves semicolon-delimited IDs or names back to display labels.
     *              Used when editing an existing rule to show pills with readable names.
     */
    @AuraEnabled
    public static List<LookupOption> resolveRuleValues(String ruleType, String ruleValue) {
        List<LookupOption> options = new List<LookupOption>();
        if (String.isBlank(ruleValue)) {
            return options;
        }
        List<String> values = ruleValue.split(';');
        Set<String> trimmed = new Set<String>();
        for (String v : values) {
            if (String.isNotBlank(v)) {
                trimmed.add(v.trim());
            }
        }
        if (trimmed.isEmpty()) {
            return options;
        }

        switch on ruleType {
            when 'User' {
                for (User u : [SELECT Id, Name, Email FROM User WHERE Id IN :trimmed]) {
                    options.add(new LookupOption(u.Name, u.Id, u.Email));
                }
            }
            when 'Profile' {
                for (Profile p : [SELECT Id, Name FROM Profile WHERE Id IN :trimmed]) {
                    options.add(new LookupOption(p.Name, p.Id));
                }
            }
            when 'Permission_Set' {
                for (PermissionSet ps : [
                    SELECT Id, Name, Label
                    FROM   PermissionSet
                    WHERE  Name IN :trimmed
                      AND  IsOwnedByProfile = false
                ]) {
                    options.add(new LookupOption(
                        String.isNotBlank(ps.Label) ? ps.Label : ps.Name,
                        ps.Name,
                        ps.Name
                    ));
                }
            }
            when 'Account' {
                for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :trimmed]) {
                    options.add(new LookupOption(a.Name, a.Id));
                }
            }
            when 'Territory' {
                try {
                    for (SObject t : Database.query(
                        'SELECT Id, Name FROM Territory2 WHERE Id IN :trimmed'
                    )) {
                        options.add(new LookupOption(
                            (String) t.get('Name'),
                            (String) t.get('Id')
                        ));
                    }
                } catch (Exception e) {
                    // Territory Management not enabled
                }
            }
        }
        return options;
    }

    // ─── Flag definition CRUD ────────────────────────────────────────────────

    /** @description Input wrapper for flag create/update operations. */
    public class FlagInput {
        @AuraEnabled public String  flagKey        { get; set; }
        @AuraEnabled public String  label          { get; set; }
        @AuraEnabled public String  description    { get; set; }
        @AuraEnabled public String  type           { get; set; }
        @AuraEnabled public String  defaultValue   { get; set; }
        @AuraEnabled public String  category       { get; set; }
        @AuraEnabled public String  expirationDate { get; set; }
        @AuraEnabled public Boolean isActive       { get; set; }
        @AuraEnabled public String  storageTarget  { get; set; }
    }

    /** @description Result wrapper for operations that may trigger async deployments. */
    public class FlagCrudResult {
        @AuraEnabled public Boolean success    { get; set; }
        @AuraEnabled public String  message    { get; set; }
        @AuraEnabled public Boolean isAsync    { get; set; }
        @AuraEnabled public String  deployJobId { get; set; }
    }

    private static final Pattern FLAG_KEY_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');
    private static final Set<String> VALID_TYPES = new Set<String>{ 'Boolean', 'Percentage', 'Variant' };

    /**
     * @description Validates a flag definition input and returns error message or null if valid.
     */
    private static String validateFlagInput(FlagInput input, Boolean isCreate) {
        if (input == null) {
            return 'Flag input is required';
        }
        if (isCreate && String.isBlank(input.flagKey)) {
            return 'Flag key is required';
        }
        if (isCreate && !FLAG_KEY_PATTERN.matcher(input.flagKey).matches()) {
            return 'Flag key must start with a letter and contain only letters, numbers, and underscores';
        }
        if (String.isBlank(input.label)) {
            return 'Label is required';
        }
        if (String.isNotBlank(input.type) && !VALID_TYPES.contains(input.type)) {
            return 'Type must be Boolean, Percentage, or Variant';
        }
        // Validate default value matches type
        if (String.isNotBlank(input.type) && String.isNotBlank(input.defaultValue)) {
            if (input.type == 'Boolean' && input.defaultValue != 'true' && input.defaultValue != 'false') {
                return 'Default value for Boolean flags must be "true" or "false"';
            }
            if (input.type == 'Percentage') {
                try {
                    Integer pct = Integer.valueOf(input.defaultValue);
                    if (pct < 0 || pct > 100) {
                        return 'Default value for Percentage flags must be between 0 and 100';
                    }
                } catch (Exception e) {
                    return 'Default value for Percentage flags must be a number between 0 and 100';
                }
            }
        }
        // Validate expiration date format
        if (String.isNotBlank(input.expirationDate)) {
            try {
                Date.valueOf(input.expirationDate);
            } catch (Exception e) {
                return 'Invalid expiration date format (expected yyyy-MM-dd)';
            }
        }
        return null;
    }

    /**
     * @description Checks key uniqueness across both CMDT and Registry.
     */
    private static Boolean flagKeyExists(String flagKey) {
        // Check CMDT
        List<FlipSwitch_Flag__mdt> cmdtFlags = [
            SELECT DeveloperName FROM FlipSwitch_Flag__mdt
            WHERE DeveloperName = :flagKey LIMIT 1
        ];
        if (!cmdtFlags.isEmpty()) {
            return true;
        }
        // Check Registry
        FlipSwitch_Flag_Registry__c reg = FeatureFlagRegistry.getRegistryFlag(flagKey);
        return reg != null;
    }

    /**
     * @description Creates a new flag definition.
     *              Registry flags are created via DML (instant).
     *              CMDT flags are deployed via Metadata API (async).
     * @param input  FlagInput wrapper with all flag metadata
     * @return       FlagCrudResult indicating success or async deployment
     */
    @AuraEnabled
    public static FlagCrudResult createFlag(FlagInput input) {
        String validationError = validateFlagInput(input, true);
        if (validationError != null) {
            throw new AuraHandledException(validationError);
        }

        if (flagKeyExists(input.flagKey)) {
            throw new AuraHandledException('A flag with key "' + input.flagKey + '" already exists');
        }

        FlagCrudResult result = new FlagCrudResult();

        if (input.storageTarget == 'CMDT') {
            // Deploy via Metadata API (async)
            Metadata.CustomMetadata md = buildCmdtRecord(input);
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            container.addMetadata(md);
            Id jobId = Metadata.Operations.enqueueDeployment(container, new FlagDeployCallback(input.flagKey, 'create'));
            result.success    = true;
            result.isAsync    = true;
            result.deployJobId = String.valueOf(jobId);
            result.message    = 'CMDT deployment queued for flag "' + input.flagKey + '"';
        } else {
            // Registry: instant DML
            if (!Schema.sObjectType.FlipSwitch_Flag_Registry__c.isCreateable()) {
                throw new AuraHandledException('Insufficient access to create registry flags');
            }
            FlipSwitch_Flag_Registry__c reg = buildRegistryRecord(input);
            try {
                insert reg;
                FeatureFlagRegistry.clearCache();
            } catch (DmlException e) {
                throw new AuraHandledException(e.getMessage());
            }
            result.success = true;
            result.isAsync = false;
            result.message = 'Flag "' + input.flagKey + '" created successfully';
        }
        return result;
    }

    /**
     * @description Updates an existing flag definition's metadata.
     *              Registry flags are updated via DML (instant).
     *              CMDT flags are updated via Metadata API (async).
     * @param input  FlagInput wrapper with updated metadata and flagKey
     * @return       FlagCrudResult indicating success or async deployment
     */
    @AuraEnabled
    public static FlagCrudResult updateFlagDefinition(FlagInput input) {
        String validationError = validateFlagInput(input, false);
        if (validationError != null) {
            throw new AuraHandledException(validationError);
        }
        if (String.isBlank(input.flagKey)) {
            throw new AuraHandledException('Flag key is required for update');
        }

        FlagCrudResult result = new FlagCrudResult();

        if (input.storageTarget == 'CMDT' || input.storageTarget == 'Deployed') {
            // Check CMDT flag exists
            List<FlipSwitch_Flag__mdt> existing = [
                SELECT DeveloperName FROM FlipSwitch_Flag__mdt
                WHERE DeveloperName = :input.flagKey LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw new AuraHandledException('CMDT flag "' + input.flagKey + '" not found');
            }

            Metadata.CustomMetadata md = buildCmdtRecord(input);
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            container.addMetadata(md);
            Id jobId = Metadata.Operations.enqueueDeployment(container, new FlagDeployCallback(input.flagKey, 'update'));
            result.success    = true;
            result.isAsync    = true;
            result.deployJobId = String.valueOf(jobId);
            result.message    = 'CMDT deployment queued for flag "' + input.flagKey + '"';
        } else {
            // Registry update
            if (!Schema.sObjectType.FlipSwitch_Flag_Registry__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient access to update registry flags');
            }
            List<FlipSwitch_Flag_Registry__c> existing = [
                SELECT Id, Flag_Key__c, Name, Type__c, Default_Value__c, Category__c,
                       Description__c, Expiration_Date__c, Is_Active__c, Source__c
                FROM FlipSwitch_Flag_Registry__c
                WHERE Flag_Key__c = :input.flagKey
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw new AuraHandledException('Registry flag "' + input.flagKey + '" not found');
            }
            FlipSwitch_Flag_Registry__c reg = existing[0];
            applyInputToRegistry(reg, input);
            try {
                update reg;
                FeatureFlagRegistry.clearCache();
            } catch (DmlException e) {
                throw new AuraHandledException(e.getMessage());
            }
            result.success = true;
            result.isAsync = false;
            result.message = 'Flag "' + input.flagKey + '" updated successfully';
        }
        return result;
    }

    /**
     * @description Deletes a flag definition and cascade-deletes all related data.
     *              Registry flags are deleted via DML (instant).
     *              CMDT flags are soft-deleted (Pending_Removal__c=true) then hard-deleted async.
     * @param flagKey  DeveloperName of the flag to delete
     * @param source   'Deployed' (CMDT) or 'Code' (Registry)
     * @return         FlagCrudResult indicating success or async deployment
     */
    @AuraEnabled
    public static FlagCrudResult deleteFlag(String flagKey, String source) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        FlagCrudResult result = new FlagCrudResult();

        // Cascade delete children (common for both storage types)
        cascadeDeleteChildren(flagKey);

        // Clear platform cache
        FeatureFlagCache.removeFlag(flagKey);

        if (source == 'Deployed') {
            // Soft-delete: set Pending_Removal__c = true via Metadata API
            Metadata.CustomMetadata md = new Metadata.CustomMetadata();
            md.fullName = 'FlipSwitch_Flag__mdt.' + flagKey;
            md.label = flagKey;
            Metadata.CustomMetadataValue fv = new Metadata.CustomMetadataValue();
            fv.field = 'Pending_Removal__c';
            fv.value = true;
            md.values.add(fv);
            Metadata.CustomMetadataValue av = new Metadata.CustomMetadataValue();
            av.field = 'Is_Active__c';
            av.value = false;
            md.values.add(av);

            Metadata.DeployContainer container = new Metadata.DeployContainer();
            container.addMetadata(md);
            Id jobId = Metadata.Operations.enqueueDeployment(container, new FlagDeployCallback(flagKey, 'delete'));
            result.success    = true;
            result.isAsync    = true;
            result.deployJobId = String.valueOf(jobId);
            result.message    = 'Flag "' + flagKey + '" marked for removal. Children deleted.';
        } else {
            // Registry: instant DML delete
            if (!Schema.sObjectType.FlipSwitch_Flag_Registry__c.isDeletable()) {
                throw new AuraHandledException('Insufficient access to delete registry flags');
            }
            List<FlipSwitch_Flag_Registry__c> toDelete = [
                SELECT Id FROM FlipSwitch_Flag_Registry__c
                WHERE Flag_Key__c = :flagKey
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (!toDelete.isEmpty()) {
                delete toDelete;
                FeatureFlagRegistry.clearCache();
            }
            result.success = true;
            result.isAsync = false;
            result.message = 'Flag "' + flagKey + '" and all related data deleted.';
        }
        return result;
    }

    /**
     * @description Cascade-deletes all rules, variants, assignments, and metrics for a flag.
     */
    private static void cascadeDeleteChildren(String flagKey) {
        // Delete assignments
        List<FlipSwitch_Assignment__c> assignments = [
            SELECT Id FROM FlipSwitch_Assignment__c
            WHERE Flag_Key__c = :flagKey
        ];
        if (!assignments.isEmpty() && Schema.sObjectType.FlipSwitch_Assignment__c.isDeletable()) {
            delete assignments;
        }

        // Delete variants
        List<FlipSwitch_Variant__c> variants = [
            SELECT Id FROM FlipSwitch_Variant__c
            WHERE Flag_Key__c = :flagKey
        ];
        if (!variants.isEmpty() && Schema.sObjectType.FlipSwitch_Variant__c.isDeletable()) {
            delete variants;
        }

        // Delete rules
        List<FlipSwitch_Rule__c> rules = [
            SELECT Id FROM FlipSwitch_Rule__c
            WHERE Flag_Key__c = :flagKey
        ];
        if (!rules.isEmpty() && Schema.sObjectType.FlipSwitch_Rule__c.isDeletable()) {
            delete rules;
        }

        // Delete metrics
        List<FlipSwitch_Metric__c> metrics = [
            SELECT Id FROM FlipSwitch_Metric__c
            WHERE Flag_Key__c = :flagKey
        ];
        if (!metrics.isEmpty() && Schema.sObjectType.FlipSwitch_Metric__c.isDeletable()) {
            delete metrics;
        }
    }

    // ─── CMDT builder helpers ────────────────────────────────────────────────

    private static Metadata.CustomMetadata buildCmdtRecord(FlagInput input) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'FlipSwitch_Flag__mdt.' + input.flagKey;
        md.label = input.label;

        addCmdtValue(md, 'Description__c', input.description);
        addCmdtValue(md, 'Default_Value__c', input.defaultValue);
        addCmdtValue(md, 'Category__c', input.category);
        addCmdtValue(md, 'Is_Active__c', input.isActive != null ? input.isActive : true);

        if (String.isNotBlank(input.expirationDate)) {
            addCmdtValue(md, 'Expiration_Date__c', Date.valueOf(input.expirationDate));
        }

        return md;
    }

    private static void addCmdtValue(Metadata.CustomMetadata md, String field, Object value) {
        Metadata.CustomMetadataValue fv = new Metadata.CustomMetadataValue();
        fv.field = field;
        fv.value = value;
        md.values.add(fv);
    }

    private static FlipSwitch_Flag_Registry__c buildRegistryRecord(FlagInput input) {
        FlipSwitch_Flag_Registry__c reg = new FlipSwitch_Flag_Registry__c();
        reg.Name             = input.label != null ? input.label.left(80) : input.flagKey.left(80);
        reg.Flag_Key__c      = input.flagKey;
        reg.Type__c          = String.isNotBlank(input.type) ? input.type : 'Boolean';
        reg.Default_Value__c = String.isNotBlank(input.defaultValue) ? input.defaultValue : 'false';
        reg.Category__c      = input.category;
        reg.Description__c   = input.description;
        reg.Is_Active__c     = input.isActive != null ? input.isActive : true;
        reg.Source__c         = 'Manual';
        reg.First_Seen_Date__c = Datetime.now();
        if (String.isNotBlank(input.expirationDate)) {
            reg.Expiration_Date__c = Date.valueOf(input.expirationDate);
        }
        return reg;
    }

    private static void applyInputToRegistry(FlipSwitch_Flag_Registry__c reg, FlagInput input) {
        if (input.label != null) {
            reg.Name = input.label.left(80);
        }
        if (input.type != null) {
            reg.Type__c = input.type;
        }
        if (input.defaultValue != null) {
            reg.Default_Value__c = input.defaultValue;
        }
        if (input.category != null) {
            reg.Category__c = input.category;
        }
        if (input.description != null) {
            reg.Description__c = input.description;
        }
        if (input.isActive != null) {
            reg.Is_Active__c = input.isActive;
        }
        if (String.isNotBlank(input.expirationDate)) {
            reg.Expiration_Date__c = Date.valueOf(input.expirationDate);
        }
    }

    // ─── Metadata API deploy callback ────────────────────────────────────────

    /**
     * @description Callback for Metadata API deployments triggered by flag CRUD operations.
     *              Logs success/failure via FeatureFlagLogger.
     */
    public class FlagDeployCallback implements Metadata.DeployCallback {
        private String flagKey;
        private String operation;

        public FlagDeployCallback(String flagKey, String operation) {
            this.flagKey = flagKey;
            this.operation = operation;
        }

        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            if (result != null && result.status == Metadata.DeployStatus.Succeeded) {
                System.debug(LoggingLevel.INFO,
                    'FlipSwitch CMDT ' + operation + ' succeeded for flag: ' + flagKey);
            } else {
                String errorMsg = 'FlipSwitch CMDT ' + operation + ' failed for flag: ' + flagKey;
                if (result != null && result.errorMessage != null) {
                    errorMsg += ' — ' + result.errorMessage;
                }
                System.debug(LoggingLevel.ERROR, errorMsg);
            }
        }
    }
}
