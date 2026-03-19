import { LightningElement, api } from 'lwc';

const TYPE_OPTIONS = [
    { label: 'Boolean', value: 'Boolean' },
    { label: 'Percentage', value: 'Percentage' },
    { label: 'Variant', value: 'Variant' },
];

const BOOLEAN_OPTIONS = [
    { label: 'false', value: 'false' },
    { label: 'true', value: 'true' },
];

const STORAGE_OPTIONS = [
    { label: 'Registry (instant)', value: 'Registry' },
    { label: 'CMDT (async deploy)', value: 'CMDT' },
];

const DEFAULT_VALUES = {
    Boolean: 'false',
    Percentage: '0',
    Variant: 'control',
};

/**
 * @description Modal form for creating and editing feature flag definitions.
 *              Supports both Registry (DML) and CMDT (Metadata API) storage targets.
 */
export default class FeatureFlagFormModal extends LightningElement {

    /** @api 'create' or 'edit' */
    @api mode = 'create';

    /** @api Existing categories for the combobox */
    @api existingCategories = [];

    // Form state
    flagKey = '';
    label = '';
    description = '';
    type = 'Boolean';
    defaultValue = 'false';
    category = '';
    expirationDate = '';
    isActive = true;
    storageTarget = 'Registry';
    isSaving = false;

    /**
     * @api Pre-populate form for edit mode.
     * @param {Object} flag - Flag data with keys: flagKey, label, description, type, defaultValue, category, expirationDate, isActive, source
     */
    @api
    setFlagData(flag) {
        if (!flag) return;
        this.flagKey = flag.flagKey || flag.developerName || '';
        this.label = flag.label || '';
        this.description = flag.description || '';
        this.type = flag.type || 'Boolean';
        this.defaultValue = flag.defaultValue || DEFAULT_VALUES[this.type] || 'false';
        this.category = flag.category || '';
        this.expirationDate = flag.expirationDate || '';
        this.isActive = flag.isActive !== undefined ? flag.isActive : true;
        this.storageTarget = flag.source === 'Deployed' ? 'CMDT' : 'Registry';
    }

    // ── Getters ──────────────────────────────────────────────────────────────

    get isCreateMode() {
        return this.mode === 'create';
    }

    get headerTitle() {
        return this.mode === 'create' ? 'New Flag' : 'Edit Flag';
    }

    get headerIcon() {
        return this.mode === 'create' ? 'utility:add' : 'utility:edit';
    }

    get saveButtonLabel() {
        if (this.isSaving) return 'Saving…';
        return this.mode === 'create' ? 'Create Flag' : 'Save Changes';
    }

    get typeOptions() {
        return TYPE_OPTIONS;
    }

    get booleanOptions() {
        return BOOLEAN_OPTIONS;
    }

    get storageOptions() {
        return STORAGE_OPTIONS;
    }

    get isBooleanType() {
        return this.type === 'Boolean';
    }

    get isPercentageType() {
        return this.type === 'Percentage';
    }

    get isCmdtStorage() {
        return this.storageTarget === 'CMDT';
    }

    get categoryOptions() {
        const cats = (this.existingCategories || []).map(c => ({ label: c, value: c }));
        // Add a blank option at the start
        return [{ label: '— None —', value: '' }, ...cats];
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleFlagKeyChange(event) {
        this.flagKey = event.target.value;
    }

    handleLabelChange(event) {
        this.label = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleTypeChange(event) {
        const newType = event.detail.value;
        this.type = newType;
        // Reset default value when type changes
        this.defaultValue = DEFAULT_VALUES[newType] || 'false';
    }

    handleDefaultValueChange(event) {
        if (this.type === 'Percentage') {
            this.defaultValue = String(event.target.value);
        } else if (event.detail && event.detail.value !== undefined) {
            this.defaultValue = event.detail.value;
        } else {
            this.defaultValue = event.target.value;
        }
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleExpirationDateChange(event) {
        this.expirationDate = event.target.value;
    }

    handleIsActiveChange(event) {
        this.isActive = event.target.checked;
    }

    handleStorageChange(event) {
        this.storageTarget = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleSave() {
        // Client-side validation
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')]
            .reduce((valid, input) => {
                input.reportValidity();
                return valid && input.checkValidity();
            }, true);

        if (!allValid) return;

        if (this.mode === 'create' && !this.flagKey) return;
        if (!this.label) return;

        this.isSaving = true;

        const detail = {
            flagKey: this.flagKey,
            label: this.label,
            description: this.description,
            type: this.type,
            defaultValue: this.defaultValue,
            category: this.category,
            expirationDate: this.expirationDate,
            isActive: this.isActive,
            storageTarget: this.storageTarget,
        };

        this.dispatchEvent(new CustomEvent('save', { detail }));
    }

    /** @api Reset the saving state (called by parent after Apex completes) */
    @api
    resetSaving() {
        this.isSaving = false;
    }
}
