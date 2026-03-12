@IsTest
private class FeatureFlagExpirationJobTest {

    @IsTest
    static void testExpiredRulesAreDeactivated() {
        // Insert one expired rule and one still-active rule
        Feature_Flag_Rule__c expired = new Feature_Flag_Rule__c(
            Name                = 'Expired Rule',
            Feature_Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'Percentage',
            Rule_Value__c       = '100',
            Priority__c         = 10,
            Is_Active__c        = true,
            End_Date__c         = Datetime.now().addHours(-1)
        );
        Feature_Flag_Rule__c active = new Feature_Flag_Rule__c(
            Name                = 'Active Rule',
            Feature_Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
            Rule_Type__c        = 'Percentage',
            Rule_Value__c       = '100',
            Priority__c         = 20,
            Is_Active__c        = true,
            End_Date__c         = Datetime.now().addDays(30)
        );
        insert new List<Feature_Flag_Rule__c>{ expired, active };

        Test.startTest();
        new FeatureFlagExpirationJob().execute(null);
        Test.stopTest();

        Feature_Flag_Rule__c expiredRefreshed = [SELECT Is_Active__c FROM Feature_Flag_Rule__c WHERE Id = :expired.Id];
        Feature_Flag_Rule__c activeRefreshed  = [SELECT Is_Active__c FROM Feature_Flag_Rule__c WHERE Id = :active.Id];

        System.assertEquals(false, expiredRefreshed.Is_Active__c, 'Expired rule should be deactivated');
        System.assertEquals(true,  activeRefreshed.Is_Active__c,  'Active rule should remain active');
    }

    @IsTest
    static void testNoExpiredRulesDoesNothing() {
        // No rules at all — should complete without error
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            new FeatureFlagExpirationJob().execute(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, exceptionThrown, 'Job should handle empty state without exceptions');
    }

    @IsTest
    static void testJobCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FlipSwitch Expiration Job',
            '0 0 0 * * ?',
            new FeatureFlagExpirationJob()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should be schedulable');
    }

    @IsTest
    static void testMultipleFlagsExpiredAtOnce() {
        List<Feature_Flag_Rule__c> rules = new List<Feature_Flag_Rule__c>();
        for (Integer i = 0; i < 5; i++) {
            rules.add(new Feature_Flag_Rule__c(
                Name                = 'Expired Rule ' + i,
                Feature_Flag_Key__c = 'SAMPLE_BOOLEAN_FLAG',
                Rule_Type__c        = 'Percentage',
                Rule_Value__c       = '50',
                Priority__c         = i + 10,
                Is_Active__c        = true,
                End_Date__c         = Datetime.now().addMinutes(-10)
            ));
        }
        insert rules;

        Test.startTest();
        new FeatureFlagExpirationJob().execute(null);
        Test.stopTest();

        List<Feature_Flag_Rule__c> deactivated = [
            SELECT Is_Active__c FROM Feature_Flag_Rule__c
            WHERE Id IN :rules AND Is_Active__c = TRUE
        ];
        System.assertEquals(0, deactivated.size(), 'All 5 expired rules should be deactivated');
    }
}
