import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveRule    from '@salesforce/apex/FeatureFlagAdminController.saveRule';
import deleteRule  from '@salesforce/apex/FeatureFlagAdminController.deleteRule';
import reorderRules from '@salesforce/apex/FeatureFlagAdminController.reorderRules';
import saveVariant  from '@salesforce/apex/FeatureFlagAdminController.saveVariant';
import deleteVariant from '@salesforce/apex/FeatureFlagAdminController.deleteVariant';
import getProfiles from '@salesforce/apex/FeatureFlagAdminController.getProfiles';
import getPermissionSets from '@salesforce/apex/FeatureFlagAdminController.getPermissionSets';
import searchUsers from '@salesforce/apex/FeatureFlagAdminController.searchUsers';
import searchAccounts from '@salesforce/apex/FeatureFlagAdminController.searchAccounts';
import getTerritories from '@salesforce/apex/FeatureFlagAdminController.getTerritories';
import resolveRuleValues from '@salesforce/apex/FeatureFlagAdminController.resolveRuleValues';

const RULE_TYPE_OPTIONS = [
    { label: 'User',           value: 'User' },
    { label: 'Profile',        value: 'Profile' },
    { label: 'Permission Set', value: 'Permission_Set' },
    { label: 'Segment',        value: 'Segment' },
    { label: 'Custom Field',   value: 'Custom_Field' },
    { label: 'Percentage',     value: 'Percentage' },
    { label: 'Emergency Disable',    value: 'Emergency_Disable' },
    { label: 'Account',        value: 'Account' },
    { label: 'Account Segment', value: 'Account_Segment' },
    { label: 'Territory',      value: 'Territory' },
];

const RULE_VALUE_HINTS = {
    User:           { label: 'Users',                placeholder: 'Search by name…' },
    Profile:        { label: 'Profiles',             placeholder: 'Filter profiles…' },
    Permission_Set: { label: 'Permission Sets',      placeholder: 'Filter permission sets…' },
    Segment:        { label: 'Segment Tag(s)',        placeholder: 'e.g. beta_testers;early_adopters' },
    Custom_Field:   { label: 'Field=Value Expression', placeholder: 'e.g. Account.Industry=Technology' },
    Percentage:     { label: 'Rollout %',            placeholder: '0–100' },
    Emergency_Disable:    { label: 'Emergency Disable',           placeholder: 'No value needed' },
    Account:        { label: 'Accounts',              placeholder: 'Search by name…' },
    Account_Segment: { label: 'Account Segment Expression', placeholder: 'Format: FieldApiName:Value (e.g. Industry:Technology)' },
    Territory:      { label: 'Territories',           placeholder: 'Filter territories…' },
};

const SEGMENT_COLORS = [
    '#0176d3', '#6366f1', '#22c55e', '#f59e0b',
    '#ec4899', '#14b8a6', '#f97316', '#8b5cf6',
];

/** Rule types that use the lookup input instead of plain text */
const LOOKUP_RULE_TYPES = new Set([
    'User', 'Profile', 'Permission_Set', 'Account', 'Territory'
]);

/** Maps rule types to their lookup variant (static combobox vs typeahead search) */
const LOOKUP_VARIANTS = {
    User:           'search',
    Profile:        'static',
    Permission_Set: 'static',
    Account:        'search',
    Territory:      'static',
};

/** Field-level help for lookup inputs */
const LOOKUP_HELP = {
    User:           'Select one or more users. The rule matches if the evaluating user\'s ID is in this list.',
    Profile:        'Select one or more profiles. The rule matches if the evaluating user belongs to any selected profile.',
    Permission_Set: 'Select one or more permission sets. The rule matches if the evaluating user has any of these assigned.',
    Account:        'Search for one or more accounts. The rule matches if the context account ID is in this list.',
    Territory:      'Select one or more territories. The rule matches if the evaluating user is assigned to any selected territory.',
};

/**
 * @description Rule builder component with drag-to-reorder, inline active toggles,
 *              an add/edit modal with context-aware inputs, and a variant weight
 *              visualizer for multi-variant flags.
 */
