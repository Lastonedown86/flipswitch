/**
 * @description Handler for the FlipSwitch_Evaluation__e platform event trigger.
 *
 *              Aggregates evaluation counts into FlipSwitch_Metric__c records.
 *              Uses an upsert on Flag_Key__c (external ID) to update-or-create
 *              the metric for each flag.
 */
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.StdCyclomaticComplexity, PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public inherited sharing class FeatureFlagEvaluationTriggerHandler {

    /**
     * @description Aggregate platform events into FlipSwitch_Metric__c records.
     * @param events  List of evaluation platform events to process
     */
    public static void handleEvaluationEvents(List<FlipSwitch_Evaluation__e> events) {
        // Accumulate counts per flag key
        Map<String, Integer> evalCounts  = new Map<String, Integer>();
        Map<String, Set<String>> userSets = new Map<String, Set<String>>();

        for (FlipSwitch_Evaluation__e event : events) {
            if (String.isBlank(event.Flag_Key__c)) {
                continue;
            }

            String key = event.Flag_Key__c;

            if (!evalCounts.containsKey(key)) {
                evalCounts.put(key, 0);
                userSets.put(key, new Set<String>());
            }

            evalCounts.put(key, evalCounts.get(key) + 1);

            if (String.isNotBlank(event.User_Id__c)) {
                userSets.get(key).add(event.User_Id__c);
            }
        }

        if (evalCounts.isEmpty()) {
            return;
        }

        // Load existing metrics for upsert
        Map<String, FlipSwitch_Metric__c> existingMetrics = new Map<String, FlipSwitch_Metric__c>();
        for (FlipSwitch_Metric__c m : [
            SELECT Id, Flag_Key__c, Evaluation_Count__c, Unique_Users__c, Last_Evaluated__c
            FROM FlipSwitch_Metric__c
            WHERE Flag_Key__c IN :evalCounts.keySet()
        ]) {
            existingMetrics.put(m.Flag_Key__c, m);
        }

        List<FlipSwitch_Metric__c> toUpsert = new List<FlipSwitch_Metric__c>();
        Datetime now = Datetime.now();

        for (String key : evalCounts.keySet()) {
            FlipSwitch_Metric__c metric = existingMetrics.containsKey(key)
                ? existingMetrics.get(key)
                : new FlipSwitch_Metric__c(
                    Name          = key,
                    Flag_Key__c   = key,
                    Evaluation_Count__c = 0,
                    Unique_Users__c     = 0
                );

            metric.Evaluation_Count__c =
                (metric.Evaluation_Count__c == null ? 0 : metric.Evaluation_Count__c)
                + evalCounts.get(key);
            metric.Unique_Users__c =
                (metric.Unique_Users__c == null ? 0 : metric.Unique_Users__c)
                + userSets.get(key).size();
            metric.Last_Evaluated__c = now;
            toUpsert.add(metric);
        }

        upsert toUpsert Flag_Key__c;
    }
}
