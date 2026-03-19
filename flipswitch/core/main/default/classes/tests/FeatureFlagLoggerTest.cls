@IsTest
private class FeatureFlagLoggerTest {

    @IsTest
    static void testSuspendedSkipsBuffering() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.suspend();

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('SUSPENDED_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);

        Test.startTest();
        FeatureFlagLogger.log(result, ctx);
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'Suspended logger should not buffer events');
        FeatureFlagLogger.resume();
    }

    @IsTest
    static void testResumeAfterSuspendAllowsBuffering() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.suspend();
        FeatureFlagLogger.resume();

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('RESUME_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);

        Test.startTest();
        FeatureFlagLogger.log(result, ctx);
        Test.stopTest();

        System.assertEquals(1, FeatureFlagLogger.getBufferSize(),
            'Resumed logger should buffer events');
    }

    @IsTest
    static void testSynchronousSaveMethodPublishesImmediately() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.setSaveMethod(FeatureFlag.SaveMethod.SYNCHRONOUS);

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('SYNC_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);

        Test.startTest();
        FeatureFlagLogger.log(result, ctx);
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'SYNCHRONOUS mode should publish immediately, not buffer');
    }

    @IsTest
    static void testQueueableSaveMethodEnqueuesOnFlush() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.setSaveMethod(FeatureFlag.SaveMethod.QUEUEABLE);

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('QUEUE_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);

        FeatureFlagLogger.log(result, ctx);
        System.assertEquals(1, FeatureFlagLogger.getBufferSize(),
            'QUEUEABLE mode should buffer first');

        Test.startTest();
        FeatureFlagLogger.flush();
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'Buffer should be cleared after flush');
    }

    @IsTest
    static void testEventBusSaveMethodBuffersAndFlushes() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.setSaveMethod(FeatureFlag.SaveMethod.EVENT_BUS);

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('EB_TEST');
        FeatureFlagResult result = FeatureFlagResult.enabled(null, null, FeatureFlagResult.REASON_DEFAULT);

        FeatureFlagLogger.log(result, ctx);
        System.assertEquals(1, FeatureFlagLogger.getBufferSize());

        Test.startTest();
        FeatureFlagLogger.flush();
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'Buffer should be cleared after flush');
    }

    @IsTest
    static void testFlushEmptyBufferNoOp() {
        FeatureFlagLogger.reset();

        Test.startTest();
        FeatureFlagLogger.flush();
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'Flushing empty buffer should be a no-op');
    }

    @IsTest
    static void testSetScenarioTagsEvents() {
        FeatureFlagLogger.reset();
        FeatureFlagLogger.setScenario('My Scenario');

        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('SCENARIO_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);

        Test.startTest();
        FeatureFlagLogger.log(result, ctx);
        Test.stopTest();

        System.assertEquals(1, FeatureFlagLogger.getBufferSize(),
            'Scenario-tagged event should still be buffered');
    }

    @IsTest
    static void testMultipleEventsBuffered() {
        FeatureFlagLogger.reset();

        for (Integer i = 0; i < 5; i++) {
            FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
            ctx.withFlagKey('MULTI_TEST_' + i);
            FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);
            FeatureFlagLogger.log(result, ctx);
        }

        Test.startTest();
        System.assertEquals(5, FeatureFlagLogger.getBufferSize(),
            'Buffer should accumulate multiple events');
        FeatureFlagLogger.flush();
        Test.stopTest();

        System.assertEquals(0, FeatureFlagLogger.getBufferSize(),
            'Buffer should be cleared after flush');
    }

    @IsTest
    static void testResetClearsAll() {
        FeatureFlagLogger.suspend();
        FeatureFlagLogger.setScenario('Test');
        FeatureFlagLogger.setSaveMethod(FeatureFlag.SaveMethod.QUEUEABLE);

        Test.startTest();
        FeatureFlagLogger.reset();
        Test.stopTest();

        // After reset, logging should work in default EVENT_BUS mode
        FeatureFlagContext ctx = FeatureFlagContext.forRunningUser();
        ctx.withFlagKey('RESET_TEST');
        FeatureFlagResult result = FeatureFlagResult.disabled(FeatureFlagResult.REASON_DEFAULT);
        FeatureFlagLogger.log(result, ctx);
        System.assertEquals(1, FeatureFlagLogger.getBufferSize(),
            'After reset, logger should buffer again');
    }
}
