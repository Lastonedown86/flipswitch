@IsTest
private class FeatureFlagInventoryJobTest {

    @IsTest
    static void job_executesWithoutExceptionWhenNoInventoryFlags() {
        // No CMDT records can be inserted in tests — job should silently return when
        // no Inventory flags exist.
        Test.startTest();
        FeatureFlagInventoryJob job = new FeatureFlagInventoryJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
            System.debug('Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(false, threwException, 'Job should complete without exception when no inventory flags');
    }

    @IsTest
    static void job_executesWithoutExceptionWithClaimRecords() {
        // Insert claim records — the job should aggregate them and not throw even when
        // no matching CMDT Inventory flags exist in the test context.
        insert new List<FlipSwitch_Inventory_Claim__c>{
            new FlipSwitch_Inventory_Claim__c(
                Flag_Key__c  = 'TEST_CAPACITY_FLAG',
                User_Id__c   = '005000000000001AAA',
                Claim_Key__c = 'TEST_CAPACITY_FLAG_005000000000001AAA',
                Claimed_At__c = System.now()
            ),
            new FlipSwitch_Inventory_Claim__c(
                Flag_Key__c  = 'TEST_CAPACITY_FLAG',
                User_Id__c   = '005000000000002AAA',
                Claim_Key__c = 'TEST_CAPACITY_FLAG_005000000000002AAA',
                Claimed_At__c = System.now()
            )
        };

        Test.startTest();
        FeatureFlagInventoryJob job = new FeatureFlagInventoryJob();
        Boolean threwException = false;
        try {
            job.execute(null);
        } catch (Exception e) {
            threwException = true;
            System.debug('Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(false, threwException, 'Job should complete without exception with claim records');
    }

    @IsTest
    static void job_canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FlipSwitch Inventory Job',
            '0 0 * * * ?',
            new FeatureFlagInventoryJob()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be schedulable');
    }
}
