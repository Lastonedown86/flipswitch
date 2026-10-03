# Flag Definitions (CMDT)

Flags are defined in `FlipSwitch_Flag__mdt`. Deploy them via CI/CD alongside the code that checks them so the flag and its implementation always ship together.

```xml
<!-- force-app/main/default/customMetadata/FlipSwitch_Flag.NEW_CHECKOUT.md-meta.xml -->
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>New Checkout</label>
    <protected>false</protected>
    <values>
        <field>Type__c</field>
        <value xsi:type="xsd:string">Boolean</value>
    </values>
    <values>
        <field>Default_Value__c</field>
        <value xsi:type="xsd:string">false</value>
    </values>
    <values>
        <field>Is_Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Category__c</field>
        <value xsi:type="xsd:string">Checkout</value>
    </values>
    <values>
        <field>Expiration_Date__c</field>
        <value xsi:type="xsd:string">2026-09-30</value>
    </values>
    <values>
        <field>Description__c</field>
        <value xsi:type="xsd:string">Enables the redesigned checkout flow. Remove after full rollout.</value>
    </values>
</CustomMetadata>
```

## Field reference

| Field | Type | Description |
|-------|------|-------------|
| `DeveloperName` | Text | The key used in code — `FeatureFlag.isEnabled('NEW_CHECKOUT')` |
| `Type__c` | Picklist | `Boolean` · `Variant` · `Percentage` |
| `Default_Value__c` | Text | Fallback when no rules match: `true`, `false`, or a variant key |
| `Is_Active__c` | Checkbox | Master disable — `false` disables the flag immediately |
| `Expiration_Date__c` | Date | Flag evaluates as disabled after this date |
| `Category__c` | Text | Grouping label in the admin dashboard |
| `Description__c` | Long Text | Human-readable purpose, owner, and cleanup notes |
