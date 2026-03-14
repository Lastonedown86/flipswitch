@IsTest
private class FeatureFlagEvaluatorTest {

    // ─── Test data helpers ────────────────────────────────────────────────

    @SuppressWarnings('PMD.ExcessiveParameterList')
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

    // ─── Emergency disable — CMDT Is_Active__c = false ──────────────────

    @IsTest
    static void testEmergencyDisableDisabledFlagReturnsDisabled() {
        // The SAMPLE_BOOLEAN_FLAG CMDT record has Is_Active__c = true.
        // We test the emergency disable rule path instead (runtime emergency disable).
        FlipSwitch_Rule__c disableRule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Emergency_Disable', null, 1
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ disableRule }
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled, 'Emergency disable rule should disable flag');
        System.assertEquals(FeatureFlagResult.REASON_EMERGENCY_DISABLE, result.reason,
            'Reason should be EMERGENCY_DISABLE');
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

        System.assertEquals(true, result.isEnabled, 'User rule match should enable flag');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
        System.assertEquals('treatment', result.variant, 'Variant should be treatment');
    }

    @IsTest
    static void testUserRuleNoMatchReturnsDefault() {
        // Use a non-matching user Id that differs from the running user
        String nonMatchingUserId = String.valueOf(UserInfo.getUserId()).substring(0, 15) + 'ZZZ';
        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'User', nonMatchingUserId, 10
        );

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'Non-matching user rule should fall through to DEFAULT');
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

        System.assertEquals(true, result.isEnabled, 'Profile rule should enable flag');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
    }

    // ─── Percentage rollout ───────────────────────────────────────────────

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

        System.assertEquals(true, result.isEnabled, 'Segment rule should enable flag');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
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

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'No rules should fall through to DEFAULT');
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
        System.assertEquals(FeatureFlagResult.REASON_QA_OVERRIDE, result.reason,
            'Reason should be QA_OVERRIDE');
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
        System.assertEquals(FeatureFlagResult.REASON_QA_OVERRIDE, result.reason,
            'Reason should be QA_OVERRIDE');
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

    // ─── Code-defined flag (registry integration) ─────────────────────────

    @IsTest
    static void testUnknownFlagReturnsNotConfigured() {
        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('TOTALLY_NEW_CODE_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'TOTALLY_NEW_CODE_FLAG', ctx, null
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled, 'Unknown flag should be disabled');
        System.assertEquals(
            FeatureFlagResult.REASON_NOT_CONFIGURED,
            result.reason,
            'Unknown flag should return NOT_CONFIGURED reason'
        );

        // Should have auto-registered
        List<FlipSwitch_Flag_Registry__c> regs = [
            SELECT Flag_Key__c FROM FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'TOTALLY_NEW_CODE_FLAG'
        ];
        System.assertEquals(1, regs.size(), 'Evaluator should auto-register unknown flags');
    }

    @IsTest
    static void testRegistryFlagActiveEvaluatesNormally() {
        // Pre-insert an active registry flag
        insert new FlipSwitch_Flag_Registry__c(
            Name             = 'ACTIVE_REG',
            Flag_Key__c      = 'ACTIVE_REG_FLAG',
            Type__c          = 'Boolean',
            Default_Value__c = 'true',
            Is_Active__c     = true,
            Source__c         = 'Code'
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.withFlagKey('ACTIVE_REG_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'ACTIVE_REG_FLAG', ctx, null
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled, 'Active registry flag with default=true should be enabled');
    }

    // ─── Account context properties ───────────────────────────────────────

    @IsTest
    static void context_withAccount_setsAccountId() {
        Id mockAccountId = '001000000000001AAA';
        FeatureFlagBuilder builder = FeatureFlag.flag('TEST_FLAG').withAccount(mockAccountId);
        // Access internal context via test-visible getter
        FeatureFlagContext ctx = builder.getContext();
        System.assertEquals(mockAccountId, ctx.accountId, 'accountId should be set from withAccount()');
    }

    // ─── Account rule matching ────────────────────────────────────────────

    @IsTest
    static void evaluator_accountRule_matchesUserUnderTargetAccount() {
        Account acc = new Account(Name = 'Acme Corp');
        insert acc;

        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Account', String.valueOf(acc.Id), 1
        );
        rule.Variant_Value__c = 'true';

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.accountId = acc.Id;
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled, 'User under target account should get true');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
    }

    @IsTest
    static void evaluator_accountRule_skipsNonMatchingAccount() {
        Account target = new Account(Name = 'Target Corp');
        insert target;
        Account other = new Account(Name = 'Other Corp');
        insert other;

        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Account', String.valueOf(target.Id), 1
        );
        rule.Variant_Value__c = 'true';

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.accountId = other.Id;
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'User under different account should fall through to DEFAULT');
    }

    @IsTest
    static void evaluator_accountSegmentRule_matchesOnField() {
        Account acc = new Account(Name = 'Tech Corp', Industry = 'Technology');
        insert acc;

        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Account_Segment', 'Industry:Technology', 1
        );
        rule.Variant_Value__c = 'true';

        Test.startTest();
        FeatureFlagContext ctx = makeCtx();
        ctx.accountId = acc.Id;
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled, 'Account with matching Industry field should get true');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason, 'Reason should be RULE_MATCH');
    }

    @IsTest
    static void context_accountRecord_cachedAfterFirstLookup() {
        // Arrange: create a test Account
        Account acc = new Account(Name = 'Test Org');
        insert acc;

        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.accountId = acc.Id;

        // Act: access accountRecord twice
        SObject r1 = ctx.accountRecord;
        Integer queriesAfterFirst = Limits.getQueries();
        SObject r2 = ctx.accountRecord;
        Integer queriesAfterSecond = Limits.getQueries();

        // Assert: only one SOQL used
        System.assertEquals(queriesAfterFirst, queriesAfterSecond, 'Account record should be cached after first access');
        System.assertEquals(acc.Id, (Id) r1.get('Id'), 'Should return correct account');
    }

    // ─── Territory rule matching ──────────────────────────────────────────

    @IsTest
    static void evaluator_territoryRule_matchesUserInTargetTerritory() {
        String territoryId = '0MV000000000001AAA';

        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Territory', territoryId, 1
        );
        rule.Variant_Value__c = 'true';

        Test.startTest();
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.setTerritoryIds(new List<String>{ territoryId });
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled,
            'User in target territory should get true');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason,
            'Reason should be RULE_MATCH');
    }

    @IsTest
    static void evaluator_territoryRule_skipsNonMatchingTerritory() {
        String targetTerritoryId = '0MV000000000001AAA';
        String userTerritoryId   = '0MV000000000002AAA';

        FlipSwitch_Rule__c rule = makeRule(
            'SAMPLE_BOOLEAN_FLAG', 'Territory', targetTerritoryId, 1
        );
        rule.Variant_Value__c = 'true';

        Test.startTest();
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.setTerritoryIds(new List<String>{ userTerritoryId });
        ctx.withFlagKey('SAMPLE_BOOLEAN_FLAG');
        FeatureFlagResult result = FeatureFlagEvaluator.evaluate(
            'SAMPLE_BOOLEAN_FLAG', ctx, new List<FlipSwitch_Rule__c>{ rule }
        );
        Test.stopTest();

        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'User in a different territory should fall through to DEFAULT');
    }

    // ─── Inventory flag type ──────────────────────────────────────────────

    @IsTest
    static void inventoryFlag_withoutAllowDml_throwsFeatureFlagException() {
        // Context without dmlAllowed — evaluateInventoryDirect should throw
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.dmlAllowed = false;

        Boolean exceptionThrown = false;
        String  exceptionMessage = '';

        Test.startTest();
        try {
            FeatureFlagEvaluator.evaluateInventoryDirect('INV_TEST_FLAG', false, ctx);
        } catch (FeatureFlagException e) {
            exceptionThrown  = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown,
            'Inventory flag without allowDml should throw FeatureFlagException');
        System.assert(exceptionMessage.contains('allowDml'),
            'Exception message should mention allowDml; got: ' + exceptionMessage);
    }

    @IsTest
    static void inventoryFlag_withAllowDml_createsClaimAndReturnsTrue() {
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.dmlAllowed = true;

        Test.startTest();
        FeatureFlagResult result = FeatureFlagEvaluator.evaluateInventoryDirect(
            'INV_CLAIM_FLAG', false, ctx
        );
        Test.stopTest();

        System.assertEquals(true, result.isEnabled,
            'First evaluation of open Inventory flag should return true');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, result.reason,
            'Reason should be RULE_MATCH after successful claim');

        // Verify the claim record was inserted
        List<FlipSwitch_Inventory_Claim__c> claims = [
            SELECT Id, Flag_Key__c, User_Id__c
            FROM FlipSwitch_Inventory_Claim__c
            WHERE Flag_Key__c = 'INV_CLAIM_FLAG'
              AND User_Id__c  = :String.valueOf(UserInfo.getUserId())
        ];
        System.assertEquals(1, claims.size(),
            'Exactly one claim record should be created for the user');
    }

    @IsTest
    static void inventoryFlag_evaluatedTwice_isIdempotent() {
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.dmlAllowed = true;

        Test.startTest();
        // First evaluation — inserts claim
        FeatureFlagResult first = FeatureFlagEvaluator.evaluateInventoryDirect(
            'INV_IDEMPOTENT_FLAG', false, ctx
        );
        // Second evaluation — finds existing claim (cache or SOQL), no duplicate insert
        FeatureFlagResult second = FeatureFlagEvaluator.evaluateInventoryDirect(
            'INV_IDEMPOTENT_FLAG', false, ctx
        );
        Test.stopTest();

        System.assertEquals(true, first.isEnabled,
            'First evaluation should return true');
        System.assertEquals(true, second.isEnabled,
            'Second evaluation should also return true (idempotent)');

        // Only one claim record should exist
        List<FlipSwitch_Inventory_Claim__c> claims = [
            SELECT Id FROM FlipSwitch_Inventory_Claim__c
            WHERE Flag_Key__c = 'INV_IDEMPOTENT_FLAG'
              AND User_Id__c  = :String.valueOf(UserInfo.getUserId())
        ];
        System.assertEquals(1, claims.size(),
            'No duplicate claim records should be created on repeated evaluation');
    }

    @IsTest
    static void inventoryFlag_whenClosed_returnsFalse() {
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        ctx.dmlAllowed = true;

        Test.startTest();
        FeatureFlagResult result = FeatureFlagEvaluator.evaluateInventoryDirect(
            'INV_CLOSED_FLAG', true, ctx
        );
        Test.stopTest();

        System.assertEquals(false, result.isEnabled,
            'Closed Inventory flag should return false when user has no prior claim');
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, result.reason,
            'Reason should be DEFAULT for a closed flag with no existing claim');
    }
}
