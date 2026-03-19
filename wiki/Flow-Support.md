# Flow Support

FlipSwitch registers an `@InvocableMethod` that appears in Flow Builder under the **Feature Flags** action category.

## Input variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `Flag Key` | Text | Yes | `FlipSwitch_Flag__mdt` DeveloperName |
| `User Id` | Text | No | Salesforce User Id — defaults to running user |

## Output variables

| Variable | Type | Description |
|----------|------|-------------|
| `Is Enabled` | Boolean | Whether the flag is on for this user |
| `Variant` | Text | Variant key (null for boolean flags) |
| `Reason` | Text | `RULE_MATCH`, `DEFAULT`, `EMERGENCY_DISABLE`, etc. |

## Usage in a Record-Triggered Flow

1. Add an **Action** element
2. Search for **Evaluate Feature Flag**
3. Set `Flag Key` to your flag's DeveloperName
4. Use `{!Is_Enabled}` in a **Decision** element to branch

The action is **bulkified** — when a record-triggered flow processes 200 records, all evaluations share a single SOQL query for targeting rules.
