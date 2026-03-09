/**
 * @description Scheduled Apex job that deactivates expired feature flag rules daily.
 *
 *              Schedule via anonymous Apex:
 *              System.schedule('FlipSwitch Expiration Job', '0 0 0 * * ?',
 *                  new FeatureFlagExpirationJob());
 *
 *              Or use the helper script: scripts/apex/schedule-expiration-job.apex
 *
 *              Behaviour:
 *              - Deactivates Feature_Flag_Rule__c records where End_Date__c <= NOW
 *              - Sends email notification to the org's default system admin
 *              - Invalidates the Platform Cache for affected flags
 */
public class FeatureFlagExpirationJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        Datetime now = Datetime.now();

        // Find active rules that have passed their End_Date__c
        List<Feature_Flag_Rule__c> expiredRules = [
            SELECT Id, Name, Feature_Flag_Key__c, End_Date__c
            FROM Feature_Flag_Rule__c
            WHERE Is_Active__c = TRUE
              AND End_Date__c != NULL
              AND End_Date__c <= :now
        ];

        if (expiredRules.isEmpty()) {
            return;
        }

        Set<String> affectedFlagKeys = new Set<String>();
        for (Feature_Flag_Rule__c rule : expiredRules) {
            rule.Is_Active__c = false;
            affectedFlagKeys.add(rule.Feature_Flag_Key__c);
        }

        update expiredRules;

        // Invalidate cache for all affected flags
        for (String flagKey : affectedFlagKeys) {
            FeatureFlagCache.removeFlag(flagKey);
        }

        // Send notification
        sendExpirationNotification(expiredRules);
    }

    private void sendExpirationNotification(List<Feature_Flag_Rule__c> expiredRules) {
        try {
            List<String> adminEmails = getAdminEmails();
            if (adminEmails.isEmpty()) {
                return;
            }

            List<String> ruleNames = new List<String>();
            for (Feature_Flag_Rule__c rule : expiredRules) {
                ruleNames.add(rule.Name + ' (' + rule.Feature_Flag_Key__c + ')');
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(adminEmails);
            mail.setSubject('FlipSwitch: ' + expiredRules.size() + ' rule(s) auto-expired');
            mail.setPlainTextBody(
                'The following FlipSwitch targeting rules were automatically deactivated ' +
                'because their End Date has passed:\n\n' +
                String.join(ruleNames, '\n') +
                '\n\nLog in to Salesforce and review these rules in the Feature Flag Admin app.'
            );

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // Notification failure must not prevent rule deactivation
        }
    }

    private List<String> getAdminEmails() {
        List<String> emails = new List<String>();
        List<User> admins = [
            SELECT Email
            FROM User
            WHERE Profile.Name = 'System Administrator'
              AND IsActive = TRUE
            LIMIT 5
        ];
        for (User u : admins) {
            emails.add(u.Email);
        }
        return emails;
    }
}
