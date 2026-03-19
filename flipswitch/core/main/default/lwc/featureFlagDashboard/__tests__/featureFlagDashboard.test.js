import { createElement } from 'lwc';
import FeatureFlagDashboard from 'c/featureFlagDashboard';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import getFlags from '@salesforce/apex/FeatureFlagAdminController.getFlags';
import getCategories from '@salesforce/apex/FeatureFlagAdminController.getCategories';

// Register wire adapters for controllable emit/error in tests
const getFlagsAdapter = registerApexTestWireAdapter(getFlags);
const getCategoriesAdapter = registerApexTestWireAdapter(getCategories);

// Mock imperative Apex methods (not wired)
jest.mock('@salesforce/apex/FeatureFlagAdminController.toggleEmergencyDisable', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/FeatureFlagAdminController.bulkUpdateFlags', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/FeatureFlagAdminController.createFlag', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/FeatureFlagAdminController.deleteFlag', () => ({ default: jest.fn() }), { virtual: true });

import createFlag from '@salesforce/apex/FeatureFlagAdminController.createFlag';

// ─── Test data ──────────────────────────────────────────────────────────────

const MOCK_DEPLOYED_FLAG = {
    developerName: 'SAMPLE_BOOLEAN_FLAG',
    label: 'Sample Boolean Flag',
    description: 'A deployed flag',
    type: 'Boolean',
    defaultValue: 'false',
    isActive: true,
    category: 'Sample',
    expirationDate: null,
    isEmergencyDisabled: false,
    isExpired: false,
    isExpiringSoon: false,
    rolloutPercent: null,
    variantKeys: [],
    activeRuleCount: 0,
    source: 'Deployed'
};

const MOCK_CODE_FLAG = {
    developerName: 'CHECKOUT_REDESIGN',
    label: 'CHECKOUT_REDESIGN',
    description: 'Enables the redesigned checkout flow',
    type: 'Boolean',
    defaultValue: 'false',
    isActive: false,
    category: 'Checkout',
    expirationDate: null,
    isEmergencyDisabled: false,
    isExpired: false,
    isExpiringSoon: false,
    rolloutPercent: null,
    variantKeys: [],
    activeRuleCount: 0,
    source: 'Code'
};

const MOCK_CODE_PERCENTAGE_FLAG = {
    developerName: 'ROLLOUT_FLAG',
    label: 'ROLLOUT_FLAG',
    description: 'Percentage rollout flag',
    type: 'Percentage',
    defaultValue: '50',
    isActive: false,
    category: 'Release',
    expirationDate: null,
    isEmergencyDisabled: false,
    isExpired: false,
    isExpiringSoon: false,
    rolloutPercent: 50,
    variantKeys: [],
    activeRuleCount: 0,
    source: 'Code'
};

const ALL_FLAGS = [MOCK_DEPLOYED_FLAG, MOCK_CODE_FLAG, MOCK_CODE_PERCENTAGE_FLAG];

// ─── Helpers ────────────────────────────────────────────────────────────────

/**
 * Emit wire adapter results to the component. LWC Jest uses the wire adapter
 * for @wire decorated properties. We simulate this by calling the wired function
 * directly using the internal handler pattern.
 */
function createComponent() {
    const element = createElement('c-feature-flag-dashboard', {
        is: FeatureFlagDashboard
    });
    document.body.appendChild(element);
    return element;
}

/**
 * Flush all pending microtasks so LWC re-renders.
 */
async function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// ─── Tests ──────────────────────────────────────────────────────────────────

describe('c-feature-flag-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // ── Rendering ─────────────────────────────────────────────────────────

    it('renders the component without errors', () => {
        const element = createComponent();
        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
    });

    it('shows empty state when no flags are loaded', async () => {
        const element = createComponent();
        getFlagsAdapter.emit([]);
        await flushPromises();

        const emptyHeading = element.shadowRoot.querySelector('h3');
        expect(emptyHeading).not.toBeNull();
        expect(emptyHeading.textContent).toBe('No Flags Found');
    });

    it('shows error state when wire returns error', async () => {
        const element = createComponent();
        getFlagsAdapter.error({ body: { message: 'Test error' } });
        await flushPromises();

        const errorAlert = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorAlert).not.toBeNull();
        // The component falls back to 'Error loading flags' when the error
        // shape doesn't match result.error.body.message exactly
        expect(errorAlert.textContent).toContain('Error loading flags');
    });

    // ── Code-defined flag rendering ──────────────────────────────────────

    it('renders code-defined flags with source=Code badge', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        getCategoriesAdapter.emit(['Checkout', 'Release', 'Sample']);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBe(3);

        // Find the code-defined flag row by data-key
        const codeRow = element.shadowRoot.querySelector('tr[data-key="CHECKOUT_REDESIGN"]');
        expect(codeRow).not.toBeNull();

        // Check the source badge shows 'Code' with the right class
        const sourceBadge = codeRow.querySelector('.source-badge');
        expect(sourceBadge).not.toBeNull();
        expect(sourceBadge.textContent).toBe('Code');
        expect(sourceBadge.classList.contains('source-badge_code')).toBe(true);
    });

    it('renders deployed flags with source=Deployed badge', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const deployedRow = element.shadowRoot.querySelector('tr[data-key="SAMPLE_BOOLEAN_FLAG"]');
        expect(deployedRow).not.toBeNull();

        const sourceBadge = deployedRow.querySelector('.source-badge');
        expect(sourceBadge).not.toBeNull();
        expect(sourceBadge.textContent).toBe('Deployed');
        expect(sourceBadge.classList.contains('source-badge_deployed')).toBe(true);
    });

    it('shows code-defined flag as Disabled by default', async () => {
        const element = createComponent();
        getFlagsAdapter.emit([MOCK_CODE_FLAG]);
        await flushPromises();

        const statusBadge = element.shadowRoot.querySelector('.status-badge');
        expect(statusBadge).not.toBeNull();
        expect(statusBadge.textContent).toBe('Disabled');
        expect(statusBadge.classList.contains('status-badge_disabled')).toBe(true);
    });

    // ── Source filter ────────────────────────────────────────────────────

    it('renders source filter pills (All Sources, Deployed, Code)', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const filterSections = element.shadowRoot.querySelectorAll('.filter-pills');
        // third filter section is source filters
        expect(filterSections.length).toBeGreaterThanOrEqual(3);

        const sourceButtons = filterSections[2].querySelectorAll('button');
        const sourceLabels = Array.from(sourceButtons).map((b) => b.textContent.trim());
        expect(sourceLabels).toContain('All Sources');
        expect(sourceLabels).toContain('Deployed');
        expect(sourceLabels).toContain('Code');
    });

    it('filters to show only Code source flags when Code pill is clicked', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        // Click the 'Code' source filter
        const filterSections = element.shadowRoot.querySelectorAll('.filter-pills');
        const sourceButtons = filterSections[2].querySelectorAll('button');
        const codeButton = Array.from(sourceButtons).find((b) => b.textContent.trim() === 'Code');
        expect(codeButton).not.toBeNull();

        codeButton.click();
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        // Should only show Code source flags (CHECKOUT_REDESIGN + ROLLOUT_FLAG)
        expect(rows.length).toBe(2);

        const keys = Array.from(rows).map((r) => r.dataset.key);
        expect(keys).toContain('CHECKOUT_REDESIGN');
        expect(keys).toContain('ROLLOUT_FLAG');
        expect(keys).not.toContain('SAMPLE_BOOLEAN_FLAG');
    });

    it('filters to show only Deployed source flags when Deployed pill is clicked', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const filterSections = element.shadowRoot.querySelectorAll('.filter-pills');
        const sourceButtons = filterSections[2].querySelectorAll('button');
        const deployedButton = Array.from(sourceButtons).find((b) => b.textContent.trim() === 'Deployed');
        deployedButton.click();
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBe(1);
        expect(rows[0].dataset.key).toBe('SAMPLE_BOOLEAN_FLAG');
    });

    it('shows all flags again when All Sources pill is clicked', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const filterSections = element.shadowRoot.querySelectorAll('.filter-pills');
        const sourceButtons = filterSections[2].querySelectorAll('button');

        // First click Code
        const codeButton = Array.from(sourceButtons).find((b) => b.textContent.trim() === 'Code');
        codeButton.click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr').length).toBe(2);

        // Then click All Sources
        const allButton = Array.from(sourceButtons).find((b) => b.textContent.trim() === 'All Sources');
        allButton.click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr').length).toBe(3);
    });

    // ── Percentage code-defined flag ─────────────────────────────────────

    it('shows rollout bar for code-defined percentage flags', async () => {
        const element = createComponent();
        getFlagsAdapter.emit([MOCK_CODE_PERCENTAGE_FLAG]);
        await flushPromises();

        const row = element.shadowRoot.querySelector('tr[data-key="ROLLOUT_FLAG"]');
        expect(row).not.toBeNull();

        const rolloutLabel = row.querySelector('.rollout-label');
        expect(rolloutLabel).not.toBeNull();
        expect(rolloutLabel.textContent).toBe('50%');
    });

    // ── View flag navigation ─────────────────────────────────────────────

    it('dispatches viewflag event when code-defined flag name is clicked', async () => {
        const element = createComponent();
        getFlagsAdapter.emit([MOCK_CODE_FLAG]);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('viewflag', handler);

        const link = element.shadowRoot.querySelector('a[data-key="CHECKOUT_REDESIGN"]');
        expect(link).not.toBeNull();
        link.click();
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.flagKey).toBe('CHECKOUT_REDESIGN');
    });

    // ── New Flag (create) ────────────────────────────────────────────────

    it('renders New Flag button in the toolbar', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const newBtn = element.shadowRoot.querySelector('.action-pill_create');
        expect(newBtn).not.toBeNull();
        expect(newBtn.textContent).toContain('New Flag');
    });

    it('opens create modal when New Flag is clicked', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        // Modal should not exist initially
        expect(element.shadowRoot.querySelector('c-feature-flag-form-modal')).toBeNull();

        const newBtn = element.shadowRoot.querySelector('.action-pill_create');
        newBtn.click();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-feature-flag-form-modal');
        expect(modal).not.toBeNull();
    });

    it('calls createFlag apex and dispatches flagcreated on save', async () => {
        createFlag.mockResolvedValue({ success: true, isAsync: false, message: 'Created' });

        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        getCategoriesAdapter.emit(['Sample']);
        await flushPromises();

        // Open modal
        const newBtn = element.shadowRoot.querySelector('.action-pill_create');
        newBtn.click();
        await flushPromises();

        const createdHandler = jest.fn();
        element.addEventListener('flagcreated', createdHandler);

        // Simulate modal save event
        const modal = element.shadowRoot.querySelector('c-feature-flag-form-modal');
        modal.dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    flagKey: 'NEW_FLAG',
                    label: 'New Flag',
                    type: 'Boolean',
                    defaultValue: 'false',
                    storageTarget: 'Registry'
                }
            })
        );
        await flushPromises();

        expect(createFlag).toHaveBeenCalledWith({
            input: expect.objectContaining({ flagKey: 'NEW_FLAG' })
        });
        expect(createdHandler).toHaveBeenCalledTimes(1);
    });

    it('shows error toast when createFlag fails', async () => {
        createFlag.mockRejectedValue({ body: { message: 'Duplicate key' } });

        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        // Open modal and save
        element.shadowRoot.querySelector('.action-pill_create').click();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-feature-flag-form-modal');
        modal.resetSaving = jest.fn();
        modal.dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    flagKey: 'DUPE',
                    label: 'Dupe',
                    type: 'Boolean',
                    defaultValue: 'false',
                    storageTarget: 'Registry'
                }
            })
        );
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        const toastDetail = toastHandler.mock.calls[0][0].detail;
        expect(toastDetail.variant).toBe('error');
        expect(toastDetail.message).toContain('Duplicate key');
    });

    it('closes modal when cancel event is received', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        // Open modal
        element.shadowRoot.querySelector('.action-pill_create').click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-feature-flag-form-modal')).not.toBeNull();

        // Cancel
        element.shadowRoot.querySelector('c-feature-flag-form-modal').dispatchEvent(new CustomEvent('cancel'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-feature-flag-form-modal')).toBeNull();
    });

    // ── Bulk Delete ──────────────────────────────────────────────────────

    it('renders Delete Selected button in the toolbar', async () => {
        const element = createComponent();
        getFlagsAdapter.emit(ALL_FLAGS);
        await flushPromises();

        const deleteBtn = element.shadowRoot.querySelector('.action-pill_delete');
        expect(deleteBtn).not.toBeNull();
    });
});
