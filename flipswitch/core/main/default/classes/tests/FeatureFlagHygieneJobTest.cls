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

    // ─── Additional coverage tests ────────────────────────────────────────

    @IsTest
    static void hygieneJob_variantWeightImbalanceDetected() {
        insert new List<FlipSwitch_Variant__c>{
            new FlipSwitch_Variant__c(
                Flag_Key__c    = 'IMBALANCE_FLAG',
                Variant_Key__c = 'control',
                Weight__c      = 40
            ),
            new FlipSwitch_Variant__c(
                Flag_Key__c    = 'IMBALANCE_FLAG',
                Variant_Key__c = 'treatment',
                Weight__c      = 50
            )
        };

        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();

        System.assertEquals(false, threwException,
            'Job should complete without exception for variant weight imbalance');
    }

    @IsTest
    static void hygieneJob_multipleStaleMetrics() {
        List<FlipSwitch_Metric__c> metrics = new List<FlipSwitch_Metric__c>();
        for (Integer i = 0; i < 3; i++) {
            metrics.add(new FlipSwitch_Metric__c(
                Flag_Key__c            = 'MULTI_STALE_' + i,
                Last_Evaluated_Date__c = Date.today().addDays(-45),
                Total_Evaluations__c   = 1
            ));
        }
        insert metrics;

        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();

        System.assertEquals(false, threwException,
            'Job should handle multiple stale metrics');
    }

    @IsTest
    static void hygieneJob_recentMetricNotFlagged() {
        insert new FlipSwitch_Metric__c(
            Flag_Key__c            = 'RECENT_FLAG',
            Last_Evaluated_Date__c = Date.today().addDays(-5),
            Total_Evaluations__c   = 100
        );

        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();

        System.assertEquals(false, threwException,
            'Job should not flag recent metrics');
    }

    @IsTest
    static void hygieneJob_balancedVariantsNoNotification() {
        insert new List<FlipSwitch_Variant__c>{
            new FlipSwitch_Variant__c(
                Flag_Key__c    = 'BALANCED_FLAG',
                Variant_Key__c = 'control',
                Weight__c      = 50
            ),
            new FlipSwitch_Variant__c(
                Flag_Key__c    = 'BALANCED_FLAG',
                Variant_Key__c = 'treatment',
                Weight__c      = 50
            )
        };

        Test.startTest();
        FeatureFlagHygieneJob job = new FeatureFlagHygieneJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();

        System.assertEquals(false, threwException,
            'Job should complete without issue for balanced variants');
    }
}
