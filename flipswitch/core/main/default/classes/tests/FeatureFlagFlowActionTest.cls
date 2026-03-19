@IsTest
private class FeatureFlagFlowActionTest {

    @IsTest
    static void testSingleFlagEvaluation() {
        FeatureFlagFlowAction.FlowInput input = new FeatureFlagFlowAction.FlowInput();
        input.flagKey = 'SAMPLE_BOOLEAN_FLAG';

        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs =
            FeatureFlagFlowAction.evaluate(new List<FeatureFlagFlowAction.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output');
        System.assertNotEquals(null, outputs[0].isEnabled, 'isEnabled should not be null');
        System.assertNotEquals(null, outputs[0].reason, 'reason should not be null');
    }

    @IsTest
    static void testBulkFlagEvaluation() {
        List<FeatureFlagFlowAction.FlowInput> inputs = new List<FeatureFlagFlowAction.FlowInput>();
        for (Integer i = 0; i < 20; i++) {
            FeatureFlagFlowAction.FlowInput input = new FeatureFlagFlowAction.FlowInput();
            input.flagKey = 'SAMPLE_BOOLEAN_FLAG';
            inputs.add(input);
        }

        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs = FeatureFlagFlowAction.evaluate(inputs);
        Test.stopTest();

        System.assertEquals(20, outputs.size(), 'Output count must match input count');
        for (FeatureFlagFlowAction.FlowOutput output : outputs) {
            System.assertNotEquals(null, output.isEnabled, 'Each output isEnabled should not be null');
        }
    }

    @IsTest
    static void testNullUserIdDefaultsToRunningUser() {
        FeatureFlagFlowAction.FlowInput input = new FeatureFlagFlowAction.FlowInput();
        input.flagKey = 'SAMPLE_BOOLEAN_FLAG';
        input.userId  = null; // Should default to running user

        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs =
            FeatureFlagFlowAction.evaluate(new List<FeatureFlagFlowAction.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output');
        System.assertNotEquals(null, outputs[0].isEnabled, 'isEnabled should not be null');
    }

    @IsTest
    static void testExplicitUserId() {
        Id userId = UserInfo.getUserId();

        // Add a rule for this user
        insert new FlipSwitch_Rule__c(
            Name                = 'Flow Action User Rule',
            Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'User',
            Rule_Value__c       = String.valueOf(userId),
            Priority__c         = 10,
            Is_Active__c        = true
        );

        FeatureFlagFlowAction.FlowInput input = new FeatureFlagFlowAction.FlowInput();
        input.flagKey = 'SAMPLE_BOOLEAN_FLAG';
        input.userId  = String.valueOf(userId);

        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs =
            FeatureFlagFlowAction.evaluate(new List<FeatureFlagFlowAction.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].isEnabled, 'User rule should enable flag for specified user');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, outputs[0].reason, 'Reason should be RULE_MATCH for matched user rule');
    }

    @IsTest
    static void testBlankFlagKeyReturnsError() {
        FeatureFlagFlowAction.FlowInput input = new FeatureFlagFlowAction.FlowInput();
        input.flagKey = '';

        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs =
            FeatureFlagFlowAction.evaluate(new List<FeatureFlagFlowAction.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output');
        System.assertEquals(false, outputs[0].isEnabled, 'Blank flag key should return disabled');
        System.assertEquals(FeatureFlagResult.REASON_ERROR, outputs[0].reason, 'Blank flag key should return ERROR reason');
    }

    @IsTest
    static void testEmptyInputListReturnsEmptyOutput() {
        Test.startTest();
        List<FeatureFlagFlowAction.FlowOutput> outputs =
            FeatureFlagFlowAction.evaluate(new List<FeatureFlagFlowAction.FlowInput>());
        Test.stopTest();
        System.assertEquals(0, outputs.size(), 'Empty input should return empty output');
    }
}
