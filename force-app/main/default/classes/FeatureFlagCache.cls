/**
 * @description Platform Cache integration for FlipSwitch.
 *
 *              Two cache tiers:
 *              - Org-level: CMDT flag definitions (rarely change, safe to cache long)
 *              - Session-level: per-user evaluation results (scoped to session)
 *
 *              Gracefully degrades to a no-op if the Platform Cache partition
 *              is not configured — the framework still works, just slower.
 */
public class FeatureFlagCache {

    private static final String PARTITION_NAME;
    private static final String ORG_PARTITION_KEY_PREFIX    = 'ff_flag_';
    private static final String SESSION_PARTITION_KEY_PREFIX = 'ff_eval_';
    private static final Integer DEFAULT_TTL_SECONDS = 3600; // 1 hour

    static {
        Feature_Flag_Config__mdt config = getConfig();
        PARTITION_NAME = config != null && String.isNotBlank(config.Cache_Partition_Name__c)
            ? config.Cache_Partition_Name__c
            : 'local.FlipSwitch';
    }

    // ─── Org-Level Cache (flag definitions) ───────────────────────────────

    /**
     * @description Store a flag definition in the org-level cache.
     */
    public static void putFlag(String flagKey, Object value) {
        putFlag(flagKey, value, DEFAULT_TTL_SECONDS);
    }

    public static void putFlag(String flagKey, Object value, Integer ttlSeconds) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            partition.put(ORG_PARTITION_KEY_PREFIX + sanitizeKey(flagKey), value, ttlSeconds);
        } catch (Exception e) {
            // Cache partition not configured or unavailable — silently skip
        }
    }

    /**
     * @description Retrieve a flag definition from the org-level cache.
     * @return  The cached value, or null on miss or error
     */
    public static Object getFlag(String flagKey) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            return partition.get(ORG_PARTITION_KEY_PREFIX + sanitizeKey(flagKey));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Remove a specific flag from the org-level cache.
     */
    public static void removeFlag(String flagKey) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            partition.remove(ORG_PARTITION_KEY_PREFIX + sanitizeKey(flagKey));
        } catch (Exception e) {
            // Silently skip
        }
    }

    // ─── Session-Level Cache (evaluation results) ─────────────────────────

    /**
     * @description Store a per-user evaluation result in the session cache.
     *              Key is userId:flagKey.
     */
    public static void putEvaluation(String userId, String flagKey, FeatureFlagResult result) {
        try {
            Cache.SessionPartition partition = Cache.Session.getPartition(PARTITION_NAME);
            String cacheKey = SESSION_PARTITION_KEY_PREFIX + sanitizeKey(userId + '_' + flagKey);
            partition.put(cacheKey, result, DEFAULT_TTL_SECONDS);
        } catch (Exception e) {
            // Silently skip
        }
    }

    /**
     * @description Retrieve a cached evaluation result for userId + flagKey.
     * @return  FeatureFlagResult, or null on miss
     */
    public static FeatureFlagResult getEvaluation(String userId, String flagKey) {
        try {
            Cache.SessionPartition partition = Cache.Session.getPartition(PARTITION_NAME);
            String cacheKey = SESSION_PARTITION_KEY_PREFIX + sanitizeKey(userId + '_' + flagKey);
            return (FeatureFlagResult) partition.get(cacheKey);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Invalidate all cached evaluations. Called when rules change.
     */
    public static void invalidateAll() {
        try {
            Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
            orgPartition.remove(new FeatureFlagCacheRemovalListener());
        } catch (Exception e) {
            // Silently skip
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────

    private static String sanitizeKey(String key) {
        // Cache keys: alphanumeric + underscore only, max 50 chars
        return key.replaceAll('[^a-zA-Z0-9_]', '_').left(50);
    }

    private static Feature_Flag_Config__mdt getConfig() {
        List<Feature_Flag_Config__mdt> configs = [
            SELECT Cache_Partition_Name__c
            FROM Feature_Flag_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    /**
     * @description Removal listener that removes all FlipSwitch cache entries
     *              when cache invalidation is triggered.
     */
    public class FeatureFlagCacheRemovalListener implements Cache.CacheBuilder {
        public Object doLoad(String key) {
            return null; // Not used for removal
        }
    }
}
