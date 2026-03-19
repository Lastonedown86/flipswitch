# Plugin Framework

Register post-evaluation hooks by implementing `FeatureFlagPlugin` and creating a `FlipSwitch_Plugin__mdt` record:

```apex
public class MyAnalyticsPlugin implements FeatureFlagPlugin {
    public void onEvaluate(FeatureFlagResult result, FeatureFlagContext ctx) {
        if (result.reason == FeatureFlagResult.REASON_EMERGENCY_DISABLE) {
            MyAlertService.notify('Emergency disable hit: ' + ctx.flagKey);
        }
        MyAnalytics.track(ctx.flagKey, result.variant, ctx.userId);
    }
}
```

Register via CMDT (`FlipSwitch_Plugin.My_Analytics_Plugin.md-meta.xml`):

```xml
<CustomMetadata ...>
    <label>My Analytics Plugin</label>
    <values>
        <field>Class_Name__c</field>
        <value xsi:type="xsd:string">MyAnalyticsPlugin</value>
    </values>
    <values>
        <field>Is_Enabled__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Priority__c</field>
        <value xsi:type="xsd:double">10</value>
    </values>
</CustomMetadata>
```

Plugin errors are silently absorbed — a failing plugin never breaks flag evaluation.

## FeatureFlagContext (available in plugins)

| Property | Type | Description |
|----------|------|-------------|
| `userId` | `Id` | The user being evaluated |
| `profileId` | `Id` | The user's profile |
| `permissionSetNames` | `Set<String>` | Active permission set API names |
| `customAttributes` | `Map<String, Object>` | Attributes passed via `.withAttribute()` |
| `flagKey` | `String` | The flag being evaluated |
| `scenario` | `String` | Business scenario tag (if set) |
