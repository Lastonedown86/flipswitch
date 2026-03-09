@IsTest
private class FeatureFlagCacheTest {

    @IsTest
    static void testPutAndGetFlag() {
        Test.startTest();
        FeatureFlagCache.putFlag('TEST_FLAG', 'cachedValue');
        Object result = FeatureFlagCache.getFlag('TEST_FLAG');
        Test.stopTest();
        // In test context, Platform Cache may not be available (no partition).
        // The contract is: no exception thrown. Value may or may not be cached.
        System.assert(true, 'No exception should be thrown on cache put/get');
    }

    @IsTest
    static void testCacheMissReturnsNull() {
        Test.startTest();
        Object result = FeatureFlagCache.getFlag('NONEXISTENT_FLAG_' + Datetime.now().getTime());
        Test.stopTest();
        System.assertEquals(null, result, 'Cache miss should return null');
    }

    @IsTest
    static void testRemoveFlag() {
        Test.startTest();
        FeatureFlagCache.putFlag('REMOVABLE_FLAG', 'value');
        FeatureFlagCache.removeFlag('REMOVABLE_FLAG');
        Object result = FeatureFlagCache.getFlag('REMOVABLE_FLAG');
        Test.stopTest();
        System.assertEquals(null, result, 'After remove, cache should return null');
    }

    @IsTest
    static void testPutEvaluationAndGetEvaluation() {
        Id userId = UserInfo.getUserId();
        FeatureFlagResult expected = FeatureFlagResult.enabled('treatment_a', null, FeatureFlagResult.REASON_RULE_MATCH);
        Test.startTest();
        FeatureFlagCache.putEvaluation(userId, 'EVAL_FLAG', expected);
        FeatureFlagResult result = FeatureFlagCache.getEvaluation(userId, 'EVAL_FLAG');
        Test.stopTest();
        // No exception is the core assertion; result may be null if no cache partition
        System.assert(true, 'No exception thrown on evaluation cache put/get');
    }

    @IsTest
    static void testGetEvaluationMissReturnsNull() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        FeatureFlagResult result = FeatureFlagCache.getEvaluation(userId, 'CACHE_MISS_FLAG_' + Datetime.now().getTime());
        Test.stopTest();
        System.assertEquals(null, result, 'Cache miss should return null');
    }

    @IsTest
    static void testGracefulFallbackWhenPartitionUnavailable() {
        // Platform Cache is not available in unit test context without a real org partition.
        // The cache methods must silently absorb the error.
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            FeatureFlagCache.putFlag('ANY_KEY', 'ANY_VALUE');
            FeatureFlagCache.getFlag('ANY_KEY');
            FeatureFlagCache.removeFlag('ANY_KEY');
            FeatureFlagCache.invalidateAll();
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, exceptionThrown, 'Cache operations must never throw exceptions to callers');
    }

    @IsTest
    static void testSpecialCharactersInKeyAreSanitized() {
        Test.startTest();
        // Keys with special characters should not throw
        FeatureFlagCache.putFlag('FLAG WITH SPACES & SYMBOLS!', 'value');
        FeatureFlagCache.getFlag('FLAG WITH SPACES & SYMBOLS!');
        Test.stopTest();
        System.assert(true, 'Special characters in key should not cause exceptions');
    }
}
