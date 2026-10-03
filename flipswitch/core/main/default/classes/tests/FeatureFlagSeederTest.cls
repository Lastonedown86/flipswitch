@IsTest
private class FeatureFlagSeederTest {

    @IsTest
    static void testSeedCreatesRegistryRecords() {
        Test.startTest();
        FeatureFlagSeeder.seed();
        Test.stopTest();

        // Verify registry records were created for the 6 flags
        List<FlipSwitch_Flag_Registry__c> records = [
            SELECT Flag_Key__c
            FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c IN (
                'NEW_CHECKOUT_FLOW',
                'DARK_MODE',
                'AI_RECOMMENDATIONS',
                'ASYNC_PROCESSING_V2',
                'HOLIDAY_BANNER',
                'BETA_SEARCH'
            )
        ];
        System.assertEquals(6, records.size(), 'seed() should create 6 registry records');
    }

    @IsTest
    static void testSeedIsIdempotent() {
        Test.startTest();
        FeatureFlagSeeder.seed();
        // Call again — should not throw or create duplicates
        FeatureFlagSeeder.seed();
        Test.stopTest();

        List<FlipSwitch_Flag_Registry__c> records = [
            SELECT Flag_Key__c
            FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c IN (
                'NEW_CHECKOUT_FLOW',
                'DARK_MODE',
                'AI_RECOMMENDATIONS',
                'ASYNC_PROCESSING_V2',
                'HOLIDAY_BANNER',
                'BETA_SEARCH'
            )
        ];
        System.assertEquals(6, records.size(), 'seed() called twice should still have exactly 6 records (idempotent)');
    }
}
