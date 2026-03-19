import { createElement } from 'lwc';
import FeatureFlagGate from 'c/featureFlagGate';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import isEnabledForCurrentUser from '@salesforce/apex/FeatureFlag.isEnabledForCurrentUser';

const mockIsEnabled = registerApexTestWireAdapter(isEnabledForCurrentUser);

describe('c-feature-flag-gate', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders enabled slot when flag is true', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.emit(true);
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(element.isEnabled).toBe(true);
    });

    it('renders disabled slot when flag is false', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.emit(false);
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(element.isEnabled).toBe(false);
    });

    it('defaults to disabled when wire returns error', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.error({ message: 'Apex error' });
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(element.isEnabled).toBe(false);
    });
});
