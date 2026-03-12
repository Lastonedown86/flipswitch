import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import getAllFlags from '@salesforce/apex/FeatureFlag.getAllFlags';
import activateKillSwitch from '@salesforce/apex/FeatureFlag.activateKillSwitch';
import deactivateKillSwitch from '@salesforce/apex/FeatureFlag.deactivateKillSwitch';

import FLIPSWITCH_RULE_OBJECT from '@salesforce/schema/FlipSwitch_Rule__c';
import FLAG_KEY_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Flag_Key__c';
import RULE_TYPE_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Rule_Type__c';
import RULE_VALUE_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Rule_Value__c';
import VARIANT_VALUE_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Variant_Value__c';
import PRIORITY_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Priority__c';
import IS_ACTIVE_FIELD from '@salesforce/schema/FlipSwitch_Rule__c.Is_Active__c';

export default class FeatureFlagAdmin extends LightningElement {
    @track flags = [];
    @track flagsError;
    @track saveMessage;
    @track killSwitchMessage;

    killSwitchFlagKey = '';

    @track newRule = {
        flagKey: '',
        ruleType: 'User',
        ruleValue: '',
        priority: 10,
        variantValue: ''
    };

    flagColumns = [
        { label: 'Flag Key', fieldName: 'DeveloperName', type: 'text' },
        { label: 'Label', fieldName: 'Label', type: 'text' },
        { label: 'Type', fieldName: 'Type__c', type: 'text' },
        { label: 'Active', fieldName: 'Is_Active__c', type: 'boolean' },
        { label: 'Default Value', fieldName: 'Default_Value__c', type: 'text' },
        { label: 'Category', fieldName: 'Category__c', type: 'text' },
        { label: 'Expires', fieldName: 'Expiration_Date__c', type: 'date' }
    ];

    ruleTypeOptions = [
        { label: 'User', value: 'User' },
        { label: 'Profile', value: 'Profile' },
        { label: 'Permission Set', value: 'Permission_Set' },
        { label: 'Percentage', value: 'Percentage' },
        { label: 'Segment', value: 'Segment' },
        { label: 'Custom Field', value: 'Custom_Field' },
        { label: 'Kill Switch', value: 'Kill_Switch' }
    ];

    @wire(getAllFlags)
    wiredFlags({ data, error }) {
        if (data) {
            this.flags = data;
            this.flagsError = undefined;
        } else if (error) {
            this.flagsError = 'Error loading flags: ' + error.body.message;
        }
    }

    handleRefresh() {
        this.dispatchEvent(new CustomEvent('refresh'));
        // Force wire re-evaluation
        getAllFlags({})
            .then((data) => {
                this.flags = data;
            })
            .catch((error) => {
                this.flagsError = error.body.message;
            });
    }

    handleFlagRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'kill') {
            this.killSwitchFlagKey = row.DeveloperName;
        }
    }

    handleRuleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newRule = { ...this.newRule, [field]: event.target.value };
    }

    handleSaveRule() {
        if (!this.newRule.flagKey || !this.newRule.ruleType) {
            this.saveMessage = 'Flag Key and Rule Type are required.';
            return;
        }

        const fields = {};
        fields[FLAG_KEY_FIELD.fieldApiName] = this.newRule.flagKey;
        fields[RULE_TYPE_FIELD.fieldApiName] = this.newRule.ruleType;
        fields[RULE_VALUE_FIELD.fieldApiName] = this.newRule.ruleValue;
        fields[VARIANT_VALUE_FIELD.fieldApiName] = this.newRule.variantValue;
        fields[PRIORITY_FIELD.fieldApiName] = parseInt(this.newRule.priority, 10);
        fields[IS_ACTIVE_FIELD.fieldApiName] = true;

        createRecord({ apiName: FLIPSWITCH_RULE_OBJECT.objectApiName, fields })
            .then(() => {
                this.saveMessage = 'Rule saved successfully.';
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Success', message: 'Rule created.', variant: 'success' })
                );
                this.newRule = { flagKey: '', ruleType: 'User', ruleValue: '', priority: 10, variantValue: '' };
            })
            .catch((error) => {
                this.saveMessage = 'Error: ' + error.body.message;
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Error', message: error.body.message, variant: 'error' })
                );
            });
    }

    handleKillSwitchKeyChange(event) {
        this.killSwitchFlagKey = event.target.value;
    }

    handleActivateKillSwitch() {
        if (!this.killSwitchFlagKey) {
            this.killSwitchMessage = 'Please enter a flag key.';
            return;
        }
        activateKillSwitch({ flagKey: this.killSwitchFlagKey })
            .then(() => {
                this.killSwitchMessage = `Kill switch activated for: ${this.killSwitchFlagKey}`;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Kill Switch Active',
                        message: `${this.killSwitchFlagKey} is now disabled.`,
                        variant: 'warning'
                    })
                );
            })
            .catch((error) => {
                this.killSwitchMessage = 'Error: ' + error.body.message;
            });
    }

    handleDeactivateKillSwitch() {
        if (!this.killSwitchFlagKey) {
            this.killSwitchMessage = 'Please enter a flag key.';
            return;
        }
        deactivateKillSwitch({ flagKey: this.killSwitchFlagKey })
            .then(() => {
                this.killSwitchMessage = `Kill switch removed for: ${this.killSwitchFlagKey}`;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Kill Switch Removed',
                        message: `${this.killSwitchFlagKey} rules restored.`,
                        variant: 'success'
                    })
                );
            })
            .catch((error) => {
                this.killSwitchMessage = 'Error: ' + error.body.message;
            });
    }
}
