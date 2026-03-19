import { createElement } from 'lwc';
import FeatureFlagAdmin from 'c/featureFlagAdmin';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import getOrgHealth from '@salesforce/apex/FeatureFlagAdminController.getOrgHealth';

const mockGetOrgHealth = registerApexTestWireAdapter(getOrgHealth);

const MOCK_HEALTH = {
    totalActive: 5,
    expiringSoon: 1,
    emergencyDisabled: 0,
    circuitBreakers: 2
};

describe('c-feature-flag-admin', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the component without errors', () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);
        expect(element.shadowRoot.querySelector('.flipswitch-admin')).not.toBeNull();
    });

    it('renders health strip when org health is loaded', async () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);

        mockGetOrgHealth.emit(MOCK_HEALTH);
        await Promise.resolve();

        const healthStrip = element.shadowRoot.querySelector('.health-strip');
        expect(healthStrip).not.toBeNull();
        const tiles = element.shadowRoot.querySelectorAll('.health-tile');
        expect(tiles.length).toBe(4);
    });

    it('renders tabset with expected tabs', () => {
        const element = createElement('c-feature-flag-admin', { is: FeatureFlagAdmin });
        document.body.appendChild(element);

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset).not.toBeNull();

        const tabs = element.shadowRoot.querySelectorAll('lightning-tab');
        expect(tabs.length).toBe(3);
    });
});
