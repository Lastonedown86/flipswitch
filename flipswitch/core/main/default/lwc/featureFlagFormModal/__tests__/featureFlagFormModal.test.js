/* eslint-disable @lwc/lwc/prefer-custom-event */
import { createElement } from 'lwc';
import FeatureFlagFormModal from 'c/featureFlagFormModal';

// ─── Helpers ────────────────────────────────────────────────────────────────

function createComponent(props = {}) {
    const element = createElement('c-feature-flag-form-modal', {
        is: FeatureFlagFormModal
    });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

async function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** querySelector shorthand */
function q(el, sel) {
    return el.shadowRoot.querySelector(sel);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

describe('c-feature-flag-form-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // ── Rendering ─────────────────────────────────────────────────────────

    it('renders the modal dialog', () => {
        const element = createComponent();
        expect(q(element, '[role="dialog"]')).not.toBeNull();
    });

    it('renders with "New Flag" title in create mode', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const heading = q(element, '.slds-modal__title');
        expect(heading).not.toBeNull();
        expect(heading.textContent).toContain('New Flag');
    });

    it('renders with "Edit Flag" title in edit mode', async () => {
        const element = createComponent({ mode: 'edit' });
        await flushPromises();

        const heading = q(element, '.slds-modal__title');
        expect(heading).not.toBeNull();
        expect(heading.textContent).toContain('Edit Flag');
    });

    it('shows Flag Key input in create mode', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        expect(q(element, '[data-id="flag-key"]')).not.toBeNull();
    });

    it('shows Flag Key as read-only display in edit mode', async () => {
        const element = createComponent({ mode: 'edit' });
        await flushPromises();

        expect(q(element, '[data-id="flag-key"]')).toBeNull();
        expect(q(element, '.flag-key-display')).not.toBeNull();
    });

    it('shows storage target selector only in create mode', async () => {
        const createEl = createComponent({ mode: 'create' });
        await flushPromises();
        expect(q(createEl, '[data-id="storage"]')).not.toBeNull();

        document.body.removeChild(createEl);

        const editEl = createComponent({ mode: 'edit' });
        await flushPromises();
        expect(q(editEl, '[data-id="storage"]')).toBeNull();
    });

    // ── Type-aware defaults ───────────────────────────────────────────────

    it('shows Boolean combobox for default value by default', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const defVal = q(element, '[data-id="default-value"]');
        expect(defVal).not.toBeNull();
        expect(defVal.tagName.toLowerCase()).toBe('lightning-combobox');
    });

    it('switches to number input when type changes to Percentage', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        q(element, '[data-id="type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'Percentage' } }));
        await flushPromises();

        const defVal = q(element, '[data-id="default-value"]');
        expect(defVal).not.toBeNull();
        expect(defVal.tagName.toLowerCase()).toBe('lightning-input');
    });

    it('switches to text input when type changes to Variant', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        q(element, '[data-id="type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'Variant' } }));
        await flushPromises();

        const defVal = q(element, '[data-id="default-value"]');
        expect(defVal).not.toBeNull();
        expect(defVal.tagName.toLowerCase()).toBe('lightning-input');
    });

    // ── setFlagData API ───────────────────────────────────────────────────

    it('populates form fields via setFlagData', async () => {
        const element = createComponent({ mode: 'edit' });
        await flushPromises();

        element.setFlagData({
            flagKey: 'TEST_FLAG',
            label: 'Test Flag',
            description: 'A description',
            type: 'Percentage',
            defaultValue: '75',
            category: 'Release',
            expirationDate: '2025-12-31',
            isActive: false,
            source: 'Code'
        });
        await flushPromises();

        expect(q(element, '.flag-key-display').textContent).toBe('TEST_FLAG');

        // Type changed to Percentage so default-value should be lightning-input
        const defVal = q(element, '[data-id="default-value"]');
        expect(defVal).not.toBeNull();
        expect(defVal.tagName.toLowerCase()).toBe('lightning-input');
    });

    it('handles null flag gracefully in setFlagData', () => {
        const element = createComponent({ mode: 'edit' });
        element.setFlagData(null);
        expect(element).toBeTruthy();
    });

    // ── Event dispatching ─────────────────────────────────────────────────

    it('dispatches cancel event when Cancel button is clicked', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('cancel', handler);

        q(element, '[data-id="cancel-btn"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('dispatches cancel event when backdrop is clicked', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('cancel', handler);

        q(element, '.slds-backdrop').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('dispatches cancel event when close button is clicked', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('cancel', handler);

        q(element, '.slds-modal__close').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('dispatches save event with form data when Save is clicked', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('save', handler);

        // Set required fields via change handlers
        const keyEvent = new Event('change');
        Object.defineProperty(keyEvent, 'target', { value: { value: 'MY_FLAG' } });
        q(element, '[data-id="flag-key"]').dispatchEvent(keyEvent);

        const labelEvent = new Event('change');
        Object.defineProperty(labelEvent, 'target', { value: { value: 'My Flag' } });
        q(element, '[data-id="label"]').dispatchEvent(labelEvent);

        await flushPromises();

        // Mock validity on all form elements
        element.shadowRoot.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea').forEach((el) => {
            el.reportValidity = jest.fn();
            el.checkValidity = jest.fn(() => true);
        });

        q(element, '[data-id="save-btn"]').click();
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual(
            expect.objectContaining({
                flagKey: 'MY_FLAG',
                label: 'My Flag',
                type: 'Boolean',
                defaultValue: 'false'
            })
        );
    });

    // ── resetSaving API ───────────────────────────────────────────────────

    it('resets isSaving via resetSaving API', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        // Set required fields
        const keyEvent = new Event('change');
        Object.defineProperty(keyEvent, 'target', { value: { value: 'TEST' } });
        q(element, '[data-id="flag-key"]').dispatchEvent(keyEvent);

        const labelEvent = new Event('change');
        Object.defineProperty(labelEvent, 'target', { value: { value: 'Test' } });
        q(element, '[data-id="label"]').dispatchEvent(labelEvent);

        await flushPromises();

        // Mock validity
        element.shadowRoot.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea').forEach((el) => {
            el.reportValidity = jest.fn();
            el.checkValidity = jest.fn(() => true);
        });

        const saveBtn = q(element, '[data-id="save-btn"]');
        saveBtn.click();
        await flushPromises();

        expect(saveBtn.disabled).toBe(true);

        element.resetSaving();
        await flushPromises();

        expect(saveBtn.disabled).toBe(false);
    });

    // ── Category options ──────────────────────────────────────────────────

    it('renders existing categories as options with a None option', async () => {
        const element = createComponent({
            mode: 'create',
            existingCategories: ['Release', 'Experiment']
        });
        await flushPromises();

        const catCombo = q(element, '[data-id="category"]');
        expect(catCombo).not.toBeNull();
        expect(catCombo.options.length).toBe(3);
        expect(catCombo.options[0].label).toBe('— None —');
        expect(catCombo.options[1].value).toBe('Release');
        expect(catCombo.options[2].value).toBe('Experiment');
    });

    // ── CMDT info box ─────────────────────────────────────────────────────

    it('shows CMDT info box when storage target is CMDT', async () => {
        const element = createComponent({ mode: 'create' });
        await flushPromises();

        q(element, '[data-id="storage"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'CMDT' } }));
        await flushPromises();

        const infoBox = q(element, '.slds-theme_info');
        expect(infoBox).not.toBeNull();
        expect(infoBox.textContent).toContain('asynchronously');
    });
});
