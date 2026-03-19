@IsTest
private class FeatureFlagResultTest {

    @IsTest
    static void testEnabledFactoryWithAllFields() {
        Map<String, Object> payload = new Map<String, Object>{ 'color' => 'blue' };
        FeatureFlagResult r = FeatureFlagResult.enabled('treatment_a', payload, FeatureFlagResult.REASON_RULE_MATCH);
        System.assertEquals(true, r.isEnabled, 'enabled() should set isEnabled to true');
        System.assertEquals('treatment_a', r.variant, 'enabled() should set variant');
        System.assertEquals(payload, r.payload, 'enabled() should set payload');
        System.assertEquals(FeatureFlagResult.REASON_RULE_MATCH, r.reason, 'enabled() should set reason');
    }

    @IsTest
    static void testEnabledFactoryWithNulls() {
        FeatureFlagResult r = FeatureFlagResult.enabled(null, null, FeatureFlagResult.REASON_CACHE_HIT);
        System.assertEquals(true, r.isEnabled, 'enabled() with nulls should still be enabled');
        System.assertEquals(null, r.variant, 'variant should be null when not provided');
        System.assertEquals(null, r.payload, 'payload should be null when not provided');
        System.assertEquals(FeatureFlagResult.REASON_CACHE_HIT, r.reason);
    }

    @IsTest
    static void testDisabledFactory() {
        FeatureFlagResult r = FeatureFlagResult.disabled(FeatureFlagResult.REASON_EMERGENCY_DISABLE);
        System.assertEquals(false, r.isEnabled, 'disabled() should set isEnabled to false');
        System.assertEquals(null, r.variant, 'disabled() should have null variant');
        System.assertEquals(null, r.payload, 'disabled() should have null payload');
        System.assertEquals(FeatureFlagResult.REASON_EMERGENCY_DISABLE, r.reason);
    }

    @IsTest
    static void testFromDefaultTrue() {
        FeatureFlagResult r = FeatureFlagResult.fromDefault('true');
        System.assertEquals(true, r.isEnabled, 'fromDefault("true") should be enabled');
        System.assertEquals(null, r.variant, 'fromDefault("true") should have null variant');
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, r.reason);
    }

    @IsTest
    static void testFromDefaultTrueCaseInsensitive() {
        FeatureFlagResult r = FeatureFlagResult.fromDefault('TRUE');
        System.assertEquals(true, r.isEnabled, 'fromDefault("TRUE") should be enabled (case-insensitive)');
        System.assertEquals(null, r.variant, 'fromDefault("TRUE") should have null variant');
    }

    @IsTest
    static void testFromDefaultFalse() {
        FeatureFlagResult r = FeatureFlagResult.fromDefault('false');
        System.assertEquals(false, r.isEnabled, 'fromDefault("false") should be disabled');
        System.assertEquals(null, r.variant, 'fromDefault("false") should have null variant');
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, r.reason);
    }

    @IsTest
    static void testFromDefaultVariantString() {
        FeatureFlagResult r = FeatureFlagResult.fromDefault('treatment_a');
        System.assertEquals(false, r.isEnabled, 'fromDefault with non-boolean string should be disabled');
        System.assertEquals('treatment_a', r.variant, 'fromDefault should store non-boolean string as variant');
        System.assertEquals(null, r.payload);
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, r.reason);
    }

    @IsTest
    static void testFromDefaultNull() {
        FeatureFlagResult r = FeatureFlagResult.fromDefault(null);
        System.assertEquals(false, r.isEnabled, 'fromDefault(null) should be disabled');
        System.assertEquals(null, r.variant, 'fromDefault(null) should have null variant');
        System.assertEquals(FeatureFlagResult.REASON_DEFAULT, r.reason);
    }

    @IsTest
    static void testReasonConstantsExist() {
        // Compile-time coverage for all reason constants
        System.assertNotEquals(null, FeatureFlagResult.REASON_RULE_MATCH);
        System.assertNotEquals(null, FeatureFlagResult.REASON_DEFAULT);
        System.assertNotEquals(null, FeatureFlagResult.REASON_EMERGENCY_DISABLE);
        System.assertNotEquals(null, FeatureFlagResult.REASON_EXPIRED);
        System.assertNotEquals(null, FeatureFlagResult.REASON_CACHE_HIT);
        System.assertNotEquals(null, FeatureFlagResult.REASON_QA_OVERRIDE);
        System.assertNotEquals(null, FeatureFlagResult.REASON_ERROR);
        System.assertNotEquals(null, FeatureFlagResult.REASON_NOT_CONFIGURED);
    }
}
