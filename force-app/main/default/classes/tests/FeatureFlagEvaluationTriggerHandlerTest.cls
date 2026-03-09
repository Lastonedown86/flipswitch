@IsTest
private class FeatureFlagEvaluationTriggerHandlerTest {

    @IsTest
    static void testHandlerCreatesMetricForNewFlag() {
        List<Feature_Flag_Evaluation__e> events = new List<Feature_Flag_Evaluation__e>{
            new Feature_Flag_Evaluation__e(
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

        List<Feature_Flag_Metric__c> metrics = [
            SELECT Evaluation_Count__c, Unique_Users__c, Last_Evaluated__c
            FROM Feature_Flag_Metric__c
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
        insert new Feature_Flag_Metric__c(
            Name                = 'SAMPLE_BOOLEAN_FLAG',
            Flag_Key__c         = 'SAMPLE_BOOLEAN_FLAG',
            Evaluation_Count__c = 10,
            Unique_Users__c     = 5
        );

        List<Feature_Flag_Evaluation__e> events = new List<Feature_Flag_Evaluation__e>{
            new Feature_Flag_Evaluation__e(
                Flag_Key__c          = 'SAMPLE_BOOLEAN_FLAG',
                User_Id__c           = UserInfo.getUserId(),
                Result__c            = 'false',
                Evaluation_Reason__c = FeatureFlagResult.REASON_DEFAULT,
                Timestamp__c         = Datetime.now()
            ),
            new Feature_Flag_Evaluation__e(
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

        Feature_Flag_Metric__c updated = [
            SELECT Evaluation_Count__c
            FROM Feature_Flag_Metric__c
            WHERE Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG'
        ];
        System.assertEquals(12, updated.Evaluation_Count__c,
            'Should increment from 10 to 12 after 2 new events');
    }

    @IsTest
    static void testHandlerIgnoresBlankFlagKeys() {
        List<Feature_Flag_Evaluation__e> events = new List<Feature_Flag_Evaluation__e>{
            new Feature_Flag_Evaluation__e(
                Flag_Key__c  = '',
                User_Id__c   = UserInfo.getUserId(),
                Timestamp__c = Datetime.now()
            )
        };

        Test.startTest();
        FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(events);
        Test.stopTest();

        List<Feature_Flag_Metric__c> metrics = [
            SELECT Id FROM Feature_Flag_Metric__c WHERE Flag_Key__c = ''
        ];
        System.assertEquals(0, metrics.size(), 'Blank flag key events should be ignored');
    }

    @IsTest
    static void testHandlerProcessesEmptyListGracefully() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(
                new List<Feature_Flag_Evaluation__e>()
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, exceptionThrown, 'Empty list should not throw');
    }
}