export default class FeatureFlagRuleBuilder extends LightningElement {

    /** @api */
    @api flagKey;

    /** @api */
    @api flagType;

    /** @api Passed from parent — raw rule list */
    @api
    get rules() {
        return this._rules;
    }
    set rules(value) {
        this._rules = value ?? [];
        this.localRules = this._buildLocalRules(this._rules);
        this.reorderDirty = false;
    }

    /** @api Passed from parent — raw variant list */
    @api
    get variants() {
        return this._variants;
    }
    set variants(value) {
        this._variants = value ?? [];
        this.localVariants = this._buildLocalVariants(this._variants);
    }

    // ─── State ───────────────────────────────────────────────────────────────

    @track localRules    = [];
    @track localVariants = [];

    isLoading     = false;
    reorderDirty  = false;

    showRuleModal = false;
    editRule      = {};
    isEditingExisting = false;

    // Drag state (not reactive — managed via DOM classes)
    _dragSourceId;
    _dragOverId;

    _rules    = [];
    _variants = [];

    // ─── Lookup state ────────────────────────────────────────────────────────

    @track profileOptions = [];
    @track permSetOptions = [];
    @track territoryOptions = [];
    @track editRuleSelectedValues = [];
    @track editRuleSelectedPills = [];
    _lookupOptionsLoaded = {};  // { Profile: true, … } — avoids re-fetching

    // ─── Getters ─────────────────────────────────────────────────────────────

    get isVariantFlag() {
        return this.flagType === 'Variant';
    }

    get noRules() {
        return !this.isLoading && this.localRules.length === 0;
    }

    get ruleTypeOptions() {
        return RULE_TYPE_OPTIONS;
    }

    get ruleModalTitle() {
        return this.isEditingExisting ? 'Edit Rule' : 'Add Rule';
    }

    get isPercentageRuleType() {
        return this.editRule?.ruleType === 'Percentage';
    }

    get isAccountSegment() {
        return this.editRule?.ruleType === 'Account_Segment';
    }

    get isLookupRuleType() {
        return LOOKUP_RULE_TYPES.has(this.editRule?.ruleType);
    }

    get lookupVariant() {
        return LOOKUP_VARIANTS[this.editRule?.ruleType] ?? 'static';
    }

    get lookupOptions() {
        const rt = this.editRule?.ruleType;
        switch (rt) {
            case 'Profile':        return this.profileOptions;
            case 'Permission_Set': return this.permSetOptions;
            case 'Territory':      return this.territoryOptions;
            default:               return [];
        }
    }

    get ruleValueHelp() {
        return LOOKUP_HELP[this.editRule?.ruleType] ?? '';
    }

    get ruleValueLabel() {
        return RULE_VALUE_HINTS[this.editRule?.ruleType]?.label ?? 'Value';
    }

    get ruleValuePlaceholder() {
        return RULE_VALUE_HINTS[this.editRule?.ruleType]?.placeholder ?? '';
    }

    get variantOptions() {
        return this.localVariants.map(v => ({
            label: v.variantKey || '(unnamed)',
            value: v.variantKey || '',
        }));
    }

    // ── Variant weight visualizer ────────────────────────────────────────────

    get totalWeight() {
        return this.localVariants.reduce((sum, v) => sum + (Number(v.weight) || 0), 0);
    }

    get totalWeightStyle() {
        return this.totalWeight !== 100 ? 'color:#c23934;font-weight:600' : 'color:#04844b;font-weight:600';
    }

    get totalWeightWarning() {
        if (this.totalWeight === 100) return '✓';
        return this.totalWeight < 100 ? `(${100 - this.totalWeight}% unassigned)` : `(${this.totalWeight - 100}% over)`;
    }

    get variantSegments() {
        return this.localVariants.map((v, idx) => ({
            key:     v.variantKey || `variant_${idx}`,
            style:   `width:${v.weight || 0}%;background:${SEGMENT_COLORS[idx % SEGMENT_COLORS.length]}`,
            tooltip: `${v.variantKey}: ${v.weight ?? 0}%`,
        }));
    }

