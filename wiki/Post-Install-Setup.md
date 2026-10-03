# Post-Install Setup

## 1. Assign permission sets

```bash
# Admin users — full read/write + emergency disable
sf org assign permset --name FlipSwitch_Admin --target-org <alias>

# Application users — read-only, flag evaluation only
sf org assign permset --name FlipSwitch_User --target-org <alias>
```

Or assign manually via **Setup → Permission Sets**.

## 2. Configure Platform Cache (optional but recommended)

1. Go to **Setup → Platform Cache**
2. Create a partition named **`FlipSwitch`**
3. Update `Cache_Partition_Name__c` on the `FlipSwitch_Config.Default` CMDT record to `local.FlipSwitch`

Without a cache partition the framework works correctly but performs a SOQL query on every evaluation.

## 3. Schedule the expiration job

```apex
System.schedule('FlipSwitch Expiration Job', '0 0 0 * * ?', new FeatureFlagExpirationJob());
```

Or run the helper script:

```bash
sf apex run --target-org <alias> --file scripts/apex/schedule-expiration-job.apex
```

## 4. Open the admin dashboard

Navigate to the **Feature Flags** tab (or the **Feature Flag Admin** Lightning App Page).
