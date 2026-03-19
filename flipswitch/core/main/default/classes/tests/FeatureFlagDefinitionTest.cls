@IsTest
private class FeatureFlagDefinitionTest {

    @IsTest
    static void testDefineAndRegisterCreatesRecord() {
        Test.startTest();
        FeatureFlag.define('DEF_TEST_FLAG')
            .type('Boolean')
            .defaultValue('true')
            .category('UI')
            .description('Test flag for definitions')
            .expiresOn(Date.newInstance(2025, 12, 31))
            .register();
        Test.stopTest();

        List<FlipSwitch_Flag_Registry__c> regs = [
            SELECT Flag_Key__c, Type__c, Default_Value__c, Category__c,
                   Description__c, Expiration_Date__c, Is_Active__c, Source__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'DEF_TEST_FLAG'
        ];
        System.assertEquals(1, regs.size(), 'Should create one registry record');
        FlipSwitch_Flag_Registry__c reg = regs[0];
        System.assertEquals('Boolean', reg.Type__c, 'Type should be Boolean');
        System.assertEquals('true', reg.Default_Value__c, 'Default value should be true');
        System.assertEquals('UI', reg.Category__c, 'Category should be UI');
        System.assertEquals('Test flag for definitions', reg.Description__c, 'Description should match');
        System.assertEquals(Date.newInstance(2025, 12, 31), reg.Expiration_Date__c, 'Expiration should match');
        System.assertEquals(false, reg.Is_Active__c, 'Should default to disabled');
        System.assertEquals('Code', reg.Source__c, 'Source should be Code');
    }

    @IsTest
    static void testDefineWithMinimalFields() {
        Test.startTest();
        FeatureFlag.define('MINIMAL_FLAG')
            .register();
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Type__c, Default_Value__c, Category__c, Description__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'MINIMAL_FLAG'
        ];
        System.assertEquals('Boolean', reg.Type__c, 'Should default to Boolean');
        System.assertEquals('false', reg.Default_Value__c, 'Should default to false');
        System.assertEquals(null, reg.Category__c, 'Category should be null when not set');
        System.assertEquals(null, reg.Description__c, 'Description should be null when not set');
    }

    @IsTest
    static void testDefineFluentChaining() {
        // Ensures all fluent methods return the same builder instance
        FeatureFlagDefinition def = new FeatureFlagDefinition('CHAIN_TEST');
        FeatureFlagDefinition result1 = def.type('Variant');
        FeatureFlagDefinition result2 = def.defaultValue('control');
        FeatureFlagDefinition result3 = def.category('Experiment');
        FeatureFlagDefinition result4 = def.description('Chaining test');
        FeatureFlagDefinition result5 = def.expiresOn(Date.today());

        System.assert(result1 === def, '.type() should return same instance');
        System.assert(result2 === def, '.defaultValue() should return same instance');
        System.assert(result3 === def, '.category() should return same instance');
        System.assert(result4 === def, '.description() should return same instance');
        System.assert(result5 === def, '.expiresOn() should return same instance');
    }

    @IsTest
    static void testDefinePreservesAdminEdits() {
        // Pre-insert a record with admin-set category
        insert new FlipSwitch_Flag_Registry__c(
            Name             = 'ADMIN_EDIT',
            Flag_Key__c      = 'ADMIN_EDIT_FLAG',
            Type__c          = 'Variant',
            Default_Value__c = 'treatment_a',
            Category__c      = 'Admin Category',
            Is_Active__c     = true,
            Source__c         = 'Code'
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FeatureFlag.define('ADMIN_EDIT_FLAG')
            .type('Boolean')            // should NOT overwrite 'Variant'
            .defaultValue('false')       // should NOT overwrite 'treatment_a'
            .category('Dev Category')    // should NOT overwrite 'Admin Category'
            .description('New desc')     // should FILL (was null)
            .register();
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Type__c, Default_Value__c, Category__c, Description__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'ADMIN_EDIT_FLAG'
        ];
        System.assertEquals('Variant', reg.Type__c, 'Should preserve admin type');
        System.assertEquals('treatment_a', reg.Default_Value__c, 'Should preserve admin default');
        System.assertEquals('Admin Category', reg.Category__c, 'Should preserve admin category');
        System.assertEquals('New desc', reg.Description__c, 'Should fill blank description');
    }

    @IsTest
    static void testRegisterOneLinerCreatesRecord() {
        Test.startTest();
        FeatureFlag.register('ONELINER_FLAG');
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'ONELINER_FLAG'
        ];
        System.assertEquals(1, count, 'One-liner register should create a record');
    }

    @IsTest
    static void testDefineFactoryReturnsNonNull() {
        FeatureFlagDefinition def = FeatureFlag.define('FACTORY_TEST');
        System.assertNotEquals(null, def, 'define() should return a non-null builder');
    }
}
