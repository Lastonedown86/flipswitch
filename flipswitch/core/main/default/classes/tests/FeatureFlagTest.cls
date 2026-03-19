@IsTest
private class FeatureFlagTest {

    private static void insertEnableRule() {
        insert new FlipSwitch_Rule__c(
            Name                = 'Enable Running User',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
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
        System.assertEquals(false, result, 'isEnabled should return false when no matching rule exists');
    }

    @IsTest
    static void testStaticIsEnabledReturnsTrueWithRule() {
        insertEnableRule();
        Test.startTest();
        Boolean result = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertEquals(true, result, 'isEnabled should return true when a matching user rule exists');
    }

    @IsTest
    static void testStaticGetVariant() {
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
        System.assertNotEquals(null, builder, 'flags(2-args) should return a non-null batch builder');
    }

    @IsTest
    static void testFlagsOverloadThreeArgs() {
        FeatureFlagBatchBuilder builder = FeatureFlag.flags(
            'SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG'
        );
        System.assertNotEquals(null, builder, 'flags(3-args) should return a non-null batch builder');
    }

    // ─── Logging controls ──────────────────────────────────────────────────

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
        System.assertEquals(1, FeatureFlagLogger.getBufferSize(), 'Buffer should have 1 entry after setScenario + evaluation');
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
        System.assertNotEquals(null, result, 'isEnabledForCurrentUser should return a non-null Boolean');
    }

    @IsTest
    static void testGetVariantForCurrentUser() {
        Test.startTest();
        String result = FeatureFlag.getVariantForCurrentUser('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();
        System.assertNotEquals(null, result, 'getVariantForCurrentUser should return a non-null string');
    }

    @IsTest
    static void testEvaluateFlagsForCurrentUser() {
        Test.startTest();
        Map<String, Object> results = FeatureFlag.evaluateFlagsForCurrentUser(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        );
        Test.stopTest();
        System.assert(results.containsKey('SAMPLE_BOOLEAN_FLAG'), 'evaluateFlagsForCurrentUser should include the requested flag key');
    }

    @IsTest
    static void testGetAllFlags() {
        Test.startTest();
        List<FlipSwitch_Flag__mdt> flags = FeatureFlag.getAllFlags();
        Test.stopTest();
        System.assert(!flags.isEmpty(), 'getAllFlags should return at least the sample CMDT record');
    }

    @IsTest
    static void testActivateAndDeactivateEmergencyDisable() {
        Test.startTest();
        FeatureFlag.activateEmergencyDisable('SAMPLE_BOOLEAN_FLAG');
        Boolean afterActivation = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        FeatureFlag.deactivateEmergencyDisable('SAMPLE_BOOLEAN_FLAG');
        Boolean afterDeactivation = FeatureFlag.isEnabled('SAMPLE_BOOLEAN_FLAG');
        Test.stopTest();

        System.assertEquals(false, afterActivation,   'Emergency disable should disable the flag');
        System.assertEquals(false, afterDeactivation, 'After deactivation, default (false) applies');
    }

    // ─── Flag definition API ──────────────────────────────────────────────

    @IsTest
    static void testDefineReturnsDefinitionBuilder() {
        FeatureFlagDefinition def = FeatureFlag.define('DEFINE_API_TEST');
        System.assertNotEquals(null, def, 'define() should return a non-null FeatureFlagDefinition');
    }

    @IsTest
    static void testRegisterCreatesRegistryRecord() {
        Test.startTest();
        FeatureFlag.register('REGISTER_API_TEST');
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'REGISTER_API_TEST'
        ];
        System.assertEquals(1, count, 'register() should create a registry record');
    }

    @IsTest
    static void testIsEnabledWithFallbackForCodeDefinedFlag() {
        Test.startTest();
        Boolean result = FeatureFlag.flag('NEVER_DEPLOYED_FLAG')
            .fallback(true)
            .isEnabled();
        Test.stopTest();

        System.assertEquals(true, result,
            'Fallback should apply for code-defined flag with NOT_CONFIGURED reason');
    }
}
