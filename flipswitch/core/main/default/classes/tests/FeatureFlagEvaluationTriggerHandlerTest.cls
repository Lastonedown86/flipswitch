@IsTest
private class FeatureFlagEvaluationTriggerHandlerTest {

    @IsTest
    static void testHandlerCreatesMetricForNewFlag() {
        List<FlipSwitch_Evaluation__e> events = new List<FlipSwitch_Evaluation__e>{
            new FlipSwitch_Evaluation__e(
                Flag_Key__c          = 'SAMPLE_BOOLEAN_FLAG',
                User_Id__c           = UserInfo.getUserId(),
                Result__c            = 'true',
                Evaluation_Reason__c = FeatureFlagResult.REASON_DEFAULT,
                Timestamp__c         = Datetime.now()
            )
        };

        Test.startTest();
        FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(events);
        Test.stopTest();

        List<FlipSwitch_Metric__c> metrics = [
            SELECT Evaluation_Count__c, Unique_Users__c, Last_Evaluated__c
            FROM FlipSwitch_Metric__c
            WHERE Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG'
        ];

        System.assertEquals(1, metrics.size(), 'Should create one metric record');
        System.assertEquals(1, metrics[0].Evaluation_Count__c, 'Evaluation count should be 1');
        System.assertEquals(1, metrics[0].Unique_Users__c, 'Unique user count should be 1');
        System.assertNotEquals(null, metrics[0].Last_Evaluated__c);
    }

    @IsTest
    static void testHandlerIncrementsExistingMetric() {
        // Pre-seed metric
        insert new FlipSwitch_Metric__c(
            Name                = 'SAMPLE_BOOLEAN_FLAG',
            Flag_Key__c         = 'SAMPLE_BOOLEAN_FLAG',
            Evaluation_Count__c = 10,
            Unique_Users__c     = 5
        );

        List<FlipSwitch_Evaluation__e> events = new List<FlipSwitch_Evaluation__e>{
            new FlipSwitch_Evaluation__e(
                Flag_Key__c          = 'SAMPLE_BOOLEAN_FLAG',
                User_Id__c           = UserInfo.getUserId(),
                Result__c            = 'false',
                Evaluation_Reason__c = FeatureFlagResult.REASON_DEFAULT,
                Timestamp__c         = Datetime.now()
            ),
            new FlipSwitch_Evaluation__e(
                Flag_Key__c          = 'SAMPLE_BOOLEAN_FLAG',
                User_Id__c           = UserInfo.getUserId(),
                Result__c            = 'true',
                Evaluation_Reason__c = FeatureFlagResult.REASON_RULE_MATCH,
                Timestamp__c         = Datetime.now()
            )
        };

        Test.startTest();
        FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(events);
        Test.stopTest();

        FlipSwitch_Metric__c updated = [
            SELECT Evaluation_Count__c
            FROM FlipSwitch_Metric__c
            WHERE Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG'
        ];
        System.assertEquals(12, updated.Evaluation_Count__c,
            'Should increment from 10 to 12 after 2 new events');
    }

    @IsTest
    static void testHandlerIgnoresBlankFlagKeys() {
        List<FlipSwitch_Evaluation__e> events = new List<FlipSwitch_Evaluation__e>{
            new FlipSwitch_Evaluation__e(
                Flag_Key__c  = '',
                User_Id__c   = UserInfo.getUserId(),
                Timestamp__c = Datetime.now()
            )
        };

        Test.startTest();
        FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(events);
        Test.stopTest();

        List<FlipSwitch_Metric__c> metrics = [
            SELECT Id FROM FlipSwitch_Metric__c WHERE Flag_Key__c = ''
        ];
        System.assertEquals(0, metrics.size(), 'Blank flag key events should be ignored');
    }

    @IsTest
    static void testHandlerProcessesEmptyListGracefully() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(
                new List<FlipSwitch_Evaluation__e>()
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, exceptionThrown, 'Empty list should not throw');
    }

    @IsTest
    static void testTriggerFiresHandler() {
        // Publish a platform event to cover the trigger itself
        FlipSwitch_Evaluation__e evt = new FlipSwitch_Evaluation__e(
            Flag_Key__c          = 'TRIGGER_COVERAGE_TEST',
            User_Id__c           = UserInfo.getUserId(),
            Result__c            = 'true',
            Evaluation_Reason__c = FeatureFlagResult.REASON_DEFAULT,
            Timestamp__c         = Datetime.now()
        );
        Test.startTest();
        EventBus.publish(evt);
        Test.stopTest();
        // Trigger fires asynchronously after Test.stopTest(); verify metric created
        List<FlipSwitch_Metric__c> metrics = [
            SELECT Evaluation_Count__c FROM FlipSwitch_Metric__c
            WHERE Flag_Key__c = 'TRIGGER_COVERAGE_TEST'
        ];
        System.assertEquals(1, metrics.size(), 'Trigger should have fired and created a metric');
    }
}
