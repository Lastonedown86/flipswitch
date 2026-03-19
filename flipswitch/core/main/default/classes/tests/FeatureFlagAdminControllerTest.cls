/**
 * @description Tests for FeatureFlagAdminController, focusing on the end-to-end
 *              flow where a code-defined flag (via FeatureFlag.define()) appears
 *              in the admin dashboard with source = 'Code'.
 */
@IsTest
private class FeatureFlagAdminControllerTest {

    // ─── End-to-end: define() → getFlags() ────────────────────────────────

    @IsTest
    static void testCodeDefinedFlagAppearsInDashboard() {
        // Define a flag the way a developer would in production code
        FeatureFlag.define('CHECKOUT_REDESIGN')
            .type('Boolean')
            .defaultValue('false')
            .category('Checkout')
            .description('Enables the redesigned checkout flow')
            .register();
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> flags =
            FeatureFlagAdminController.getFlags(null, null);
        Test.stopTest();

        // Find our code-defined flag in the results
        FeatureFlagAdminController.FlagSummary codeFlag = null;
        for (FeatureFlagAdminController.FlagSummary f : flags) {
            if (f.developerName == 'CHECKOUT_REDESIGN') {
                codeFlag = f;
                break;
            }
        }

        System.assertNotEquals(null, codeFlag, 'Code-defined flag should appear in getFlags()');
        System.assertEquals('Code', codeFlag.source, 'Source should be Code');
        System.assertEquals('Boolean', codeFlag.type, 'Type should match define() call');
        System.assertEquals('false', codeFlag.defaultValue, 'Default value should match');
        System.assertEquals('Checkout', codeFlag.category, 'Category should match');
        System.assertEquals('Enables the redesigned checkout flow', codeFlag.description, 'Description should match');
        System.assertEquals(false, codeFlag.isActive, 'Code-defined flags should default to disabled');
    }

    @IsTest
    static void testCodeDefinedFlagFilteredByCategory() {
        FeatureFlag.define('UI_DARKMODE')
            .type('Boolean')
            .category('UI')
            .description('Dark mode toggle')
            .register();

        FeatureFlag.define('API_RATE_LIMIT')
            .type('Percentage')
            .defaultValue('25')
            .category('Backend')
            .description('Rate limiter rollout')
            .register();

        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> uiFlags =
            FeatureFlagAdminController.getFlags('UI', null);
        List<FeatureFlagAdminController.FlagSummary> backendFlags =
            FeatureFlagAdminController.getFlags('Backend', null);
        Test.stopTest();

        // UI filter should return only the UI flag (among code-defined ones)
        Boolean foundDarkMode = false;
        Boolean foundRateLimit = false;
        for (FeatureFlagAdminController.FlagSummary f : uiFlags) {
            if (f.developerName == 'UI_DARKMODE') { foundDarkMode = true; }
            if (f.developerName == 'API_RATE_LIMIT') { foundRateLimit = true; }
        }
        System.assert(foundDarkMode, 'UI_DARKMODE should appear in UI category filter');
        System.assert(!foundRateLimit, 'API_RATE_LIMIT should NOT appear in UI category filter');

        // Backend filter should return only the backend flag
        foundDarkMode = false;
        foundRateLimit = false;
        for (FeatureFlagAdminController.FlagSummary f : backendFlags) {
            if (f.developerName == 'UI_DARKMODE') { foundDarkMode = true; }
            if (f.developerName == 'API_RATE_LIMIT') { foundRateLimit = true; }
        }
        System.assert(!foundDarkMode, 'UI_DARKMODE should NOT appear in Backend category filter');
        System.assert(foundRateLimit, 'API_RATE_LIMIT should appear in Backend category filter');
    }

    @IsTest
    static void testCodeDefinedFlagFilteredByDisabledStatus() {
        // Code-defined flags default to disabled
        FeatureFlag.define('DISABLED_FLAG')
            .type('Boolean')
            .category('Test')
            .register();
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> disabledFlags =
            FeatureFlagAdminController.getFlags(null, 'disabled');
        List<FeatureFlagAdminController.FlagSummary> activeFlags =
            FeatureFlagAdminController.getFlags(null, 'active');
        Test.stopTest();

        Boolean inDisabled = false;
        Boolean inActive = false;
        for (FeatureFlagAdminController.FlagSummary f : disabledFlags) {
            if (f.developerName == 'DISABLED_FLAG') { inDisabled = true; }
        }
        for (FeatureFlagAdminController.FlagSummary f : activeFlags) {
            if (f.developerName == 'DISABLED_FLAG') { inActive = true; }
        }
        System.assert(inDisabled, 'Code-defined flag should appear in disabled filter');
        System.assert(!inActive, 'Code-defined flag should NOT appear in active filter');
    }

