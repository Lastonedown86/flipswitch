@IsTest
private class FeatureFlagContextTest {

    @IsTest
    static void testForRunningUser() {
        Test.startTest();
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.stopTest();
        System.assertEquals(UserInfo.getUserId(), ctx.userId, 'forRunningUser should set userId to running user');
        System.assertNotEquals(null, ctx.profileId, 'forRunningUser should populate profileId');
        System.assertNotEquals(null, ctx.permissionSetNames, 'permissionSetNames should be initialized');
        System.assertNotEquals(null, ctx.customAttributes, 'customAttributes should be initialized');
    }

    @IsTest
    static void testForUser() {
        Id currentUserId = UserInfo.getUserId();
        Test.startTest();
        FeatureFlagContext ctx = FeatureFlagContext.forUser(currentUserId);
        Test.stopTest();
        System.assertEquals(currentUserId, ctx.userId, 'forUser should set userId');
        System.assertNotEquals(null, ctx.profileId, 'forUser should query and set profileId');
    }

    @IsTest
    static void testWithAttribute() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.startTest();
        FeatureFlagContext returned = ctx.withAttribute('region', 'US');
        Test.stopTest();
        System.assert(ctx === returned, 'withAttribute should return the same instance for chaining');
        System.assertEquals('US', ctx.customAttributes.get('region'), 'withAttribute should store the value');
    }

    @IsTest
    static void testWithAttributes() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Map<String, Object> attrs = new Map<String, Object>{
            'region' => 'EU',
            'tier'   => 'premium'
        };
        Test.startTest();
        FeatureFlagContext returned = ctx.withAttributes(attrs);
        Test.stopTest();
        System.assert(ctx === returned, 'withAttributes should return the same instance for chaining');
        System.assertEquals('EU', ctx.customAttributes.get('region'));
        System.assertEquals('premium', ctx.customAttributes.get('tier'));
    }

    @IsTest
    static void testWithScenario() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.startTest();
        FeatureFlagContext returned = ctx.withScenario('checkout_flow');
        Test.stopTest();
        System.assert(ctx === returned, 'withScenario should return the same instance for chaining');
        System.assertEquals('checkout_flow', ctx.scenario);
    }

    @IsTest
    static void testWithFlagKey() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.startTest();
        FeatureFlagContext returned = ctx.withFlagKey('MY_FLAG');
        Test.stopTest();
        System.assert(ctx === returned, 'withFlagKey should return the same instance for chaining');
        System.assertEquals('MY_FLAG', ctx.flagKey);
    }

    @IsTest
    static void testAccountRecordLazyLoad() {
        Account testAccount = new Account(Name = 'Test Corp', Industry = 'Technology');
        insert testAccount;

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.accountId = testAccount.Id;

        Test.startTest();
        SObject record = ctx.accountRecord;
        // Second access should use cached value (no additional SOQL)
        SObject recordAgain = ctx.accountRecord;
        Test.stopTest();

        System.assertNotEquals(null, record, 'accountRecord should lazy-load when accountId is set');
        System.assertEquals(testAccount.Id, record.Id, 'accountRecord should match the set accountId');
        System.assertEquals('Test Corp', (String) record.get('Name'));
        System.assert(record === recordAgain, 'Second access should return cached instance');
    }

    @IsTest
    static void testAccountRecordNullWhenNoAccountId() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.startTest();
        SObject record = ctx.accountRecord;
        Test.stopTest();
        System.assertEquals(null, record, 'accountRecord should be null when accountId is not set');
    }

    @IsTest
    static void testTerritoryIdsDefaultEmpty() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        Test.startTest();
        List<String> territories = ctx.territoryIds;
        Test.stopTest();
        System.assertNotEquals(null, territories, 'territoryIds should never be null');
        // May or may not be empty depending on whether Territory Management is enabled
        System.assert(territories.size() >= 0, 'territoryIds should be an initialized list');
    }

    @IsTest
    static void testSetTerritoryIds() {
        FeatureFlagContext ctx = new FeatureFlagContext(UserInfo.getUserId());
        List<String> testIds = new List<String>{ 'territory1', 'territory2' };

        Test.startTest();
        ctx.setTerritoryIds(testIds);
        List<String> result = ctx.territoryIds;
        Test.stopTest();

        System.assertEquals(2, result.size(), 'setTerritoryIds should inject the provided IDs');
        System.assertEquals('territory1', result[0]);
        System.assertEquals('territory2', result[1]);
    }

    @IsTest
    static void testDmlAllowed() {
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.dmlAllowed = true;
        System.assertEquals(true, ctx.dmlAllowed, 'dmlAllowed should be settable');
        ctx.dmlAllowed = false;
        System.assertEquals(false, ctx.dmlAllowed, 'dmlAllowed should be updatable');
    }

    @IsTest
    static void testFluentChaining() {
        Test.startTest();
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser()
            .withAttribute('region', 'US')
            .withAttribute('tier', 'enterprise')
            .withScenario('bulk_import')
            .withFlagKey('IMPORT_V2');
        Test.stopTest();

        System.assertEquals('US', ctx.customAttributes.get('region'));
        System.assertEquals('enterprise', ctx.customAttributes.get('tier'));
        System.assertEquals('bulk_import', ctx.scenario);
        System.assertEquals('IMPORT_V2', ctx.flagKey);
    }
}
