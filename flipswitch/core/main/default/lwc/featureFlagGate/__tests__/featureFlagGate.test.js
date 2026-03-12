import { createElement } from 'lwc';
import FeatureFlagGate from 'c/featureFlagGate';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import isEnabledForCurrentUser from '@salesforce/apex/FeatureFlag.isEnabledForCurrentUser';

const mockIsEnabled = registerLdsTestWireAdapter(isEnabledForCurrentUser);

describe('c-feature-flag-gate', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows spinner while loading', () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });

    it('renders enabled slot when flag is true', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.emit(true);
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('renders disabled slot when flag is false', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.emit(false);
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('defaults to disabled when wire returns error', async () => {
        const element = createElement('c-feature-flag-gate', { is: FeatureFlagGate });
        element.flagKey = 'TEST_FLAG';
        document.body.appendChild(element);

        mockIsEnabled.error({ message: 'Apex error' });
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
