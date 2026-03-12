import { LightningElement, api, wire } from 'lwc';
import isEnabledForCurrentUser from '@salesforce/apex/FeatureFlag.isEnabledForCurrentUser';

export default class FeatureFlagGate extends LightningElement {
    /** The FlipSwitch_Flag__mdt DeveloperName to evaluate */
    @api flagKey;

    _isEnabled = false;
    isLoading = true;
    error;

    @wire(isEnabledForCurrentUser, { flagKey: '$flagKey' })
    wiredResult({ data, error }) {
        this.isLoading = false;
        if (data !== undefined) {
            this._isEnabled = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this._isEnabled = false;
        }
    }

    @api get isEnabled() {
        return this._isEnabled;
    }
}