    // ─── Local data builders ─────────────────────────────────────────────────

    _buildLocalRules(rules) {
        return rules.map((r, idx) => this._enrichRule(r, idx));
    }

    _enrichRule(r, idx) {
        const start  = r.Start_Date__c ? new Date(r.Start_Date__c) : null;
        const end    = r.End_Date__c   ? new Date(r.End_Date__c)   : null;
        const isScheduled = !!(start || end);

        let scheduleSummary = '';
        if (start && end) {
            scheduleSummary = `${start.toLocaleDateString()} – ${end.toLocaleDateString()}`;
        } else if (start) {
            scheduleSummary = `From ${start.toLocaleDateString()}`;
        } else if (end) {
            scheduleSummary = `Until ${end.toLocaleDateString()}`;
        }

        // Truncate long rule values
        const rawValue = r.Rule_Value__c ?? '';
        const valueSummary = rawValue.length > 60
            ? rawValue.substring(0, 57) + '…' : rawValue;

        const isActive  = r.Is_Active__c ?? true;
        const ruleType  = r.Rule_Type__c ?? '';
        const priority  = r.Priority__c  ?? idx + 1;

        return {
            id:             r.Id,
            ruleType,
            ruleValue:      r.Rule_Value__c,
            variantValue:   r.Variant_Value__c,
            priority,
            isActive,
            startDate:      r.Start_Date__c,
            endDate:        r.End_Date__c,
            isScheduled,
            scheduleSummary,
            valueSummary,
            hasVariantValue: !!r.Variant_Value__c,
            liClass:        `rule-item${isActive ? '' : ' rule-item--inactive'}`,
        };
    }

    _buildLocalVariants(variants) {
        return variants.map(v => ({
            id:         v.Id,
            variantKey: v.Variant_Key__c,
            weight:     v.Weight__c,
            payload:    v.Payload__c,
        }));
    }

    // ─── Drag-to-reorder ─────────────────────────────────────────────────────

    handleDragStart(event) {
        this._dragSourceId = event.currentTarget.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', this._dragSourceId);
        event.currentTarget.classList.add('rule-item--dragging');
    }

    handleDragEnter(event) {
        event.preventDefault();
        const targetId = event.currentTarget.dataset.id;
        if (targetId !== this._dragSourceId) {
            this._dragOverId = targetId;
            event.currentTarget.classList.add('rule-item--drag-over');
        }
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('rule-item--drag-over');
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }

    handleDrop(event) {
        event.preventDefault();
        const targetEl = event.target.closest('li[data-id]');
        if (!targetEl) return;
        const targetId = targetEl.dataset.id;
        if (!this._dragSourceId || targetId === this._dragSourceId) return;

        const fromIdx = this.localRules.findIndex(r => r.id === this._dragSourceId);
        const toIdx   = this.localRules.findIndex(r => r.id === targetId);
        if (fromIdx === -1 || toIdx === -1) return;

        // Reorder the array
        const reordered = [...this.localRules];
        const [moved]   = reordered.splice(fromIdx, 1);
        reordered.splice(toIdx, 0, moved);

        // Reassign sequential priorities
        this.localRules  = reordered.map((r, idx) => ({ ...r, priority: idx + 1 }));
        this.reorderDirty = true;

        // Clean up drag-over highlight
        targetEl.classList.remove('rule-item--drag-over');
    }

    handleDragEnd(event) {
        event.currentTarget.classList.remove('rule-item--dragging');
        this._dragSourceId = null;
        this._dragOverId   = null;
    }

