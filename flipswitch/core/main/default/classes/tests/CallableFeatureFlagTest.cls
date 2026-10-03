@IsTest
private class CallableFeatureFlagTest {

    private static System.Callable getInstance() {
        return new CallableFeatureFlag();
    }

    @IsTest
    static void testIsEnabledAction() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('isEnabled', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG'
        });
        Test.stopTest();
        System.assert(result instanceof Boolean, 'isEnabled should return a Boolean');
    }

    @IsTest
    static void testIsEnabledCaseInsensitive() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('IsEnabled', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG'
        });
        Test.stopTest();
        System.assert(result instanceof Boolean, 'IsEnabled (mixed case) should still work');
    }

    @IsTest
    static void testIsEnabledUpperCase() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('ISENABLED', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG'
        });
        Test.stopTest();
        System.assert(result instanceof Boolean, 'ISENABLED (upper case) should still work');
    }

    @IsTest
    static void testIsEnabledWithUserId() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('isEnabled', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG',
            'userId'  => UserInfo.getUserId()
        });
        Test.stopTest();
        System.assert(result instanceof Boolean, 'isEnabled with userId should return a Boolean');
    }

    @IsTest
    static void testGetVariantAction() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('getVariant', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG'
        });
        Test.stopTest();
        System.assert(result instanceof String, 'getVariant should return a String');
    }

    @IsTest
    static void testGetVariantWithUserId() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('getVariant', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG',
            'userId'  => UserInfo.getUserId()
        });
        Test.stopTest();
        System.assert(result instanceof String, 'getVariant with userId should return a String');
    }

    @IsTest
    static void testEvaluateAction() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('evaluate', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG'
        });
        Test.stopTest();
        System.assert(result instanceof Map<String, Object>, 'evaluate should return a Map');
        Map<String, Object> resultMap = (Map<String, Object>) result;
        System.assert(resultMap.containsKey('isEnabled'), 'evaluate result should contain isEnabled');
        System.assert(resultMap.containsKey('variant'), 'evaluate result should contain variant');
        System.assert(resultMap.containsKey('reason'), 'evaluate result should contain reason');
        System.assert(resultMap.containsKey('payload'), 'evaluate result should contain payload');
    }

    @IsTest
    static void testEvaluateWithUserId() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('evaluate', new Map<String, Object>{
            'flagKey' => 'SAMPLE_BOOLEAN_FLAG',
            'userId'  => UserInfo.getUserId()
        });
        Test.stopTest();
        System.assert(result instanceof Map<String, Object>, 'evaluate with userId should return a Map');
    }

    @IsTest
    static void testSetScenarioAction() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('setScenario', new Map<String, Object>{
            'scenario' => 'checkout_test'
        });
        Test.stopTest();
        System.assertEquals(null, result, 'setScenario should return null');
    }

    @IsTest
    static void testFlushLogsAction() {
        System.Callable ff = getInstance();
        Test.startTest();
        Object result = ff.call('flushLogs', new Map<String, Object>());
        Test.stopTest();
        System.assertEquals(null, result, 'flushLogs should return null');
    }

    @IsTest
    static void testUnknownActionThrowsException() {
        System.Callable ff = getInstance();
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ff.call('unknownAction', new Map<String, Object>());
        } catch (FeatureFlagException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('unknownAction'),
                'Exception message should contain the unknown action name');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Unknown action should throw FeatureFlagException');
    }
}
