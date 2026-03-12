@IsTest
private class FeatureFlagBuilderTest {

    // ─── Helpers ──────────────────────────────────────────────────────────

    private static FlipSwitch_Rule__c enableForCurrentUser() {
        FlipSwitch_Rule__c rule = new FlipSwitch_Rule__c(
            Name                = 'Enable Test User',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(UserInfo.getUserId()),
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert rule;
        return rule;
    }

    // ─── isEnabled terminal ───────────────────────────────────────────────

    @IsTest
    static void testIsEnabledReturnsTrueWhenRuleMatches() {
        enableForCurrentUser();
        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').isEnabled();
        Test.stopTest();
        System.assertEquals(true, result);
    }

    @IsTest
    static void testIsEnabledReturnsFalseWhenNoRules() {
        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').isEnabled();
        Test.stopTest();
        // Default_Value__c = 'false' on the CMDT sample record
        System.assertEquals(false, result);
    }

    // ─── getVariant terminal ──────────────────────────────────────────────

    @IsTest
    static void testGetVariantReturnsVariantKey() {
        FlipSwitch_Rule__c rule = new FlipSwitch_Rule__c(
            Name                = 'Variant Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(UserInfo.getUserId()),
            Variant_Value__c    = 'treatment_a',
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert rule;

        Test.startTest();
        String variant = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').getVariant();
        Test.stopTest();

        System.assertEquals('treatment_a', variant);
    }

    // ─── fallback ─────────────────────────────────────────────────────────

    @IsTest
    static void testBooleanFallbackOverridesDefaultWhenNoRules() {
        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .fallback(true)
            .isEnabled();
        Test.stopTest();
        // CMDT default is false; fallback(true) should override
        System.assertEquals(true, result, 'fallback(true) should override CMDT default of false');
    }

    @IsTest
    static void testFallbackNotAppliedWhenRuleMatches() {
        enableForCurrentUser();
        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .fallback(false) // should be ignored — rule matched
            .isEnabled();
        Test.stopTest();
        System.assertEquals(true, result, 'Rule match should take precedence over fallback');
    }

    // ─── forUser ─────────────────────────────────────────────────────────

    @IsTest
    static void testForUserSetsTargetUser() {
        Id currentUser = UserInfo.getUserId();
        FlipSwitch_Rule__c rule = new FlipSwitch_Rule__c(
            Name                = 'Specific User Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(currentUser),
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert rule;

        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .forUser(currentUser)
            .isEnabled();
        Test.stopTest();

        System.assertEquals(true, result, '.forUser() should use the specified user for evaluation');
    }

    // ─── withAttribute / Segment ──────────────────────────────────────────

    @IsTest
    static void testWithAttributePassedToSegmentRule() {
        FlipSwitch_Rule__c rule = new FlipSwitch_Rule__c(
            Name                = 'Segment Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'Segment',
            Rule_Value__c       = '{"region":"EMEA"}',
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert rule;

        Test.startTest();
        Boolean matchResult = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .withAttribute('region', 'EMEA')
            .isEnabled();
        Boolean noMatchResult = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .withAttribute('region', 'APAC')
            .isEnabled();
        Test.stopTest();

        System.assertEquals(true,  matchResult,   'Matching attribute should trigger rule');
        System.assertEquals(false, noMatchResult, 'Non-matching attribute should not trigger rule');
    }

    @IsTest
    static void testWithAttributesBulkAdd() {
        FlipSwitch_Rule__c rule = new FlipSwitch_Rule__c(
            Name                = 'Multi Segment Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'Segment',
            Rule_Value__c       = '{"region":"US","tier":"Premium"}',
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert rule;

        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .withAttributes(new Map<String, Object>{ 'region' => 'US', 'tier' => 'Premium' })
            .isEnabled();
        Test.stopTest();

        System.assertEquals(true, result);
    }

    // ─── silent ───────────────────────────────────────────────────────────

    @IsTest
    static void testSilentSuppressesLogBuffer() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').silent().isEnabled();
        Integer bufferSize = FeatureFlagLogger.getBufferSize();
        Test.stopTest();
        System.assertEquals(0, bufferSize, 'silent() should prevent entries being added to log buffer');
    }

    @IsTest
    static void testNonSilentAddsToLogBuffer() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').isEnabled();
        Integer bufferSize = FeatureFlagLogger.getBufferSize();
        Test.stopTest();
        System.assertEquals(1, bufferSize, 'Non-silent evaluation should buffer one log entry');
    }

    // ─── whenEnabled / whenDisabled / execute ─────────────────────────────

    @IsTest
    static void testWhenEnabledCallbackFires() {
        enableForCurrentUser();
        CallbackCapture capture = new CallbackCapture();

        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .whenEnabled(capture)
            .execute();
        Test.stopTest();

        System.assertEquals(true, capture.wasCalled, 'whenEnabled handler should fire when flag is on');
    }

    @IsTest
    static void testWhenDisabledCallbackFires() {
        // No rules inserted — flag defaults to disabled
        CallbackCapture capture = new CallbackCapture();

        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .whenDisabled(capture)
            .execute();
        Test.stopTest();

        System.assertEquals(true, capture.wasCalled, 'whenDisabled handler should fire when flag is off');
    }

    @IsTest
    static void testExecuteDoesNotFireWrongHandler() {
        enableForCurrentUser();
        CallbackCapture shouldFire   = new CallbackCapture();
        CallbackCapture shouldNotFire = new CallbackCapture();

        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .whenEnabled(shouldFire)
            .whenDisabled(shouldNotFire)
            .execute();
        Test.stopTest();

        System.assertEquals(true,  shouldFire.wasCalled,    'Enabled handler should fire');
        System.assertEquals(false, shouldNotFire.wasCalled, 'Disabled handler should NOT fire when enabled');
    }

    // ─── inScenario ───────────────────────────────────────────────────────

    @IsTest
    static void testInScenarioSetsScenarioOnContext() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .inScenario('Checkout Flow')
            .isEnabled();
        Test.stopTest();
        // The scenario is set — no exception, buffer should have 1 entry
        System.assertEquals(1, FeatureFlagLogger.getBufferSize());
    }

    // ─── Fluent chaining (each method returns FeatureFlagBuilder) ─────────

    @IsTest
    static void testFluentChainReturnsSelf() {
        Test.startTest();
        FeatureFlagBuilder b = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG');
        System.assertNotEquals(null, b.forUser(UserInfo.getUserId()));
        System.assertNotEquals(null, b.withAttribute('k', 'v'));
        System.assertNotEquals(null, b.withAttributes(new Map<String, Object>{ 'x' => 1 }));
        System.assertNotEquals(null, b.fallback(false));
        System.assertNotEquals(null, b.silent());
        System.assertNotEquals(null, b.inScenario('test'));
        Test.stopTest();
    }

    // ─── evaluate returns full result ─────────────────────────────────────

    @IsTest
    static void testEvaluateReturnsFullResult() {
        enableForCurrentUser();
        Test.startTest();
        FeatureFlagResult result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').evaluate();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isEnabled);
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason);
    }

    // ─── Test helper ─────────────────────────────────────────────────────

    private class CallbackCapture implements FeatureFlagHandler {
        public Boolean wasCalled = false;
        public void handle() {
            wasCalled = true;
        }
    }
}
