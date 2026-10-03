/**
 * @description Imperative LWC service module for feature flag evaluation.
 *
 *              Usage:
 *              import { isEnabled, getVariant, evaluateFlags } from 'c/featureFlagService';
 *
 *              const newCheckout = await isEnabled('NEW_CHECKOUT');
 *              const variant = await getVariant('HOMEPAGE_EXPERIMENT');
 *              const results = await evaluateFlags(['FLAG_A', 'FLAG_B']);
 *
 *              Client-side in-memory cache deduplicates repeated calls within
 *              the same component lifecycle.
 */
import isEnabledForCurrentUser from '@salesforce/apex/FeatureFlag.isEnabledForCurrentUser';
import getVariantForCurrentUser from '@salesforce/apex/FeatureFlag.getVariantForCurrentUser';
import evaluateFlagsForCurrentUser from '@salesforce/apex/FeatureFlag.evaluateFlagsForCurrentUser';

// Simple in-memory cache keyed by flagKey
const cache = new Map();
const TTL_MS = 30000; // 30 seconds

function getCached(key) {
    const entry = cache.get(key);
    if (entry && Date.now() - entry.timestamp < TTL_MS) {
        return entry.value;
    }
    return undefined;
}

function setCached(key, value) {
    cache.set(key, { value, timestamp: Date.now() });
}

/**
 * @description Check if a flag is enabled for the current user.
 * @param {string} flagKey - FlipSwitch_Flag__mdt DeveloperName
 * @returns {Promise<boolean>}
 */
async function isEnabled(flagKey) {
    const cached = getCached(`enabled:${flagKey}`);
    if (cached !== undefined) return cached;

    const result = await isEnabledForCurrentUser({ flagKey });
    setCached(`enabled:${flagKey}`, result);
    return result;
}

/**
 * @description Get the variant for a flag for the current user.
 * @param {string} flagKey - FlipSwitch_Flag__mdt DeveloperName
 * @returns {Promise<string>}
 */
async function getVariant(flagKey) {
    const cached = getCached(`variant:${flagKey}`);
    if (cached !== undefined) return cached;

    const result = await getVariantForCurrentUser({ flagKey });
    setCached(`variant:${flagKey}`, result);
    return result;
}

/**
 * @description Batch evaluate multiple flags in a single Apex call.
 * @param {string[]} flagKeys - Array of FlipSwitch_Flag__mdt DeveloperNames
 * @returns {Promise<Object>} Map of flagKey → { isEnabled, variant, reason }
 */
async function evaluateFlags(flagKeys) {
    const result = await evaluateFlagsForCurrentUser({ flagKeys });
    // Cache individual results
    if (result) {
        Object.keys(result).forEach((key) => {
            setCached(`enabled:${key}`, result[key].isEnabled);
            setCached(`variant:${key}`, result[key].variant);
        });
    }
    return result;
}

/**
 * @description Clear the client-side cache.
 *              Call after admin operations that may have changed flag state.
 */
function clearCache() {
    cache.clear();
}

export { isEnabled, getVariant, evaluateFlags, clearCache };
