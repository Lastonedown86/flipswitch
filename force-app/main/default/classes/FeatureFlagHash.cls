/**
 * @description Deterministic hashing utility for consistent percentage rollouts.
 *
 *              Uses SHA-256(userId + ':' + flagKey) % 100 to assign a stable
 *              0–99 percentile to each user+flag combination. This guarantees
 *              the same user always gets the same result for the same flag,
 *              without storing any per-user assignment records.
 */
public inherited sharing class FeatureFlagHash {

    /**
     * @description Returns a deterministic integer in [0, 99] for a given
     *              userId + flagKey pair. The same inputs always produce the
     *              same output, providing sticky assignment without storage.
     *
     * @param userId  The Salesforce user Id
     * @param flagKey The Feature_Flag__mdt DeveloperName
     * @return        Integer in [0, 99]
     */
    public static Integer getHashedPercentile(Id userId, String flagKey) {
        String input = String.valueOf(userId) + ':' + String.valueOf(flagKey);
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(input));
        String hex = EncodingUtil.convertToHex(digest);
        // Take the first 8 hex chars (32 bits) and convert to a positive long
        Long hashVal = Long.valueOf('0x' + hex.substring(0, 8));
        return Math.abs(Integer.valueOf(Math.mod(hashVal, 100)));
    }
}
