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
        System.assertEquals(true, result, 'User rule should enable flag');
    }

    @IsTest
    static void testIsEnabledReturnsFalseWhenNoRules() {
        Test.startTest();
        Boolean result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').isEnabled();
        Test.stopTest();
        // Default_Value__c = 'false' on the CMDT sample record
        System.assertEquals(false, result, 'Flag with no matching rules should return CMDT default (false)');
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

        System.assertEquals('treatment_a', variant, 'Should return the variant value from matching rule');
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

        System.assertEquals(true, result, '.withAttributes should trigger segment rule');
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
        System.assertEquals(1, FeatureFlagLogger.getBufferSize(), 'Scenario should buffer one log entry');
    }

    // ─── Fluent chaining ──────────────────────────────────────────────────

    @IsTest
    static void testFluentChainReturnsSelf() {
        Test.startTest();
        FeatureFlagBuilder b = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG');
        System.assertNotEquals(null, b.forUser(UserInfo.getUserId()), '.forUser() should return builder');
        System.assertNotEquals(null, b.withAttribute('k', 'v'), '.withAttribute() should return builder');
        System.assertNotEquals(null, b.withAttributes(new Map<String, Object>{ 'x' => 1 }), '.withAttributes() should return builder');
        System.assertNotEquals(null, b.fallback(false), '.fallback() should return builder');
        System.assertNotEquals(null, b.silent(), '.silent() should return builder');
        System.assertNotEquals(null, b.inScenario('test'), '.inScenario() should return builder');
        Test.stopTest();
    }

    // ─── evaluate returns full result ─────────────────────────────────────

    @IsTest
    static void testEvaluateReturnsFullResult() {
        enableForCurrentUser();
        Test.startTest();
        FeatureFlagResult result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG').evaluate();
        Test.stopTest();

        System.assertNotEquals(null, result, 'evaluate() should return a non-null result');
        System.assertEquals(true, result.isEnabled, 'Flag with matching user rule should be enabled');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
    }

    // ─── Test helper ─────────────────────────────────────────────────────

    /** @description Test helper to capture callback invocations. */
    private class CallbackCapture implements FeatureFlagHandler {
        public Boolean wasCalled = false;
        public void handle() {
            wasCalled = true;
        }
    }

    // ─── Fallback on NOT_CONFIGURED ───────────────────────────────────────

    @IsTest
    static void testFallbackAppliesToNotConfiguredFlags() {
        Test.startTest();
        Boolean withFallback = FeatureFlag.flag('NONEXISTENT_FOR_FALLBACK')
            .fallback(true)
            .isEnabled();
        Boolean withoutFallback = FeatureFlag.flag('NONEXISTENT_FOR_NOFALLBACK')
            .isEnabled();
        Test.stopTest();

        System.assertEquals(true, withFallback,
            'Fallback(true) should return true for NOT_CONFIGURED flag');
        System.assertEquals(false, withoutFallback,
            'Without fallback, NOT_CONFIGURED flag should return false');
    }

    // ─── Additional coverage tests ────────────────────────────────────────

    @IsTest
    static void testFallbackStringVariant() {
        Test.startTest();
        String variant = FeatureFlag.flag('NONEXISTENT_STRING_FALLBACK')
            .fallback('my_variant')
            .getVariant();
        Test.stopTest();

        System.assertEquals('my_variant', variant,
            'String fallback should return the variant when flag is not configured');
    }

    @IsTest
    static void testExecuteWithNoHandlersDoesNotThrow() {
        Test.startTest();
        FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .execute();
        Test.stopTest();

        System.assert(true, 'execute() with no handlers should complete without error');
    }

    @IsTest
    static void testAllowDmlSetsFlag() {
        Test.startTest();
        FeatureFlagBuilder builder = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .allowDml();
        Test.stopTest();

        System.assertEquals(true, builder.isDmlAllowed(),
            'allowDml() should set DML flag to true');
    }

    @IsTest
    static void testWithAccountSetsAccountId() {
        Account acc = new Account(Name = 'Builder Test Acct');
        insert acc;

        Test.startTest();
        FeatureFlagResult result = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .withAccount(acc.Id)
            .evaluate();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a result with account set');
    }

    @IsTest
    static void testGetPayloadReturnsNull() {
        Test.startTest();
        Map<String, Object> payload = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .getPayload();
        Test.stopTest();

        // Payload is null when no variant payload is configured
        System.assertEquals(null, payload, 'Payload should be null when not configured');
    }

    @IsTest
    static void testFallbackNotAppliedWhenRuleMatchesVariant() {
        insert new FlipSwitch_Rule__c(
            Flag_Key__c      = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c     = 'User',
            Rule_Value__c    = String.valueOf(UserInfo.getUserId()),
            Variant_Value__c = 'treatment',
            Priority__c      = 10,
            Is_Active__c     = true
        );

        Test.startTest();
        String variant = FeatureFlag.flag('SAMPLE_BOOLEAN_FLAG')
            .fallback('control')
            .getVariant();
        Test.stopTest();

        System.assertEquals('treatment', variant,
            'Fallback should not override when a rule matches');
    }
}
