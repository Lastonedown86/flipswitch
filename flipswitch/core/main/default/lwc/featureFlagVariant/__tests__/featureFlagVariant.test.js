import { createElement } from 'lwc';
import FeatureFlagVariant from 'c/featureFlagVariant';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import getVariantForCurrentUser from '@salesforce/apex/FeatureFlag.getVariantForCurrentUser';

const mockGetVariant = registerApexTestWireAdapter(getVariantForCurrentUser);

describe('c-feature-flag-variant', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('uses default variant when flag returns null', async () => {
        const element = createElement('c-feature-flag-variant', { is: FeatureFlagVariant });
        element.flagKey = 'EXPERIMENT';
        element.defaultVariant = 'control';
        document.body.appendChild(element);

        mockGetVariant.emit(null);
        await Promise.resolve();

        expect(element.currentVariant).toBe('control');
    });

    it('uses returned variant when flag returns a value', async () => {
        const element = createElement('c-feature-flag-variant', { is: FeatureFlagVariant });
        element.flagKey = 'EXPERIMENT';
        document.body.appendChild(element);

        mockGetVariant.emit('treatment_a');
        await Promise.resolve();

        expect(element.currentVariant).toBe('treatment_a');
    });

    it('falls back to default variant on wire error', async () => {
        const element = createElement('c-feature-flag-variant', { is: FeatureFlagVariant });
        element.flagKey = 'EXPERIMENT';
        element.defaultVariant = 'control';
        document.body.appendChild(element);

        mockGetVariant.error({ message: 'Apex error' });
        await Promise.resolve();

        expect(element.currentVariant).toBe('control');
    });
});