    async handleSaveReorder() {
        this.isLoading = true;
        try {
            const payload = this.localRules.map(r => ({
                Id:          r.id,
                Priority__c: r.priority,
            }));
            await reorderRules({ rules: payload });
            this.reorderDirty = false;
            this.dispatchEvent(new CustomEvent('ruleschanged'));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Rule order saved.',
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not save rule order',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    handleDiscardReorder() {
        this.localRules   = this._buildLocalRules(this._rules);
        this.reorderDirty = false;
    }

    // ─── Rule CRUD ────────────────────────────────────────────────────────────

    handleAddRule() {
        this.isEditingExisting = false;
        this.editRule = {
            ruleType:     'User',
            ruleValue:    '',
            variantValue: '',
            priority:     this.localRules.length + 1,
            isActive:     true,
            startDate:    null,
            endDate:      null,
        };
        this.editRuleSelectedValues = [];
        this.editRuleSelectedPills = [];
        this._loadLookupOptionsForType('User');
        this.showRuleModal = true;
    }

    handleEditRule(event) {
        const id   = event.currentTarget.dataset.id;
        const rule = this.localRules.find(r => r.id === id);
        if (!rule) return;
        this.isEditingExisting = true;
        this.editRule = { ...rule };

        // Parse existing semicolon-delimited values into selected values array
        if (LOOKUP_RULE_TYPES.has(rule.ruleType) && rule.ruleValue) {
            this.editRuleSelectedValues = rule.ruleValue
                .split(';')
                .map(v => v.trim())
                .filter(Boolean);
            // Resolve IDs/names to display labels
            this._resolveExistingValues(rule.ruleType, rule.ruleValue);
        } else {
            this.editRuleSelectedValues = [];
            this.editRuleSelectedPills = [];
        }

        this._loadLookupOptionsForType(rule.ruleType);
        this.showRuleModal = true;
    }

    handleCloseRuleModal() {
        this.showRuleModal = false;
        this.editRule = {};
    }

    handleEditRuleTypeChange(event) {
        const newType = event.detail.value;
        this.editRule = { ...this.editRule, ruleType: newType, ruleValue: '' };
        this.editRuleSelectedValues = [];
        this.editRuleSelectedPills = [];
        this._loadLookupOptionsForType(newType);
    }

    handleEditFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRule = { ...this.editRule, [field]: event.target.value };
    }

    handleEditToggleChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRule = { ...this.editRule, [field]: event.target.checked };
    }

    async handleSaveRule() {
        if (!this.editRule.ruleType) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Error',
                message: 'Rule Type is required.',
                variant: 'error'
            }));
            return;
        }

        // For lookup types, join selected values into semicolon-delimited string
        let ruleValue = this.editRule.ruleValue;
        if (LOOKUP_RULE_TYPES.has(this.editRule.ruleType)) {
            ruleValue = this.editRuleSelectedValues.join(';');
        }

        const record = {
            Flag_Key__c:      this.flagKey,
            Rule_Type__c:     this.editRule.ruleType,
            Rule_Value__c:    ruleValue,
            Variant_Value__c: this.editRule.variantValue || null,
            Priority__c:      this.editRule.priority,
            Is_Active__c:     this.editRule.isActive,
            Start_Date__c:    this.editRule.startDate || null,
            End_Date__c:      this.editRule.endDate   || null,
        };

        if (this.isEditingExisting && this.editRule.id) {
            record.Id = this.editRule.id;
        }

        this.isLoading = true;
        try {
            await saveRule({ rule: record });
            this.showRuleModal = false;
            this.editRule = {};
            this.dispatchEvent(new CustomEvent('ruleschanged'));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Rule saved.',
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not save rule',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteRule(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this.isLoading = true;
        try {
            await deleteRule({ ruleId: id });
            this.dispatchEvent(new CustomEvent('ruleschanged'));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deleted',
                message: 'Rule removed.',
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not delete rule',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleRuleActiveToggle(event) {
        const id        = event.currentTarget.dataset.id;
        const isActive  = event.target.checked;
        const rule      = this.localRules.find(r => r.id === id);
        if (!rule) return;

        const record = {
            Id:          id,
            Is_Active__c: isActive,
            Flag_Key__c:  this.flagKey,
            Rule_Type__c: rule.ruleType,
        };

        this.isLoading = true;
        try {
            await saveRule({ rule: record });
            this.dispatchEvent(new CustomEvent('ruleschanged'));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not update rule',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Variant CRUD ─────────────────────────────────────────────────────────

    handleAddVariant() {
        this.localVariants = [
            ...this.localVariants,
            { id: `new_${Date.now()}`, variantKey: '', weight: 0, payload: '' }
        ];
    }

    handleVariantFieldChange(event) {
        const id    = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const value = event.target.value;
        this.localVariants = this.localVariants.map(v =>
            (v.id === id ? { ...v, [field]: field === 'weight' ? Number(value) : value } : v)
        );
    }

    async handleSaveVariant(event) {
        const id      = event.currentTarget.dataset.id;
        const local   = this.localVariants.find(v => v.id === id);
        if (!local) return;

        const record = {
            Flag_Key__c:    this.flagKey,
            Variant_Key__c: local.variantKey,
            Weight__c:      local.weight,
            Payload__c:     local.payload || null,
        };

        const isNew = id.startsWith('new_');
        if (!isNew) {
            record.Id = id;
        }

        this.isLoading = true;
        try {
            const saved = await saveVariant({ variant: record });
            // Replace temp id with real Id if new
            if (isNew) {
                this.localVariants = this.localVariants.map(v =>
                    (v.id === id ? { ...v, id: saved.Id } : v)
                );
            }
            this.dispatchEvent(new CustomEvent('variantschanged'));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved',
                message: `Variant "${local.variantKey}" saved.`,
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not save variant',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteVariant(event) {
        const id    = event.currentTarget.dataset.id;
        const isNew = id.startsWith('new_');

        if (isNew) {
            // Just remove from local array
            this.localVariants = this.localVariants.filter(v => v.id !== id);
            return;
        }

        this.isLoading = true;
        try {
            await deleteVariant({ variantId: id });
            this.localVariants = this.localVariants.filter(v => v.id !== id);
            this.dispatchEvent(new CustomEvent('variantschanged'));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deleted',
                message: 'Variant removed.',
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not delete variant',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Lookup handlers ──────────────────────────────────────────────────────

    handleLookupChange(event) {
        this.editRuleSelectedValues = event.detail.values;
        // Sync ruleValue for non-lookup save path
        this.editRule = {
            ...this.editRule,
            ruleValue: event.detail.values.join(';')
        };
    }

    async handleLookupSearch(event) {
        const { searchTerm } = event.detail;
        const rt = this.editRule?.ruleType;
        try {
            let results = [];
            if (rt === 'User') {
                results = await searchUsers({ searchTerm });
            } else if (rt === 'Account') {
                results = await searchAccounts({ searchTerm });
            }
            const lookupEl = this.template.querySelector('c-feature-flag-lookup-input');
            if (lookupEl) {
                lookupEl.setSearchResults(results);
            }
        } catch (err) {
            const lookupEl = this.template.querySelector('c-feature-flag-lookup-input');
            if (lookupEl) {
                lookupEl.setSearchResults([]);
            }
        }
    }

    // ─── Lookup helpers ──────────────────────────────────────────────────────

    async _loadLookupOptionsForType(ruleType) {
        if (!LOOKUP_RULE_TYPES.has(ruleType)) return;
        if (LOOKUP_VARIANTS[ruleType] === 'search') return; // search types don't preload

        // Only fetch once per session
        if (this._lookupOptionsLoaded[ruleType]) return;

        try {
            let options = [];
            switch (ruleType) {
                case 'Profile':
                    options = await getProfiles();
                    this.profileOptions = options;
                    break;
                case 'Permission_Set':
                    options = await getPermissionSets();
                    this.permSetOptions = options;
                    break;
                case 'Territory':
                    options = await getTerritories();
                    this.territoryOptions = options;
                    break;
                default:
                    break;
            }
            this._lookupOptionsLoaded[ruleType] = true;
        } catch (err) {
            // Silently fall back to empty options
        }
    }

    async _resolveExistingValues(ruleType, ruleValue) {
        try {
            const pills = await resolveRuleValues({ ruleType, ruleValue });
            this.editRuleSelectedPills = pills;
        } catch (err) {
            // If resolution fails, show raw values as pills
            this.editRuleSelectedPills = this.editRuleSelectedValues.map(v => ({
                label: v,
                value: v
            }));
        }
    }
}
