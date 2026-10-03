import { LightningElement, api, wire } from 'lwc';
import getVariantForCurrentUser from '@salesforce/apex/FeatureFlag.getVariantForCurrentUser';

export default class FeatureFlagVariant extends LightningElement {
    /** The FlipSwitch_Flag__mdt DeveloperName to evaluate */
    @api flagKey;

    /** Default variant slot to render when no other matches */
    @api defaultVariant = 'control';

    _variant;
    isLoading = true;
    error;

    @wire(getVariantForCurrentUser, { flagKey: '$flagKey' })
    wiredVariant({ data, error }) {
        this.isLoading = false;
        if (data !== undefined) {
            this._variant = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this._variant = this.defaultVariant;
        }
    }

    @api get currentVariant() {
        return this._variant || this.defaultVariant;
    }
}
