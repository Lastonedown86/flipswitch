/**
 * @description Scheduled Apex job that closes Inventory-type feature flags when
 *              the number of claims meets or exceeds the configured Capacity__c.
 *
 *              Schedule via anonymous Apex:
 *              System.schedule('FlipSwitch Inventory Job', '0 0 * * * ?',
 *                  new FeatureFlagInventoryJob());
 *
 *              Behaviour:
 *              - Queries all active, non-closed Inventory flags from FlipSwitch_Flag__mdt
 *              - Aggregates FlipSwitch_Inventory_Claim__c records per flag key
 *              - Deploys a CMDT update (Is_Closed__c = true) for any flag at or over capacity
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public inherited sharing class FeatureFlagInventoryJob implements Schedulable {

    /** @description Checks all active Inventory flags and closes any that have reached capacity.
     *  @param sc  Schedulable context (may be null when invoked directly)
     */
    public void execute(SchedulableContext sc) {
        List<FlipSwitch_Flag__mdt> inventoryFlags = [
            SELECT DeveloperName, Capacity__c, Is_Closed__c
            FROM FlipSwitch_Flag__mdt
            WHERE Type__c = 'Inventory'
              AND Is_Closed__c = FALSE
              AND Is_Active__c = TRUE
        ];

        if (inventoryFlags.isEmpty()) {
            return;
        }

        Set<String> flagKeys = new Set<String>();
        for (FlipSwitch_Flag__mdt flag : inventoryFlags) {
            flagKeys.add(flag.DeveloperName);
        }

        List<AggregateResult> counts = [
            SELECT Flag_Key__c flagKey, COUNT(Id) claimCount
            FROM FlipSwitch_Inventory_Claim__c
            WHERE Flag_Key__c IN :flagKeys
            GROUP BY Flag_Key__c
        ];

        Map<String, Integer> claimCountByFlag = new Map<String, Integer>();
        for (AggregateResult ar : counts) {
            claimCountByFlag.put((String) ar.get('flagKey'), (Integer) ar.get('claimCount'));
        }

        List<Metadata.CustomMetadata> toUpdate = new List<Metadata.CustomMetadata>();
        for (FlipSwitch_Flag__mdt flag : inventoryFlags) {
            Integer claimed = claimCountByFlag.containsKey(flag.DeveloperName)
                ? claimCountByFlag.get(flag.DeveloperName)
                : 0;
            if (flag.Capacity__c != null && claimed >= (Integer) flag.Capacity__c) {
                Metadata.CustomMetadata md = new Metadata.CustomMetadata();
                md.fullName = 'FlipSwitch_Flag__mdt.' + flag.DeveloperName;
                md.label = flag.DeveloperName;
                Metadata.CustomMetadataValue fv = new Metadata.CustomMetadataValue();
                fv.field = 'Is_Closed__c';
                fv.value = true;
                md.values.add(fv);
                toUpdate.add(md);
            }
        }

        if (!toUpdate.isEmpty()) {
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            for (Metadata.CustomMetadata md : toUpdate) {
                container.addMetadata(md);
            }
            Metadata.Operations.enqueueDeployment(container, null);
        }
    }
}