    @IsTest
    static void testRegisterOneLinerAppearsInDashboard() {
        // The simpler register() one-liner should also show up
        FeatureFlag.register('SIMPLE_FLAG');
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> flags =
            FeatureFlagAdminController.getFlags(null, null);
        Test.stopTest();

        FeatureFlagAdminController.FlagSummary found = null;
        for (FeatureFlagAdminController.FlagSummary f : flags) {
            if (f.developerName == 'SIMPLE_FLAG') {
                found = f;
                break;
            }
        }
        System.assertNotEquals(null, found, 'register() one-liner should appear in dashboard');
        System.assertEquals('Code', found.source, 'Source should be Code');
        System.assertEquals('Boolean', found.type, 'Should default to Boolean');
        System.assertEquals('false', found.defaultValue, 'Should default to false');
    }

    @IsTest
    static void testCodeDefinedPercentageFlagShowsRollout() {
        FeatureFlag.define('ROLLOUT_TEST')
            .type('Percentage')
            .defaultValue('75')
            .category('Release')
            .register();
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> flags =
            FeatureFlagAdminController.getFlags(null, null);
        Test.stopTest();

        FeatureFlagAdminController.FlagSummary found = null;
        for (FeatureFlagAdminController.FlagSummary f : flags) {
            if (f.developerName == 'ROLLOUT_TEST') {
                found = f;
                break;
            }
        }
        System.assertNotEquals(null, found, 'Percentage flag should appear');
        System.assertEquals('Percentage', found.type, 'Type should be Percentage');
        System.assertEquals(75, found.rolloutPercent, 'Rollout percent should be parsed from default value');
    }

    @IsTest
    static void testCodeDefinedFlagWithExpiration() {
        Date futureDate = Date.today().addDays(3);
        FeatureFlag.define('EXPIRING_FLAG')
            .type('Boolean')
            .expiresOn(futureDate)
            .register();
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> flags =
            FeatureFlagAdminController.getFlags(null, null);
        Test.stopTest();

        FeatureFlagAdminController.FlagSummary found = null;
        for (FeatureFlagAdminController.FlagSummary f : flags) {
            if (f.developerName == 'EXPIRING_FLAG') {
                found = f;
                break;
            }
        }
        System.assertNotEquals(null, found, 'Expiring flag should appear');
        System.assertEquals(String.valueOf(futureDate), found.expirationDate, 'Expiration date should be set');
        System.assertEquals(true, found.isExpiringSoon, 'Flag expiring in 3 days should be marked as expiring soon');
        System.assertEquals(false, found.isExpired, 'Flag should not yet be expired');
    }

    @IsTest
    static void testMultipleCodeDefinedFlagsAllAppear() {
        FeatureFlag.define('FLAG_ALPHA').category('GroupA').register();
        FeatureFlag.define('FLAG_BETA').category('GroupA').register();
        FeatureFlag.define('FLAG_GAMMA').category('GroupB').register();
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FeatureFlagAdminController.FlagSummary> flags =
            FeatureFlagAdminController.getFlags(null, null);
        Test.stopTest();

        Set<String> foundKeys = new Set<String>();
        for (FeatureFlagAdminController.FlagSummary f : flags) {
            if (f.source == 'Code') {
                foundKeys.add(f.developerName);
            }
        }
        System.assert(foundKeys.contains('FLAG_ALPHA'), 'FLAG_ALPHA should appear');
        System.assert(foundKeys.contains('FLAG_BETA'), 'FLAG_BETA should appear');
        System.assert(foundKeys.contains('FLAG_GAMMA'), 'FLAG_GAMMA should appear');
    }

    // ─── Lookup method tests ─────────────────────────────────────────────────

