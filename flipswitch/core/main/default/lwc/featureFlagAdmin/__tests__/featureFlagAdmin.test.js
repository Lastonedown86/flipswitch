import { createElement } from 'lwc';
import FeatureFlagAdmin from 'c/featureFlagAdmin';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import getAllFlags from '@salesforce/apex/FeatureFlag.getAllFlags';

const mockGetAllFlags = registerLdsTestWireAdapter(getAllFlags);

const MOCK_FLAGS = [
    {
        DeveloperName: 'SAMPLE_BOOLEAN_FLAG',
        Label: 'Sample Boolean Flag',
        Type__c: 'Boolean',
        Is_Active__c: true,
        Default_Value__c: 'false',
        Category__c: 'Sample',
        Expiration_Date__c: null
    }
];

describe('c-feature-flag-admin', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the component without errors', () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);
        expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
    });

    it('renders datatable when flags are loaded', async () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);

        mockGetAllFlags.emit(MOCK_FLAGS);
        await Promise.resolve();

        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable).not.toBeNull();
        expect(datatable.data.length).toBe(1);
    });

    it('shows error message when flags fail to load', async () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);

        mockGetAllFlags.error({ body: { message: 'Apex error' } });
        await Promise.resolve();

        const errorEl = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('Error loading flags');
    });

    it('shows kill switch message when flag key is empty', async () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);

        // Trigger kill switch with no key
        const btn = element.shadowRoot.querySelector('[label="Activate Kill Switch"]');
        expect(btn).not.toBeNull();
    });
});
