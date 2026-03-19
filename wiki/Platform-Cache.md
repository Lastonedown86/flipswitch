# Platform Cache

FlipSwitch uses two cache tiers when a partition is configured:

| Tier | Scope | Content | TTL |
|------|-------|---------|-----|
| Org | Cross-session | CMDT flag definitions | 1 hour |
| Session | Per-user | Evaluation results | 1 hour |

If the partition is unavailable or not configured, all cache operations silently no-op and the framework falls back to direct SOQL queries. No configuration is required for the framework to function correctly.

## Setup

Create a partition named `FlipSwitch` in **Setup → Platform Cache**, then set `Cache_Partition_Name__c` on `FlipSwitch_Config.Default` to `local.FlipSwitch`.
