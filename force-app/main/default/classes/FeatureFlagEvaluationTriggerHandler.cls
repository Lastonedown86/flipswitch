/**
 * @description Handler for the Feature_Flag_Evaluation__e platform event trigger.
 *
 *              Aggregates evaluation counts into Feature_Flag_Metric__c records.
 *              Uses an upsert on Flag_Key__c (external ID) to update-or-create
 *              the metric for each flag.
 */
public inherited sharing class FeatureFlagEvaluationTriggerHandler {

    public static void handleEvaluationEvents(List<Feature_Flag_Evaluation__e> events) {
        // Accumulate counts per flag key
        Map<String, Integer> evalCounts  = new Map<String, Integer>();
        Map<String, Set<String>> userSets = new Map<String, Set<String>>();

        for (Feature_Flag_Evaluation__e event : events) {
            if (String.isBlank(event.Flag_Key__c)) continue;

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

        if (evalCounts.isEmpty()) return;

        // Load existing metrics for upsert
        Map<String, Feature_Flag_Metric__c> existingMetrics = new Map<String, Feature_Flag_Metric__c>();
        for (Feature_Flag_Metric__c m : [
            SELECT Id, Flag_Key__c, Evaluation_Count__c, Unique_Users__c, Last_Evaluated__c
            FROM Feature_Flag_Metric__c
            WHERE Flag_Key__c IN :evalCounts.keySet()
        ]) {
            existingMetrics.put(m.Flag_Key__c, m);
        }

        List<Feature_Flag_Metric__c> toUpsert = new List<Feature_Flag_Metric__c>();
        Datetime now = Datetime.now();

        for (String key : evalCounts.keySet()) {
            Feature_Flag_Metric__c metric = existingMetrics.containsKey(key)
                ? existingMetrics.get(key)
                : new Feature_Flag_Metric__c(
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
