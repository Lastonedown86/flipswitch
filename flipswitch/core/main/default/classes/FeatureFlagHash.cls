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
     * @param flagKey The FlipSwitch_Flag__mdt DeveloperName
     * @return        Integer in [0, 99]
     */
    public static Integer getHashedPercentile(Id userId, String flagKey) {
        String input = String.valueOf(userId) + ':' + String.valueOf(flagKey);
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(input));
        String hex = EncodingUtil.convertToHex(digest);
        // Take the first 8 hex chars (32 bits) and parse as a positive long
        Long hashVal = hexToLong(hex.substring(0, 8));
        return Math.abs(Integer.valueOf(Math.mod(hashVal, 100)));
    }

    private static Long hexToLong(String hex) {
        Long result = 0;
        for (Integer i = 0; i < hex.length(); i++) {
            Integer digit = hexCharToInt(hex.substring(i, i + 1));
            result = (result * 16) + digit;
        }
        return result;
    }

    private static Integer hexCharToInt(String c) {
        String lower = c.toLowerCase();
        if (lower == 'a') {
            return 10;
        } else if (lower == 'b') {
            return 11;
        } else if (lower == 'c') {
            return 12;
        } else if (lower == 'd') {
            return 13;
        } else if (lower == 'e') {
            return 14;
        } else if (lower == 'f') {
            return 15;
        }
        return Integer.valueOf(lower);
    }
}
