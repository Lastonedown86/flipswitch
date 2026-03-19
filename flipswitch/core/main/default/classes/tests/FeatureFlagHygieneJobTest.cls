@IsTest
private class FeatureFlagHygieneJobTest {

    @IsTest
    static void hygieneJob_completesWithoutExceptionForStaleMetric() {
        // Insert a Metric record stale by 31 days
        FlipSwitch_Metric__c metric = new FlipSwitch_Metric__c(
            Flag_Key__c = 'STALE_FLAG_TEST',
            Last_Evaluated_Date__c = Date.today().addDays(-31),
            Total_Evaluations__c = 5
        );
        insert metric;

        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
            System.debug('Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(false, threwException, 'Job should complete without exception for stale flag');
        System.assertEquals(1, [SELECT COUNT() FROM FlipSwitch_Metric__c WHERE Flag_Key__c = 'STALE_FLAG_TEST'],
            'Stale metric record should still exist after job run (job is read-only on metrics)');
    }

    @IsTest
    static void hygieneJob_doesNotThrowWhenNoStaleFlags() {
        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();

        System.assertEquals(false, threwException, 'Job should not throw when there are no stale flags');
    }
}
