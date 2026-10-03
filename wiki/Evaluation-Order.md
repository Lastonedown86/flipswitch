# Evaluation Order

FlipSwitch evaluates in this fixed priority order and short-circuits on the first match:

```
1. CMDT Is_Active__c = false            → EMERGENCY_DISABLE
2. Expiration_Date__c < TODAY           → EXPIRED
3. QA override (Override_All_Flags__c)  → QA_OVERRIDE
4. Emergency_Disable rule (Priority__c ASC)   → EMERGENCY_DISABLE
5. Targeting rules (Priority__c ASC):
     User → Profile → Permission_Set
     → Segment → Custom_Field           → RULE_MATCH
     → Percentage
6. CMDT Default_Value__c                → DEFAULT
```

Rules with the same `Priority__c` are evaluated in insertion order. Lower number = higher precedence (1 beats 10).
