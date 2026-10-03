public class FeatureFlagHygieneJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        // Use config for threshold — default to 30 days if not configured
        Integer staleThreshold = 30;
        try {
            FlipSwitch_Config__mdt config = [
                SELECT Stale_Flag_Threshold_Days__c FROM FlipSwitch_Config__mdt
                LIMIT 1
            ];
            if (config.Stale_Flag_Threshold_Days__c != null) {
                staleThreshold = Integer.valueOf(config.Stale_Flag_Threshold_Days__c);
            }
        } catch (Exception e) {
            // No config or field not queryable — use default
        }

        Date staleDate = Date.today().addDays(-staleThreshold);

        // Find stale metric records
        List<FlipSwitch_Metric__c> staleMetrics = [
            SELECT Flag_Key__c
            FROM FlipSwitch_Metric__c
            WHERE Last_Evaluated_Date__c < :staleDate
                AND Last_Evaluated_Date__c != null
        ];

        for (FlipSwitch_Metric__c metric : staleMetrics) {
            sendHygieneNotification(metric.Flag_Key__c,
                'Flag has not been evaluated in ' + staleThreshold + ' days.');
        }

        // Check variant weight imbalances (sum != 100)
        List<AggregateResult> variants = [
            SELECT Flag_Key__c flagKey, SUM(Weight__c) totalWeight
            FROM FlipSwitch_Variant__c
            GROUP BY Flag_Key__c
            HAVING SUM(Weight__c) != 100
        ];
        for (AggregateResult ar : variants) {
            sendHygieneNotification((String) ar.get('flagKey'),
                'Variant weights do not sum to 100. Current total: ' + ar.get('totalWeight'));
        }
    }

    private void sendHygieneNotification(String flagKey, String body) {
        try {
            CustomNotificationType notifType = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'FlipSwitch_Hygiene_Alert'
                LIMIT 1
            ];
            Messaging.CustomNotification notif = new Messaging.CustomNotification();
            notif.setTitle('FlipSwitch Flag Health: ' + flagKey);
            notif.setBody(body);
            notif.setNotificationTypeId(notifType.Id);
            notif.setTargetId(UserInfo.getUserId());
            notif.send(new Set<String>{ UserInfo.getUserId() });
        } catch (QueryException e) {
            // CustomNotificationType not found — fall back to debug log
            System.debug(LoggingLevel.WARN,
                'FlipSwitch hygiene: CustomNotificationType FlipSwitch_Hygiene_Alert not found. ' +
                'Flag: ' + flagKey + '. ' + body);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'FlipSwitch hygiene notification failed: ' + e.getMessage());
        }
    }
}
