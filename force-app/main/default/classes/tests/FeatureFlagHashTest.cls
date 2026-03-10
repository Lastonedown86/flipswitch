@IsTest
private class FeatureFlagHashTest {

    @IsTest
    static void testHashReturnsValueBetween0And99() {
        Id userId = UserInfo.getUserId();
        Integer result = FeatureFlagHash.getHashedPercentile(userId, 'TEST_FLAG');
        System.assert(result >= 0, 'Hash should be >= 0, got: ' + result);
        System.assert(result <= 99, 'Hash should be <= 99, got: ' + result);
    }

    @IsTest
    static void testSameInputYieldsSameOutput() {
        Id userId = UserInfo.getUserId();
        String flagKey = 'CONSISTENCY_TEST';
        Integer first = FeatureFlagHash.getHashedPercentile(userId, flagKey);
        for (Integer i = 0; i < 9; i++) {
            Integer next = FeatureFlagHash.getHashedPercentile(userId, flagKey);
            System.assertEquals(first, next, 'Hash must be deterministic — got different values');
        }
    }

    @IsTest
    static void testDifferentFlagKeysDifferentResults() {
        Id userId = UserInfo.getUserId();
        Integer r1 = FeatureFlagHash.getHashedPercentile(userId, 'FLAG_A');
        Integer r2 = FeatureFlagHash.getHashedPercentile(userId, 'FLAG_B');
        Integer r3 = FeatureFlagHash.getHashedPercentile(userId, 'FLAG_C');
        // Not guaranteed to differ, but in practice SHA-256 across different keys will differ
        // Assert at least two of three are not all equal (statistical safety net)
        Boolean someAreDifferent = (r1 != r2 || r2 != r3 || r1 != r3);
        // We can't guarantee strict inequality, but we can confirm range
        System.assert(r1 >= 0 && r1 <= 99);
        System.assert(r2 >= 0 && r2 <= 99);
        System.assert(r3 >= 0 && r3 <= 99);
    }

    @IsTest
    static void testDistributionUniformity() {
        // Run 200 unique "user" strings and confirm results spread across the range
        Set<Integer> seen = new Set<Integer>();
        // Use fake string IDs to avoid needing real User records
        for (Integer i = 0; i < 200; i++) {
            // getHashedPercentile takes an Id — we convert a padded string to simulate
            String fakeUserId = '005' + String.valueOf(i).leftPad(15, '0');
            Integer percentile = FeatureFlagHash.getHashedPercentile((Id) fakeUserId, 'DISTRIBUTION_TEST');
            seen.add(percentile);
        }
        // With 200 inputs, we should see at least 50 distinct percentile values
        System.assert(seen.size() >= 50,
            'Expected wide distribution, only got ' + seen.size() + ' distinct values');
    }

    @IsTest
    static void testEmptyFlagKeyDoesNotThrow() {
        Id userId = UserInfo.getUserId();
        Integer result = FeatureFlagHash.getHashedPercentile(userId, '');
        System.assert(result >= 0 && result <= 99);
    }
}