    @IsTest
    static void testGetProfilesReturnsResults() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.getProfiles();
        System.assertNotEquals(0, options.size(), 'Should return at least one profile');
        // Verify shape
        FeatureFlagAdminController.LookupOption first = options[0];
        System.assertNotEquals(null, first.label, 'Profile label should not be null');
        System.assertNotEquals(null, first.value, 'Profile value should not be null');
    }

    @IsTest
    static void testGetPermissionSetsReturnsResults() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.getPermissionSets();
        // May be empty in minimal scratch orgs but should not error
        System.assertNotEquals(null, options, 'Should return a list');
    }

    @IsTest
    static void testSearchUsersWithTerm() {
        // The running test user should match their own name
        User me = [SELECT Name FROM User WHERE Id = :UserInfo.getUserId()];
        String term = me.Name.length() > 2 ? me.Name.substring(0, 3) : me.Name;
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.searchUsers(term);
        System.assertNotEquals(null, options, 'Should return a list');
    }

    @IsTest
    static void testSearchUsersShortTermReturnsEmpty() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.searchUsers('a');
        System.assertEquals(0, options.size(), 'Short search term should return empty');
    }

    @IsTest
    static void testSearchUsersBlankReturnsEmpty() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.searchUsers('');
        System.assertEquals(0, options.size(), 'Blank search should return empty');
    }

    @IsTest
    static void testSearchAccountsWithTerm() {
        Account a = new Account(Name = 'FlipSwitch Test Acct');
        insert a;
        // SOSL needs Test.setFixedSearchResults in tests
        Test.setFixedSearchResults(new List<Id>{ a.Id });
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.searchAccounts('FlipSwitch');
        System.assertEquals(1, options.size(), 'Should find the test account');
        System.assertEquals('FlipSwitch Test Acct', options[0].label);
    }

    @IsTest
    static void testSearchAccountsBlankReturnsEmpty() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.searchAccounts('');
        System.assertEquals(0, options.size(), 'Blank search should return empty');
    }

    @IsTest
    static void testGetTerritoriesDoesNotThrow() {
        // Territory Management may not be enabled — should gracefully return empty
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.getTerritories();
        System.assertNotEquals(null, options, 'Should return a list (possibly empty)');
    }

    @IsTest
    static void testResolveRuleValuesForProfile() {
        // Resolve the System Administrator profile
        Profile sysAdmin = [SELECT Id, Name FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.resolveRuleValues('Profile', sysAdmin.Id);
        System.assertEquals(1, options.size(), 'Should resolve one profile');
        System.assertEquals('System Administrator', options[0].label);
    }

    @IsTest
    static void testResolveRuleValuesForUser() {
        String userId = UserInfo.getUserId();
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.resolveRuleValues('User', userId);
        System.assertEquals(1, options.size(), 'Should resolve the current user');
    }

    @IsTest
    static void testResolveRuleValuesBlankReturnsEmpty() {
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.resolveRuleValues('User', '');
        System.assertEquals(0, options.size(), 'Blank value should return empty');
    }

    @IsTest
    static void testResolveRuleValuesForAccount() {
        Account a = new Account(Name = 'Resolve Test Acct');
        insert a;
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.resolveRuleValues('Account', a.Id);
        System.assertEquals(1, options.size(), 'Should resolve the account');
        System.assertEquals('Resolve Test Acct', options[0].label);
    }

    @IsTest
    static void testResolveRuleValuesForPermissionSet() {
        // Create a test permission set
        PermissionSet ps = new PermissionSet(
            Name = 'FlipSwitch_Lookup_Test_PS',
            Label = 'FlipSwitch Lookup Test PS'
        );
        insert ps;
        List<FeatureFlagAdminController.LookupOption> options =
            FeatureFlagAdminController.resolveRuleValues('Permission_Set', ps.Name);
        System.assertEquals(1, options.size(), 'Should resolve the permission set');
    }

    // ─── Flag CRUD tests ────────────────────────────────────────────────────

    @IsTest
    static void testCreateRegistryFlag() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey      = 'TEST_CREATE_FLAG';
        input.label        = 'Test Create Flag';
        input.description  = 'A test flag';
        input.type         = 'Boolean';
        input.defaultValue = 'true';
        input.category     = 'Testing';
        input.isActive     = true;
        input.storageTarget = 'Registry';

        Test.startTest();
        FeatureFlagAdminController.FlagCrudResult result =
            FeatureFlagAdminController.createFlag(input);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Create should succeed');
        System.assertEquals(false, result.isAsync, 'Registry create should be synchronous');

        // Verify the registry record exists
        List<FlipSwitch_Flag_Registry__c> regs = [
            SELECT Flag_Key__c, Type__c, Default_Value__c, Category__c, Is_Active__c, Source__c
            FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c = 'TEST_CREATE_FLAG'
        ];
        System.assertEquals(1, regs.size(), 'Registry record should exist');
        System.assertEquals('Boolean', regs[0].Type__c);
        System.assertEquals('true', regs[0].Default_Value__c);
        System.assertEquals('Testing', regs[0].Category__c);
        System.assertEquals(true, regs[0].Is_Active__c);
        System.assertEquals('Manual', regs[0].Source__c);
    }

    @IsTest
    static void testCreateFlagDuplicateKeyThrows() {
        FeatureFlag.define('DUPE_KEY').register();
        FeatureFlagRegistry.clearCache();

        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'DUPE_KEY';
        input.label         = 'Duplicate';
        input.type          = 'Boolean';
        input.defaultValue  = 'false';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        Test.startTest();
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('already exists'), 'Should mention already exists');
        }
        Test.stopTest();
        System.assert(caught, 'Should throw AuraHandledException for duplicate key');
    }

    @IsTest
    static void testCreateFlagInvalidKeyThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = '123_BAD_KEY';
        input.label         = 'Bad Key';
        input.type          = 'Boolean';
        input.defaultValue  = 'false';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        Test.startTest();
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('must start with a letter'), 'Should mention key format');
        }
        Test.stopTest();
        System.assert(caught, 'Should throw for invalid flag key');
    }

    @IsTest
    static void testCreateFlagMissingLabelThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'NO_LABEL';
        input.label         = null;
        input.type          = 'Boolean';
        input.defaultValue  = 'false';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('Label is required'));
        }
        System.assert(caught, 'Should throw for missing label');
    }

    @IsTest
    static void testCreateFlagInvalidTypeThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'BAD_TYPE';
        input.label         = 'Bad Type';
        input.type          = 'InvalidType';
        input.defaultValue  = 'false';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('Boolean, Percentage, or Variant'));
        }
        System.assert(caught, 'Should throw for invalid type');
    }

    @IsTest
    static void testCreateFlagInvalidBooleanDefaultThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'BAD_DEFAULT';
        input.label         = 'Bad Default';
        input.type          = 'Boolean';
        input.defaultValue  = 'yes';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('true" or "false'));
        }
        System.assert(caught, 'Should throw for invalid boolean default');
    }

    @IsTest
    static void testCreateFlagInvalidPercentageDefaultThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'BAD_PCT';
        input.label         = 'Bad Pct';
        input.type          = 'Percentage';
        input.defaultValue  = '150';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        try {
            FeatureFlagAdminController.createFlag(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('between 0 and 100'));
        }
        System.assert(caught, 'Should throw for percentage > 100');
    }

    @IsTest
    static void testUpdateRegistryFlag() {
        // Create via define
        FeatureFlag.define('UPDATE_TEST')
            .type('Boolean')
            .defaultValue('false')
            .category('Original')
            .description('Original description')
            .register();
        FeatureFlagRegistry.clearCache();

        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'UPDATE_TEST';
        input.label         = 'Updated Label';
        input.type          = 'Percentage';
        input.defaultValue  = '50';
        input.category      = 'Updated';
        input.description   = 'Updated description';
        input.isActive      = true;
        input.storageTarget = 'Registry';

        Test.startTest();
        FeatureFlagAdminController.FlagCrudResult result =
            FeatureFlagAdminController.updateFlagDefinition(input);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.isAsync);

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Name, Type__c, Default_Value__c, Category__c, Description__c, Is_Active__c
            FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c = 'UPDATE_TEST'
        ];
        System.assertEquals('Updated Label', reg.Name);
        System.assertEquals('Percentage', reg.Type__c);
        System.assertEquals('50', reg.Default_Value__c);
        System.assertEquals('Updated', reg.Category__c);
        System.assertEquals('Updated description', reg.Description__c);
        System.assertEquals(true, reg.Is_Active__c);
    }

    @IsTest
    static void testUpdateNonexistentFlagThrows() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'DOES_NOT_EXIST';
        input.label         = 'Ghost';
        input.storageTarget = 'Registry';

        Boolean caught = false;
        try {
            FeatureFlagAdminController.updateFlagDefinition(input);
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('not found'));
        }
        System.assert(caught, 'Should throw for nonexistent flag');
    }

    @IsTest
    static void testDeleteRegistryFlagWithCascade() {
        // Create flag
        FeatureFlag.define('DELETE_CASCADE')
            .type('Boolean')
            .category('Test')
            .register();
        FeatureFlagRegistry.clearCache();

        // Activate it so it's ready
        FlipSwitch_Flag_Registry__c reg = [
            SELECT Id, Is_Active__c FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c = 'DELETE_CASCADE'
        ];
        reg.Is_Active__c = true;
        update reg;

        // Create child rules
        insert new FlipSwitch_Rule__c(
            Flag_Key__c = 'DELETE_CASCADE',
            Rule_Type__c = 'User',
            Rule_Value__c = UserInfo.getUserId(),
            Is_Active__c = true,
            Priority__c = 1
        );

        // Create child variant
        insert new FlipSwitch_Variant__c(
            Flag_Key__c = 'DELETE_CASCADE',
            Variant_Key__c = 'treatment',
            Weight__c = 100
        );

        Test.startTest();
        FeatureFlagAdminController.FlagCrudResult result =
            FeatureFlagAdminController.deleteFlag('DELETE_CASCADE', 'Code');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.isAsync);

        // Verify registry record deleted
        System.assertEquals(0, [SELECT COUNT() FROM FlipSwitch_Flag_Registry__c WHERE Flag_Key__c = 'DELETE_CASCADE']);
        // Verify children deleted
        System.assertEquals(0, [SELECT COUNT() FROM FlipSwitch_Rule__c WHERE Flag_Key__c = 'DELETE_CASCADE']);
        System.assertEquals(0, [SELECT COUNT() FROM FlipSwitch_Variant__c WHERE Flag_Key__c = 'DELETE_CASCADE']);
    }

    @IsTest
    static void testDeleteFlagMissingKeyThrows() {
        Boolean caught = false;
        try {
            FeatureFlagAdminController.deleteFlag(null, 'Code');
        } catch (AuraHandledException e) {
            caught = true;
            System.assert(e.getMessage().contains('flagKey is required'));
        }
        System.assert(caught, 'Should throw for null flagKey');
    }

    @IsTest
    static void testCreateCmdtFlagAsync() {
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey       = 'CMDT_CREATE_TEST';
        input.label         = 'CMDT Test';
        input.type          = 'Boolean';
        input.defaultValue  = 'false';
        input.category      = 'Testing';
        input.isActive      = true;
        input.storageTarget = 'CMDT';

        Test.startTest();
        FeatureFlagAdminController.FlagCrudResult result =
            FeatureFlagAdminController.createFlag(input);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(true, result.isAsync, 'CMDT create should be async');
        System.assertNotEquals(null, result.deployJobId, 'Should have a deploy job ID');
    }

    @IsTest
    static void testCreateFlagWithExpirationDate() {
        Date futureDate = Date.today().addDays(30);
        FeatureFlagAdminController.FlagInput input = new FeatureFlagAdminController.FlagInput();
        input.flagKey        = 'EXPIRING_CREATE';
        input.label          = 'Expiring Flag';
        input.type           = 'Boolean';
        input.defaultValue   = 'true';
        input.expirationDate = String.valueOf(futureDate);
        input.isActive       = true;
        input.storageTarget  = 'Registry';

        Test.startTest();
        FeatureFlagAdminController.FlagCrudResult result =
            FeatureFlagAdminController.createFlag(input);
        Test.stopTest();

        System.assertEquals(true, result.success);

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Expiration_Date__c FROM FlipSwitch_Flag_Registry__c
            WHERE Flag_Key__c = 'EXPIRING_CREATE'
        ];
        System.assertEquals(futureDate, reg.Expiration_Date__c);
    }

    @IsTest
    static void testFlagDeployCallbackHandlesSuccess() {
        // Exercise the deploy callback code path
        FeatureFlagAdminController.FlagDeployCallback cb =
            new FeatureFlagAdminController.FlagDeployCallback('TEST_KEY', 'create');

        Metadata.DeployResult dr = new Metadata.DeployResult();
        dr.status = Metadata.DeployStatus.Succeeded;

        // Should not throw
        cb.handleResult(dr, null);
    }

    @IsTest
    static void testFlagDeployCallbackHandlesFailure() {
        FeatureFlagAdminController.FlagDeployCallback cb =
            new FeatureFlagAdminController.FlagDeployCallback('TEST_KEY', 'update');

        Metadata.DeployResult dr = new Metadata.DeployResult();
        dr.status = Metadata.DeployStatus.Failed;

        // Should not throw
        cb.handleResult(dr, null);
    }
}
