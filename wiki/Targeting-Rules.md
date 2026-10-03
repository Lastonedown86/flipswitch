# Targeting Rules

Targeting rules live in `FlipSwitch_Rule__c` (a Custom Object) so admins can create and modify them without a deployment.

## Rule types

### User

Enable for specific users. `Rule_Value__c` is a semicolon-delimited list of User Ids:

```
005Dn000005abc1AAA;005Dn000005abc2AAA
```

### Profile

Enable for an entire profile. `Rule_Value__c` is a semicolon-delimited list of Profile Ids:

```
00e000000000001AAA
```

### Permission Set

Enable for users who hold a specific permission set. `Rule_Value__c` is a semicolon-delimited list of permission set API names:

```
Beta_Testers;Release_Team
```

### Percentage

Enable for a percentage of users based on a deterministic hash. `Rule_Value__c` is an integer `0`–`100`:

```
20
```

See [Percentage Rollouts](Percentage-Rollouts) for how the hash is calculated.

### Segment

Enable when all specified context attributes match. `Rule_Value__c` is a JSON object — all key-value pairs must be present and equal in the evaluation context:

```json
{"region": "US", "tier": "Enterprise"}
```

Pass attributes in the builder:

```apex
FeatureFlag.flag('FEATURE')
    .withAttribute('region', 'US')
    .withAttribute('tier', 'Enterprise')
    .isEnabled();
```

### Custom Field

Enable based on a single named attribute. `Rule_Value__c` is a JSON object with `field` and `value` keys:

```json
{"field": "account_type", "value": "Partner"}
```

### Emergency Disable

Immediately disables the flag regardless of all other rules. No `Rule_Value__c` needed. Set `Priority__c = 1` to ensure it always wins.

## Rule scheduling

Every rule supports optional `Start_Date__c` and `End_Date__c` fields. A rule is only evaluated while:

```
Start_Date__c ≤ NOW ≤ End_Date__c
```

Rules past their `End_Date__c` are automatically deactivated by `FeatureFlagExpirationJob` each night.
