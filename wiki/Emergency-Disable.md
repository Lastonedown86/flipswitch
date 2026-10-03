# Emergency Disable

An emergency disable immediately disables a flag for all users with no deployment. There are two levels:

## CMDT-level

Set `Is_Active__c = false` on the `FlipSwitch_Flag__mdt` record and deploy via CI/CD. Suitable for permanent retirements.

## Runtime emergency disable (instant, no deployment)

Via the admin UI **Emergency Disable** tab, or directly in Apex:

```apex
// Disable immediately (also invalidates Platform Cache)
FeatureFlag.activateEmergencyDisable('NEW_CHECKOUT');

// Re-enable
FeatureFlag.deactivateEmergencyDisable('NEW_CHECKOUT');
```

Or create a `FlipSwitch_Rule__c` record manually:

| Field | Value |
|-------|-------|
| `Flag_Key__c` | `NEW_CHECKOUT` |
| `Rule_Type__c` | `Emergency_Disable` |
| `Priority__c` | `1` |
| `Is_Active__c` | `true` |

The emergency disable takes effect on the next evaluation — no cache TTL delay.
