@IsTest
private class FeatureFlagRegistryTest {

    // ─── registerIfNew ────────────────────────────────────────────────────

    @IsTest
    static void testRegisterIfNewCreatesRegistryRecord() {
        Test.startTest();
        FeatureFlagRegistry.registerIfNew('TEST_AUTO_REG');
        Test.stopTest();

        List<FlipSwitch_Flag_Registry__c> regs = [
            SELECT Flag_Key__c, Type__c, Default_Value__c, Is_Active__c,
                   Source__c, First_Seen_Date__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'TEST_AUTO_REG'
        ];
        System.assertEquals(1, regs.size(), 'Should create exactly one registry record');
        FlipSwitch_Flag_Registry__c reg = regs[0];
        System.assertEquals('Boolean', reg.Type__c, 'Type should default to Boolean');
        System.assertEquals('false', reg.Default_Value__c, 'Default value should be false');
        System.assertEquals(false, reg.Is_Active__c, 'Should default to disabled');
        System.assertEquals('Code', reg.Source__c, 'Source should be Code');
        System.assertNotEquals(null, reg.First_Seen_Date__c, 'First seen date should be set');
    }

    @IsTest
    static void testRegisterIfNewDeduplicatesWithinTransaction() {
        Test.startTest();
        FeatureFlagRegistry.registerIfNew('DEDUP_FLAG');
        FeatureFlagRegistry.registerIfNew('DEDUP_FLAG');
        FeatureFlagRegistry.registerIfNew('DEDUP_FLAG');
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'DEDUP_FLAG'
        ];
        System.assertEquals(1, count, 'Deduplication should prevent multiple inserts');
    }

    @IsTest
    static void testRegisterIfNewSkipsBlankKey() {
        Test.startTest();
        FeatureFlagRegistry.registerIfNew('');
        FeatureFlagRegistry.registerIfNew(null);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM FlipSwitch_Flag_Registry__c];
        System.assertEquals(0, count, 'Should not create records for blank keys');
    }

    @IsTest
    static void testRegisterIfNewSkipsExistingRegistryRecord() {
        // Pre-insert a registry record
        insert new FlipSwitch_Flag_Registry__c(
            Name             = 'EXISTING',
            Flag_Key__c      = 'EXISTING_FLAG',
            Type__c          = 'Variant',
            Default_Value__c = 'control',
            Is_Active__c     = true,
            Source__c         = 'Manual'
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FeatureFlagRegistry.registerIfNew('EXISTING_FLAG');
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Type__c, Default_Value__c, Is_Active__c, Source__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'EXISTING_FLAG'
        ];
        System.assertEquals('Variant', reg.Type__c, 'Should not overwrite existing type');
        System.assertEquals(true, reg.Is_Active__c, 'Should not overwrite existing active state');
        System.assertEquals('Manual', reg.Source__c, 'Should not overwrite existing source');
    }

    // ─── registerWithMetadata ─────────────────────────────────────────────

    @IsTest
    static void testRegisterWithMetadataCreatesRichRecord() {
        Test.startTest();
        FeatureFlagRegistry.registerWithMetadata(
            'RICH_FLAG', 'Percentage', '50', 'Release',
            'A/B test for homepage', Date.newInstance(2025, 12, 31)
        );
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Type__c, Default_Value__c, Category__c, Description__c,
                   Expiration_Date__c, Is_Active__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'RICH_FLAG'
        ];
        System.assertEquals('Percentage', reg.Type__c, 'Type should be Percentage');
        System.assertEquals('50', reg.Default_Value__c, 'Default value should be 50');
        System.assertEquals('Release', reg.Category__c, 'Category should be Release');
        System.assertEquals('A/B test for homepage', reg.Description__c, 'Description should match');
        System.assertEquals(Date.newInstance(2025, 12, 31), reg.Expiration_Date__c, 'Expiration should match');
        System.assertEquals(false, reg.Is_Active__c, 'Should default to disabled');
    }

    @IsTest
    static void testRegisterWithMetadataFillNotOverwrite() {
        // Pre-insert a record with partial data
        insert new FlipSwitch_Flag_Registry__c(
            Name             = 'PARTIAL',
            Flag_Key__c      = 'PARTIAL_FLAG',
            Type__c          = 'Boolean',
            Default_Value__c = 'true',
            Is_Active__c     = true,
            Source__c         = 'Code'
            // category + description are null
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FeatureFlagRegistry.registerWithMetadata(
            'PARTIAL_FLAG', 'Variant', 'control', 'Experiment',
            'Fill test', Date.newInstance(2025, 6, 30)
        );
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Type__c, Default_Value__c, Category__c, Description__c,
                   Expiration_Date__c
            FROM   FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'PARTIAL_FLAG'
        ];
        // Pre-existing fields should NOT be overwritten
        System.assertEquals('Boolean', reg.Type__c, 'Should not overwrite existing type');
        System.assertEquals('true', reg.Default_Value__c, 'Should not overwrite existing default');
        // Blank fields should be filled
        System.assertEquals('Experiment', reg.Category__c, 'Should fill blank category');
        System.assertEquals('Fill test', reg.Description__c, 'Should fill blank description');
        System.assertEquals(Date.newInstance(2025, 6, 30), reg.Expiration_Date__c, 'Should fill blank expiration');
    }

    // ─── Query API ────────────────────────────────────────────────────────

    @IsTest
    static void testGetRegistryFlagReturnsNullWhenNotFound() {
        Test.startTest();
        FlipSwitch_Flag_Registry__c result = FeatureFlagRegistry.getRegistryFlag('NONEXISTENT');
        Test.stopTest();
        System.assertEquals(null, result, 'getRegistryFlag should return null for nonexistent key');
    }

    @IsTest
    static void testGetRegistryFlagReturnsRecord() {
        insert new FlipSwitch_Flag_Registry__c(
            Name        = 'QUERY_TEST',
            Flag_Key__c = 'QUERY_TEST_FLAG',
            Type__c     = 'Boolean',
            Default_Value__c = 'false',
            Is_Active__c = true,
            Source__c    = 'Code'
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FlipSwitch_Flag_Registry__c result = FeatureFlagRegistry.getRegistryFlag('QUERY_TEST_FLAG');
        Test.stopTest();

        System.assertNotEquals(null, result, 'getRegistryFlag should return a record for existing key');
        System.assertEquals('QUERY_TEST_FLAG', result.Flag_Key__c, 'Flag_Key__c should match the queried key');
    }

    @IsTest
    static void testGetRegistryFlagsReturnsSubset() {
        insert new List<FlipSwitch_Flag_Registry__c>{
            new FlipSwitch_Flag_Registry__c(
                Name = 'A', Flag_Key__c = 'FLAG_A', Type__c = 'Boolean',
                Default_Value__c = 'false', Is_Active__c = false, Source__c = 'Code'
            ),
            new FlipSwitch_Flag_Registry__c(
                Name = 'B', Flag_Key__c = 'FLAG_B', Type__c = 'Boolean',
                Default_Value__c = 'false', Is_Active__c = false, Source__c = 'Code'
            ),
            new FlipSwitch_Flag_Registry__c(
                Name = 'C', Flag_Key__c = 'FLAG_C', Type__c = 'Boolean',
                Default_Value__c = 'false', Is_Active__c = false, Source__c = 'Code'
            )
        };
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        Map<String, FlipSwitch_Flag_Registry__c> results =
            FeatureFlagRegistry.getRegistryFlags(new Set<String>{ 'FLAG_A', 'FLAG_C', 'FLAG_Z' });
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return only existing keys');
        System.assert(results.containsKey('FLAG_A'), 'Results should contain FLAG_A');
        System.assert(results.containsKey('FLAG_C'), 'Results should contain FLAG_C');
        System.assert(!results.containsKey('FLAG_Z'), 'Results should not contain non-existent FLAG_Z');
    }

    @IsTest
    static void testGetAllRegistryFlags() {
        insert new List<FlipSwitch_Flag_Registry__c>{
            new FlipSwitch_Flag_Registry__c(
                Name = 'ALL1', Flag_Key__c = 'ALL_FLAG_1', Type__c = 'Boolean',
                Default_Value__c = 'false', Is_Active__c = false, Source__c = 'Code'
            ),
            new FlipSwitch_Flag_Registry__c(
                Name = 'ALL2', Flag_Key__c = 'ALL_FLAG_2', Type__c = 'Boolean',
                Default_Value__c = 'false', Is_Active__c = false, Source__c = 'Code'
            )
        };
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        List<FlipSwitch_Flag_Registry__c> all = FeatureFlagRegistry.getAllRegistryFlags();
        Test.stopTest();

        System.assert(all.size() >= 2, 'Should return at least the inserted records');
    }

    // ─── Promotion API ────────────────────────────────────────────────────

    @IsTest
    static void testPromoteFlagSetsIsPromoted() {
        insert new FlipSwitch_Flag_Registry__c(
            Name        = 'PROMO',
            Flag_Key__c = 'PROMO_FLAG',
            Type__c     = 'Boolean',
            Default_Value__c = 'false',
            Is_Active__c = false,
            Source__c    = 'Code',
            Is_Promoted__c = false
        );
        FeatureFlagRegistry.clearCache();

        Test.startTest();
        FeatureFlagRegistry.promoteFlag('PROMO_FLAG');
        Test.stopTest();

        FlipSwitch_Flag_Registry__c reg = [
            SELECT Is_Promoted__c FROM FlipSwitch_Flag_Registry__c
            WHERE  Flag_Key__c = 'PROMO_FLAG'
        ];
        System.assertEquals(true, reg.Is_Promoted__c, 'Should mark as promoted');
    }

    @IsTest
    static void testPromoteFlagNoOpWhenNotFound() {
        Test.startTest();
        FeatureFlagRegistry.promoteFlag('NONEXISTENT_PROMO');
        Test.stopTest();
        System.assert(true, 'promoteFlag should not throw when flag key is not found');
    }

    // ─── Cache management ─────────────────────────────────────────────────

    @IsTest
    static void testClearCacheInvalidates() {
        insert new FlipSwitch_Flag_Registry__c(
            Name        = 'CACHE1',
            Flag_Key__c = 'CACHE_FLAG_1',
            Type__c     = 'Boolean',
            Default_Value__c = 'false',
            Is_Active__c = false,
            Source__c    = 'Code'
        );
        FeatureFlagRegistry.clearCache();

        // Prime the cache
        FlipSwitch_Flag_Registry__c before = FeatureFlagRegistry.getRegistryFlag('CACHE_FLAG_1');
        System.assertNotEquals(null, before, 'Cached query should return the record');

        // Insert a second record behind the scenes
        insert new FlipSwitch_Flag_Registry__c(
            Name        = 'CACHE2',
            Flag_Key__c = 'CACHE_FLAG_2',
            Type__c     = 'Boolean',
            Default_Value__c = 'false',
            Is_Active__c = false,
            Source__c    = 'Code'
        );

        // Cache still has stale data
        System.assertEquals(null, FeatureFlagRegistry.getRegistryFlag('CACHE_FLAG_2'), 'Stale cache should not contain newly inserted record');

        // Clear and re-query
        FeatureFlagRegistry.clearCache();
        FlipSwitch_Flag_Registry__c after = FeatureFlagRegistry.getRegistryFlag('CACHE_FLAG_2');
        System.assertNotEquals(null, after, 'After clearCache, new record should be found');
    }
}
