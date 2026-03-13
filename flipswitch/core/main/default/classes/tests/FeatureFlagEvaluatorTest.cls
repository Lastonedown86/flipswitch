@IsTest
private class FeatureFlagEvaluatorTest {

    // ─── Test data helpers ────────────────────────────────────────────────

    private static FlipSwitch_Rule__c makeRule(
        String flagKey, String ruleType, String ruleValue, Integer priority
    ) {
        return new FlipSwitch_Rule__c(
            Name                = 'Test Rule',
            Flag_Key__c = flagKey,
            Rule_Type__c        = ruleType,
            Rule_Value__c       = ruleValue,
            Priority__c         = priority,
            Is_Active__c        = true
        );
    }

    private static FeatureFlagContext makeCtx() {
        return FeatureFlagContext.forRunningUser();
    }

    // ─── Kill switch — CMDT Is_Active__c = false ─────────────────────────

    @IsTest
    static void testKillSwitchDisabledFlagReturnsDisabled() {
        // The SAMPLE_BOOLEAN_FLAG CMDT record has Is_Active__c = true.
        // We test the kill switch rule path instead (runtime kill switch).
        FlipSwitch_Rule__c killRule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Kill_Switch', null, 1
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ killRule }
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled, 'Kill switch rule should disable flag');
        System.assertEquals(FeatureFlagResult.REASON_KILL_SWITCH, result.reason);
    }

    // ─── Expiration ───────────────────────────────────────────────────────

    @IsTest
    static void testExpiredFlagReturnsDisabled() {
        // We cannot modify CMDT in test context, so test expiration via a
        // custom rule with End_Date__c in the past — constructed in memory
        FlipSwitch_Rule__c expiredRule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User',
            String.valueOf(UserInfo.getUserId()), 10
        );
        expiredRule.End_Date__c = Datetime.now().addMinutes(-1);

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ expiredRule }
        );
        Test.stopTest();

        // Expired rule should not match; flag returns default
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'Expired rule should be skipped, result should be DEFAULT');
    }

    // ─── User rule matching ───────────────────────────────────────────────

    @IsTest
    static void testUserRuleMatchReturnsEnabled() {
        String userId = String.valueOf(UserInfo.getUserId());
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User', userId, 10
        );
        rule.Variant_Value__c = 'treatment';

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled);
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason);
        System.assertEquals('treatment', result.variant);
    }

    @IsTest
    static void testUserRuleNoMatchReturnsDefault() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User', '005000000000001AAA', 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason);
    }

    // ─── Profile rule matching ─────────────────────────────────────────────

    @IsTest
    static void testProfileRuleMatch() {
        Id profileId = UserInfo.getProfileId();
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Profile', String.valueOf(profileId), 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled);
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason);
    }

    // ─── Percentage rule ──────────────────────────────────────────────────

    @IsTest
    static void testPercentageRuleConsistency() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Percentage', '50', 10
        );

        Id userId = UserInfo.getUserId();
        FeatureFlagContext ctx = FeatureFlagContext.forUser(userId);
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        List<FlipSwitch_Rule__c> rules = new List<FlipSwitch_Rule__c>{ rule };

        Test.startTest();
        FeatureFlagResult first = FeatureFlagEvaluator.evaluate('SAMPLE_BOOLEAN_FLAG', ctx, rules);
        for (Integer i = 0; i < 9; i++) {
            FeatureFlagResult next = FeatureFlagEvaluator.evaluate('SAMPLE_BOOLEAN_FLAG', ctx, rules);
            System.assertEquals(first.isEnabled, next.isEnabled,
                'Percentage rule must produce consistent result for same user');
        }
        Test.stopTest();
    }

    @IsTest
    static void testPercentage100EnablesEveryone() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Percentage', '100', 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled,
            '100% rollout should enable for all users');
    }

    @IsTest
    static void testPercentage0DisablesEveryone() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Percentage', '0', 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled,
            '0% rollout should disable for all users');
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            '0% percentage rule never matches; falls through to DEFAULT');
    }

    // ─── Segment matching ─────────────────────────────────────────────────

    @IsTest
    static void testSegmentRuleMatch() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Segment',
            '{"region":"US","tier":"Enterprise"}', 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withAttribute('region', 'US')
           .withAttribute('tier', 'Enterprise')
           .withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled);
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason);
    }

    @IsTest
    static void testSegmentRulePartialMatchFails() {
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Segment',
            '{"region":"US","tier":"Enterprise"}', 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withAttribute('region', 'US') // tier missing
           .withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'Partial segment match should not trigger rule');
    }

    // ─── Rule priority ordering ───────────────────────────────────────────

    @IsTest
    static void testLowerPriorityNumberWins() {
        String userId = String.valueOf(UserInfo.getUserId());

        // Priority 5 — should win
        FlipSwitch_Rule__c highPriority = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User', userId, 5
        );
        highPriority.Variant_Value__c = 'high_priority';

        // Priority 20 — should lose
        FlipSwitch_Rule__c lowPriority = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User', userId, 20
        );
        lowPriority.Variant_Value__c = 'low_priority';

        // Pass in priority order (ASC) as the evaluator would return from SOQL
        List<FlipSwitch_Rule__c> rules = new List<FlipSwitch_Rule__c>{ highPriority, lowPriority };

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate('SAMPLE_BOOLEAN_FLAG', ctx, rules);
        Test.stopTest();

        System.assertEquals('high_priority', result.variant,
            'Lower priority number (5) should win over priority 20');
    }

    // ─── No rules — default ───────────────────────────────────────────────

    @IsTest
    static void testNoRulesReturnsDefault() {
        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        // Pass empty rules list
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason);
    }

    // ─── Circuit breaker ──────────────────────────────────────────────────

    @IsTest
    static void testUnknownFlagKeyReturnsDisabledNotException() {
        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('DOES_NOT_EXIST_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'DOES_NOT_EXIST_FLAG', ctx, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Circuit breaker must return a result, not null');
        System.assertEquals(false, result.isEnabled, 'Unknown flags should default to disabled');
    }

    // ─── QA Override ─────────────────────────────────────────────────────

    @IsTest
    static void testQAOverrideEnableAll() {
        FlipSwitch_Settings__c settings = new FlipSwitch_Settings__c();
        settings.Override_All_Flags__c = 'Enable_All';
        settings.Is_Logging_Enabled__c = true;
        upsert settings;

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled, 'Enable_All override should force all flags on');
        System.assertEquals(FeatureFlagResult.REASON_QA_OVERRIDE, result.reason);
    }

    @IsTest
    static void testQAOverrideDisableAll() {
        FlipSwitch_Settings__c settings = new FlipSwitch_Settings__c();
        settings.Override_All_Flags__c = 'Disable_All';
        settings.Is_Logging_Enabled__c = true;
        upsert settings;

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled, 'Disable_All override should force all flags off');
        System.assertEquals(FeatureFlagResult.REASON_QA_OVERRIDE, result.reason);
    }

    // ─── Batch rule loading ───────────────────────────────────────────────

    @IsTest
    static void testLoadRulesForFlagsReturnsAllRules() {
        insert makeRule('SAMPLE_BOOLEAN_FLAG', 'Percentage', '50', 10);

        Test.startTest();
        List<FlipSwitch_Rule__c> rules = FeatureFlagEvaluator.loadRulesForFlags(
            new Set<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        );
        Test.stopTest();

        System.assert(!rules.isEmpty(), 'Should return at least one rule');
        for (FlipSwitch_Rule__c rule : rules) {
            System.assertEquals('SAMPLE_BOOLEAN_FLAG', rule.Flag_Key__c);
        }
    }
}
