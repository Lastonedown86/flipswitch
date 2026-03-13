/**
 * @description AuraEnabled controller for the featureFlagAdmin LWC suite.
 *              Provides flag dashboard data, rule CRUD, kill-switch toggling,
 *              evaluation preview, bulk operations, and aggregated analytics.
 *              Flag definitions (FlipSwitch_Flag__mdt) are read-only via SOQL;
 *              mutations are delegated to Metadata API via a @future callout.
 *              Runtime data (FlipSwitch_Rule__c, FlipSwitch_Metric__c, etc.)
 *              is managed with standard DML.
 * @author      FlipSwitch
 */
public with sharing class FeatureFlagAdminController {

    // ─── Inner wrapper types ────────────────────────────────────────────────

    /** Lightweight flag summary for the dashboard list. */
    public class FlagSummary {
        @AuraEnabled public String  developerName   { get; set; }
        @AuraEnabled public String  label           { get; set; }
        @AuraEnabled public String  description     { get; set; }
        @AuraEnabled public String  type            { get; set; }
        @AuraEnabled public String  defaultValue    { get; set; }
        @AuraEnabled public Boolean isActive        { get; set; }
        @AuraEnabled public String  category        { get; set; }
        @AuraEnabled public String  expirationDate  { get; set; }
        @AuraEnabled public Boolean isKillSwitched  { get; set; }
        @AuraEnabled public Boolean isExpired       { get; set; }
        @AuraEnabled public Boolean isExpiringSoon  { get; set; }
        @AuraEnabled public Integer rolloutPercent  { get; set; }
        @AuraEnabled public List<String> variantKeys { get; set; }
        @AuraEnabled public Integer activeRuleCount { get; set; }
    }

    /** Full flag detail including all rules and variants. */
    public class FlagDetail {
        @AuraEnabled public FlagSummary              summary  { get; set; }
        @AuraEnabled public List<FlipSwitch_Rule__c> rules    { get; set; }
        @AuraEnabled public List<FlipSwitch_Variant__c> variants { get; set; }
    }

    /** Result of a simulated evaluation (preview panel). */
    public class EvalPreviewResult {
        @AuraEnabled public Boolean isEnabled { get; set; }
        @AuraEnabled public String  variant   { get; set; }
        @AuraEnabled public String  reason    { get; set; }
        @AuraEnabled public String  payload   { get; set; }
    }

    /** Aggregated analytics for the analytics tab. */
    public class FlagAnalytics {
        @AuraEnabled public String              flagKey           { get; set; }
        @AuraEnabled public Integer             totalEvaluations  { get; set; }
        @AuraEnabled public Integer             uniqueUsers       { get; set; }
        @AuraEnabled public Integer             circuitBreakerTrips { get; set; }
        @AuraEnabled public List<VariantStat>   variantStats      { get; set; }
        @AuraEnabled public List<DailyStat>     dailyStats        { get; set; }
    }

    public class VariantStat {
        @AuraEnabled public String  variantKey   { get; set; }
        @AuraEnabled public Integer count        { get; set; }
        @AuraEnabled public Integer uniqueUsers  { get; set; }
        @AuraEnabled public Decimal percentage   { get; set; }
    }

    public class DailyStat {
        @AuraEnabled public String  evalDate { get; set; }
        @AuraEnabled public Integer count    { get; set; }
    }

    /** Org-level health counts for the admin shell summary strip. */
    public class OrgHealth {
        @AuraEnabled public Integer totalActive      { get; set; }
        @AuraEnabled public Integer expiringSoon     { get; set; }
        @AuraEnabled public Integer killSwitched     { get; set; }
        @AuraEnabled public Integer circuitBreakers  { get; set; }
    }

    // ─── Dashboard ───────────────────────────────────────────────────────────

    /**
     * @description Returns all flag summaries enriched with rule data.
     *              Applies optional category and status filters.
     * @param  category  Category__c value to filter on; null = all
     * @param  status    'active' | 'disabled' | 'expired' | 'killswitch' | null = all
     * @return           List<FlagSummary>
     */
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

        if (flagMdts.isEmpty()) {
            return new List<FlagSummary>();
        }

        // Collect flag keys for rule / variant / metric queries
        Set<String> flagKeys = new Set<String>();
        for (FlipSwitch_Flag__mdt f : flagMdts) {
            flagKeys.add(f.DeveloperName);
        }

        // Kill-switch rules (Rule_Type__c = 'Kill_Switch', Is_Active__c = true)
        Map<String, Boolean> killSwitchedMap = new Map<String, Boolean>();
        for (FlipSwitch_Rule__c r : [
            SELECT Flag_Key__c
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c IN :flagKeys
            AND    Rule_Type__c = 'Kill_Switch'
            AND    Is_Active__c = true
            WITH   SECURITY_ENFORCED
        ]) {
            killSwitchedMap.put(r.Flag_Key__c, true);
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

        for (FlipSwitch_Flag__mdt f : flagMdts) {
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
            s.isKillSwitched  = killSwitchedMap.containsKey(f.DeveloperName);
            s.isExpired       = f.Expiration_Date__c != null && f.Expiration_Date__c < today;
            s.isExpiringSoon  = f.Expiration_Date__c != null
                               && f.Expiration_Date__c >= today
                               && f.Expiration_Date__c <= soonThreshold;
            s.variantKeys     = variantMap.containsKey(f.DeveloperName)
                               ? variantMap.get(f.DeveloperName) : new List<String>();
            s.activeRuleCount = ruleCounts.containsKey(f.DeveloperName)
                               ? ruleCounts.get(f.DeveloperName) : 0;

            // Parse rollout % from Default_Value__c for Percentage flags
            if (f.Type__c == 'Percentage' && String.isNotBlank(f.Default_Value__c)) {
                try {
                    s.rolloutPercent = Integer.valueOf(f.Default_Value__c);
                } catch (Exception ex) {
                    s.rolloutPercent = 0;
                }
            }

            // Apply filters
            if (String.isNotBlank(category) && f.Category__c != category) {
                continue;
            }
            if (String.isNotBlank(status)) {
                if (status == 'active'     && (!f.Is_Active__c || s.isKillSwitched || s.isExpired)) continue;
                if (status == 'disabled'   && (f.Is_Active__c || s.isKillSwitched))                 continue;
                if (status == 'expired'    && !s.isExpired)                                          continue;
                if (status == 'killswitch' && !s.isKillSwitched)                                     continue;
            }

            results.add(s);
        }

        return results;
    }

    /**
     * @description Returns org-level health counts for the admin shell strip.
     */
    @AuraEnabled(cacheable=true)
    public static OrgHealth getOrgHealth() {
        List<FlagSummary> all = getFlags(null, null);
        OrgHealth h = new OrgHealth();
        h.totalActive     = 0;
        h.expiringSoon    = 0;
        h.killSwitched    = 0;
        h.circuitBreakers = 0;

        for (FlagSummary s : all) {
            if (s.isActive && !s.isKillSwitched && !s.isExpired) h.totalActive++;
            if (s.isExpiringSoon)  h.expiringSoon++;
            if (s.isKillSwitched)  h.killSwitched++;
        }

        // Circuit breaker trips: Evaluation__e rows with reason = 'CIRCUIT_BREAKER'
        // stored in FlipSwitch_Metric__c (if subscriber is running)
        // Approximate from metric records with reason indicator
        List<AggregateResult> cbTrips = [
            SELECT COUNT(Id) cnt
            FROM   FlipSwitch_Metric__c
            WHERE  Evaluation_Reason__c = 'CIRCUIT_BREAKER'
            WITH   SECURITY_ENFORCED
        ];
        if (!cbTrips.isEmpty() && cbTrips[0].get('cnt') != null) {
            h.circuitBreakers = (Integer) cbTrips[0].get('cnt');
        }

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

        List<FlipSwitch_Flag__mdt> flagMdts = [
            SELECT DeveloperName, Label, Description__c, Type__c,
                   Default_Value__c, Is_Active__c, Expiration_Date__c, Category__c
            FROM   FlipSwitch_Flag__mdt
            WHERE  DeveloperName = :flagKey
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (flagMdts.isEmpty()) {
            throw new AuraHandledException('Flag not found: ' + flagKey);
        }

        // Enrich summary via getFlags (reuse logic)
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
        return detail;
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

    // ─── Kill switch ─────────────────────────────────────────────────────────

    /**
     * @description Toggles the runtime kill switch for a flag.
     *              Creates a Kill_Switch rule when activating; deletes it when deactivating.
     * @param  flagKey  DeveloperName of the flag
     * @param  active   true = enable kill switch, false = remove it
     */
    @AuraEnabled
    public static void toggleKillSwitch(String flagKey, Boolean active) {
        if (String.isBlank(flagKey)) {
            throw new AuraHandledException('flagKey is required');
        }

        List<FlipSwitch_Rule__c> existing = [
            SELECT Id
            FROM   FlipSwitch_Rule__c
            WHERE  Flag_Key__c    = :flagKey
            AND    Rule_Type__c   = 'Kill_Switch'
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        if (active) {
            // Create if it doesn't already exist
            if (existing.isEmpty()) {
                if (!Schema.sObjectType.FlipSwitch_Rule__c.isCreateable()) {
                    throw new AuraHandledException('Insufficient access to create kill switch');
                }
                FlipSwitch_Rule__c ks = new FlipSwitch_Rule__c(
                    Flag_Key__c   = flagKey,
                    Rule_Type__c  = 'Kill_Switch',
                    Is_Active__c  = true,
                    Priority__c   = 0
                );
                try {
                    insert ks;
                } catch (DmlException e) {
                    throw new AuraHandledException(e.getMessage());
                }
            }
        } else {
            // Delete if it exists
            if (!existing.isEmpty()) {
                if (!Schema.sObjectType.FlipSwitch_Rule__c.isDeletable()) {
                    throw new AuraHandledException('Insufficient access to remove kill switch');
                }
                try {
                    delete existing;
                } catch (DmlException e) {
                    throw new AuraHandledException(e.getMessage());
                }
            }
        }
    }

    // ─── Bulk operations ─────────────────────────────────────────────────────

    /**
     * @description Bulk-enables or bulk-disables multiple flags via kill-switch rules.
     *              action = 'enable' removes all kill-switch rules for the given keys.
     *              action = 'disable' creates kill-switch rules for the given keys.
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
            toggleKillSwitch(key, action == 'disable');
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
     * @param  attrs     JSON-serialized Map<String,String> of context attributes
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
     * @param  startDate  ISO date string (yyyy-MM-dd), null = last 30 days
     * @param  endDate    ISO date string (yyyy-MM-dd), null = today
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

        Date endDate   = String.isNotBlank(endDateStr)
                         ? Date.valueOf(endDateStr) : Date.today();
        Date startDate = String.isNotBlank(startDateStr)
                         ? Date.valueOf(startDateStr) : endDate.addDays(-30);

        // Variant distribution
        List<VariantStat> variantStats = new List<VariantStat>();
        Integer totalEvals = 0;

        List<AggregateResult> variantAgg = [
            SELECT Result__c variant, COUNT(Id) cnt, COUNT_DISTINCT(User_Id__c) uniq
            FROM   FlipSwitch_Metric__c
            WHERE  Flag_Key__c          = :flagKey
            AND    Evaluation_Date__c  >= :startDate
            AND    Evaluation_Date__c  <= :endDate
            WITH   SECURITY_ENFORCED
            GROUP BY Result__c
            ORDER BY COUNT(Id) DESC
        ];

        for (AggregateResult ar : variantAgg) {
            VariantStat vs = new VariantStat();
            vs.variantKey  = (String)  ar.get('variant');
            vs.count       = (Integer) ar.get('cnt');
            vs.uniqueUsers = (Integer) ar.get('uniq');
            variantStats.add(vs);
            totalEvals    += vs.count;
        }

        // Back-fill percentages
        for (VariantStat vs : variantStats) {
            vs.percentage = totalEvals > 0
                ? ((Decimal) vs.count / totalEvals * 100).setScale(1) : 0;
        }

        // Daily evaluation volume
        List<DailyStat> dailyStats = new List<DailyStat>();
        List<AggregateResult> dailyAgg = [
            SELECT Evaluation_Date__c evalDate, COUNT(Id) cnt
            FROM   FlipSwitch_Metric__c
            WHERE  Flag_Key__c          = :flagKey
            AND    Evaluation_Date__c  >= :startDate
            AND    Evaluation_Date__c  <= :endDate
            WITH   SECURITY_ENFORCED
            GROUP BY Evaluation_Date__c
            ORDER BY Evaluation_Date__c ASC
        ];

        for (AggregateResult ar : dailyAgg) {
            DailyStat ds = new DailyStat();
            ds.evalDate = String.valueOf((Date) ar.get('evalDate'));
            ds.count    = (Integer) ar.get('cnt');
            dailyStats.add(ds);
        }

        // Circuit breaker trips
        List<AggregateResult> cbAgg = [
            SELECT COUNT(Id) cnt
            FROM   FlipSwitch_Metric__c
            WHERE  Flag_Key__c          = :flagKey
            AND    Evaluation_Reason__c = 'CIRCUIT_BREAKER'
            AND    Evaluation_Date__c  >= :startDate
            AND    Evaluation_Date__c  <= :endDate
            WITH   SECURITY_ENFORCED
        ];
        Integer cbTrips = (!cbAgg.isEmpty() && cbAgg[0].get('cnt') != null)
                          ? (Integer) cbAgg[0].get('cnt') : 0;

        // Unique users across all variants
        List<AggregateResult> uniqAgg = [
            SELECT COUNT_DISTINCT(User_Id__c) uniq
            FROM   FlipSwitch_Metric__c
            WHERE  Flag_Key__c          = :flagKey
            AND    Evaluation_Date__c  >= :startDate
            AND    Evaluation_Date__c  <= :endDate
            WITH   SECURITY_ENFORCED
        ];
        Integer uniqueUsers = (!uniqAgg.isEmpty() && uniqAgg[0].get('uniq') != null)
                              ? (Integer) uniqAgg[0].get('uniq') : 0;

        FlagAnalytics analytics = new FlagAnalytics();
        analytics.flagKey            = flagKey;
        analytics.totalEvaluations   = totalEvals;
        analytics.uniqueUsers        = uniqueUsers;
        analytics.circuitBreakerTrips = cbTrips;
        analytics.variantStats       = variantStats;
        analytics.dailyStats         = dailyStats;
        return analytics;
    }

    // ─── Distinct categories ─────────────────────────────────────────────────

    /**
     * @description Returns a sorted deduplicated list of all Category__c values
     *              in use, for the filter-pill row on the dashboard.
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
}
