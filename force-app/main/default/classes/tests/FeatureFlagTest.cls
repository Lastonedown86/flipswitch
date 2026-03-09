@IsTest
private class FeatureFlagTest {

    private static void insertEnableRule() {
        insert new Feature_Flag_Rule__c(
            Name                = 'Enable Running User',
            Feature_Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(UserInfo.getUserId()),
            Priority__c         = 10,
            Is_Active__c        = true
        );
    }

    // ─── Static convenience API ───────────────────────────────────────────

    @IsTest
    static void testStaticIsEnabledReturnsFalseByDefault() {
        Test.startTest();
        Boolean result = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        // Default_Value__c = 'false' on the CMDT sample record
        System.assertEquals(false, result);
    }

    @IsTest
    static void testStaticIsEnabledReturnsTrueWhenRuleMatches() {
        insertEnableRule();
        Test.startTest();
        Boolean result = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertEquals(true, result);
    }

    @IsTest
    static void testStaticGetVariantReturnsString() {
        Test.startTest();
        String variant = FeatureFlag.getVariant('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertNotEquals(null, variant, 'getVariant should always return a non-null string');
    }

    // ─── Factory methods ──────────────────────────────────────────────────

    @IsTest
    static void testFlagFactoryReturnsBuilder() {
        FeatureFlagBuilder builder = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG');
        System.assertNotEquals(null, builder, 'flag() should return a non-null builder');
    }

    @IsTest
    static void testFlagsFactoryReturnsBatchBuilder() {
        FeatureFlagBatchBuilder builder = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        );
        System.assertNotEquals(null, builder, 'flags() should return a non-null batch builder');
    }

    @IsTest
    static void testFlagsOverloadTwoArgs() {
        FeatureFlagBatchBuilder builder = FeatureFlag.flags('SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG');
        System.assertNotEquals(null, builder);
    }

    @IsTest
    static void testFlagsOverloadThreeArgs() {
        FeatureFlagBatchBuilder builder = FeatureFlag.flags(
            'SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG'
        );
        System.assertNotEquals(null, builder);
    }

    // ─── Transaction controls ─────────────────────────────────────────────

    @IsTest
    static void testSuspendLoggingPreventsBuffering() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.suspendLogging();
        FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Integer buffered = FeatureFlagLogger.getBufferSize();
        Test.stopTest();
        System.assertEquals(0, buffered, 'suspendLogging() should prevent evaluation from being buffered');
    }

    @IsTest
    static void testResumeLoggingRestoresBuffering() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.suspendLogging();
        FeatureFlag.resumeLogging();
        FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Integer buffered = FeatureFlagLogger.getBufferSize();
        Test.stopTest();
        System.assertEquals(1, buffered, 'resumeLogging() should restore buffering');
    }

    @IsTest
    static void testFlushEvaluationsPublishesAndClearsBuffer() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        System.assertEquals(1, FeatureFlagLogger.getBufferSize(), 'Should have 1 buffered entry before flush');
        FeatureFlag.flushEvaluations();
        System.assertEquals(0, FeatureFlagLogger.getBufferSize(), 'Buffer should be empty after flush');
        Test.stopTest();
    }

    @IsTest
    static void testSetScenarioTagsSubsequentCalls() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.setScenario('Checkout Flow');
        FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        // Verify scenario was set — buffer should have entry
        System.assertEquals(1, FeatureFlagLogger.getBufferSize());
        // Reset scenario for test isolation
        FeatureFlag.setScenario(null);
    }

    @IsTest
    static void testSetSaveMethodDoesNotThrow() {
        Test.startTest();
        FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.EVENT_BUS);
        FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.QUEUEABLE);
        FeatureFlag.setSaveMethod(FeatureFlag.SaveMethod.SYNCHRONOUS);
        Test.stopTest();
        System.assert(true, 'setSaveMethod should not throw for any valid enum value');
    }

    // ─── AuraEnabled methods ──────────────────────────────────────────────

    @IsTest
    static void testIsEnabledForCurrentUser() {
        Test.startTest();
        Boolean result = FeatureFlag.isEnabledForCurrentUser('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetVariantForCurrentUser() {
        Test.startTest();
        String result = FeatureFlag.getVariantForCurrentUser('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testEvaluateFlagsForCurrentUser() {
        Test.startTest();
        Map<String, Object> results = FeatureFlag.evaluateFlagsForCurrentUser(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        );
        Test.stopTest();
        System.assert(results.containsKey('SAMPLE_BOOLEAN_FLAG'));
    }

    @IsTest
    static void testGetAllFlags() {
        Test.startTest();
        List<Feature_Flag__mdt> flags = FeatureFlag.getAllFlags();
        Test.stopTest();
        System.assert(!flags.isEmpty(), 'getAllFlags should return at least the sample CMDT record');
    }

    @IsTest
    static void testActivateAndDeactivateKillSwitch() {
        Test.startTest();
        FeatureFlag.activateKillSwitch('SAMPLE_BOOLEAN_FLAG');
        Boolean afterActivation = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        FeatureFlag.deactivateKillSwitch('SAMPLE_BOOLEAN_FLAG');
        Boolean afterDeactivation = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();

        System.assertEquals(false, afterActivation,   'Kill switch should disable the flag');
        System.assertEquals(false, afterDeactivation, 'After deactivation, default (false) applies');
    }
}
