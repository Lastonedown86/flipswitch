# Percentage Rollouts

FlipSwitch uses a **deterministic SHA-256 hash** to assign each user a consistent percentile:

```
percentile = SHA-256( userId + ':' + flagKey ) mod 100
```

## Properties

- Same user + same flag = same percentile every time, with no per-user storage
- Increasing the threshold from 10% to 20% preserves all users already in the treatment group
- Each flag hashes independently — a user in Flag A's 10% is not guaranteed to be in Flag B's 10%
- Changing the flag's `DeveloperName` reassigns all users (use a stable, permanent key)

## Usage

To roll out to 20% of users, create a `Percentage` rule with `Rule_Value__c = 20`.
