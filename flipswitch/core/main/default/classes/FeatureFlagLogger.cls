/**
 * @description Async evaluation logging via Platform Events.
 *
 *              NebulaLogger-inspired transaction buffering: evaluations accumulate
 *              in-memory and are flushed as a single EventBus.publish() call,
 *              reducing Platform Event DML operations from N to 1 per transaction.
 *
 *              Respects:
 *              - FlipSwitch_Settings__c.Is_Logging_Enabled__c per user
 *              - FlipSwitch_Config__mdt.Log_Sampling_Rate__c (0–100%)
 *              - FeatureFlagBuilder.silent() to suppress a specific call
 *              - FeatureFlag.SaveMethod for how events are persisted
 */
public inherited sharing class FeatureFlagLogger {

    private static final List<FlipSwitch_Evaluation__e> BUFFER =
        new List<FlipSwitch_Evaluation__e>();

    private static Boolean suspended = false;
    private static String  currentScenario;
    private static FeatureFlag.SaveMethod saveMethod = FeatureFlag.SaveMethod.EVENT_BUS;

    // ─── Public API ───────────────────────────────────────────────────────

    /**
     * @description Buffer an evaluation event. Does nothing when suspended,
     *              logging is disabled, or the sampling rate rejects this call.
     * @param result  The evaluation result to log
     * @param ctx     The evaluation context with user and flag info
     */
    public static void log(FeatureFlagResult result, FeatureFlagContext ctx) {
        if (suspended) {
            return;
        }
        if (!isLoggingEnabled(ctx)) {
            return;
        }
        if (!passesSamplingRate()) {
            return;
        }

        FlipSwitch_Evaluation__e event = new FlipSwitch_Evaluation__e(
            Flag_Key__c          = ctx.flagKey,
            User_Id__c           = String.valueOf(ctx.userId),
            Result__c            = result.variant != null ? result.variant
                                   : String.valueOf(result.isEnabled),
            Evaluation_Reason__c = result.reason,
            Scenario__c          = currentScenario,
            Timestamp__c         = Datetime.now(),
            Context__c           = buildContextJson(ctx)
        );

        if (saveMethod == FeatureFlag.SaveMethod.SYNCHRONOUS) {
            EventBus.publish(event);
        } else {
            BUFFER.add(event);
        }
    }

    /**
     * @description Flush all buffered events as a single publish call.
     *              Called automatically by FeatureFlag.flushEvaluations().
     */
    public static void flush() {
        if (BUFFER.isEmpty()) {
            return;
        }
        if (saveMethod == FeatureFlag.SaveMethod.QUEUEABLE) {
            System.enqueueJob(new FeatureFlagLoggerQueueable(BUFFER.clone()));
        } else {
            EventBus.publish(BUFFER);
        }
        BUFFER.clear();
    }

    /** @description Stop buffering evaluations (performance-sensitive code path). */
    public static void suspend() {
        suspended = true;
    }

    /** @description Resume buffering evaluations. */
    public static void resume() {
        suspended = false;
    }

    /**
     * @description Set the save method for this transaction.
     * @param method  The save method enum value
     */
    public static void setSaveMethod(FeatureFlag.SaveMethod method) {
        saveMethod = method;
    }

    /**
     * @description Set the scenario tag applied to all subsequent log entries.
     * @param scenario  The scenario name
     */
    public static void setScenario(String scenario) {
        currentScenario = scenario;
    }

    /** @description Reset transaction state (useful in tests). */
    @TestVisible
    private static void reset() {
        BUFFER.clear();
        suspended = false;
        currentScenario = null;
        saveMethod = FeatureFlag.SaveMethod.EVENT_BUS;
    }

    /**
     * @description Returns the number of events currently buffered (for tests).
     * @return  Buffer size
     */
    @TestVisible
    private static Integer getBufferSize() {
        return BUFFER.size();
    }

    // ─── Private helpers ──────────────────────────────────────────────────

    private static Boolean isLoggingEnabled(FeatureFlagContext ctx) {
        FlipSwitch_Settings__c settings = FlipSwitch_Settings__c.getInstance(ctx.userId);
        // Hierarchy Custom Settings: getInstance() always returns non-null.
        // If no record was explicitly created (Id is null), default to enabled.
        if (settings == null || settings.Id == null) {
            return true;
        }
        return settings.Is_Logging_Enabled__c;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static Boolean passesSamplingRate() {
        // CMDT is always readable — no CRUD check needed
        List<FlipSwitch_Config__mdt> configs = [
            SELECT Log_Sampling_Rate__c
            FROM FlipSwitch_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (configs.isEmpty() || configs[0].Log_Sampling_Rate__c == null) {
            return true;
        }
        Integer rate = Integer.valueOf(configs[0].Log_Sampling_Rate__c);
        if (rate >= 100) {
            return true;
        }
        if (rate <= 0) {
            return false;
        }
        return (Math.random() * 100) < rate;
    }

    private static String buildContextJson(FeatureFlagContext ctx) {
        Map<String, Object> ctxMap = new Map<String, Object>{
            'userId'     => String.valueOf(ctx.userId),
            'profileId'  => String.valueOf(ctx.profileId),
            'permSets'   => new List<String>(ctx.permissionSetNames),
            'attributes' => ctx.customAttributes
        };
        return JSON.serialize(ctxMap);
    }

    /** @description Queueable context for deferred event publishing. */
    public class FeatureFlagLoggerQueueable implements Queueable {
        private final List<FlipSwitch_Evaluation__e> events;

        /** @description Construct a queueable with the events to publish.
         *  @param events  Platform events to publish
         */
        public FeatureFlagLoggerQueueable(List<FlipSwitch_Evaluation__e> events) {
            this.events = events;
        }

        /** @description Publish buffered events.
         *  @param qc  Queueable context
         */
        public void execute(QueueableContext qc) {
            EventBus.publish(events);
        }
    }
}
