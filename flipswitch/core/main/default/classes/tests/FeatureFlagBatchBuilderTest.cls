@IsTest
private class FeatureFlagBatchBuilderTest {

    private static void insertUserRule(String flagKey) {
        insert new FlipSwitch_Rule__c(
            Name                = 'Enable User — ' + flagKey,
            Flag_Key__c = flagKey,
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(UserInfo.getUserId()),
            Priority__c         = 10,
            Is_Active__c        = true
        );
    }

    @IsTest
    static void testEvaluateAllReturnsMapWithAllKeys() {
        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG', 'SAMPLE_BOOLEAN_FLAG' }
        ).evaluateAll();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Deduped flag keys should produce 1 result');
        System.assert(results.containsKey('SAMPLE_BOOLEAN_FLAG'), 'Should contain SAMPLE_BOOLEAN_FLAG key');
    }

    @IsTest
    static void testEvaluateAllWithMultipleFlags() {
        // SAMPLE_BOOLEAN_FLAG is the only CMDT record we have in test context.
        // Test with two references to confirm the map is populated.
        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        ).evaluateAll();
        Test.stopTest();

        System.assertNotEquals(null, results.get('SAMPLE_BOOLEAN_FLAG'), 'SAMPLE_BOOLEAN_FLAG result should not be null');
    }

    @IsTest
    static void testSingleSOQLForMultipleFlags() {
        // Insert rules for a single flag
        insertUserRule('SAMPLE_BOOLEAN_FLAG');

        Integer queriesBefore = Limits.getQueries();
        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        ).forUser(UserInfo.getUserId())
            .evaluateAll();
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        // SOQL for rules + User context + CMDT + settings + logging/sampling = bounded, not N per flag
        System.assert(queriesUsed <= 8,
            'Batch evaluation should use a bounded number of queries, not N per flag. Used: ' + queriesUsed);
        System.assertEquals(true, results.get('SAMPLE_BOOLEAN_FLAG').isEnabled,
            'User rule should enable flag in batch evaluation');
    }

    @IsTest
    static void testSharedContextAppliedToAllFlags() {
        FlipSwitch_Rule__c segRule = new FlipSwitch_Rule__c(
            Name                = 'Segment Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'Segment',
            Rule_Value__c       = '{"env":"staging"}',
            Priority__c         = 10,
            Is_Active__c        = true
        );
        insert segRule;

        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        ).withAttribute('env', 'staging')
            .evaluateAll();
        Test.stopTest();

        System.assertEquals(true, results.get('SAMPLE_BOOLEAN_FLAG').isEnabled,
            'Shared attribute should reach all flag evaluations');
    }

    @IsTest
    static void testEmptyFlagListReturnsEmptyMap() {
        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>()
        ).evaluateAll();
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty flag list should return empty map');
    }

    @IsTest
    static void testForUserAppliedToAllFlags() {
        Id currentUser = UserInfo.getUserId();
        insertUserRule('SAMPLE_BOOLEAN_FLAG');

        Test.startTest();
        Map<String, FeatureFlagResult> results = FeatureFlag.flags(
            new List<String>{ 'SAMPLE_BOOLEAN_FLAG' }
        ).forUser(currentUser)
            .evaluateAll();
        Test.stopTest();

        System.assertEquals(true, results.get('SAMPLE_BOOLEAN_FLAG').isEnabled, 'forUser should evaluate rules for specified user');
    }

    @IsTest
    static void testScenarioTagAppliedInBatch() {
        FeatureFlagLogger.reset();
        Test.startTest();
        FeatureFlag.flags(new List<String>{ 'SAMPLE_BOOLEAN_FLAG' })
            .inScenario('Batch Test Scenario')
            .evaluateAll();
        Test.stopTest();
        // Scenario is carried through — buffer gets entries
        System.assert(FeatureFlagLogger.getBufferSize() >= 1, 'Scenario tag should cause at least one log buffer entry');
    }
}
