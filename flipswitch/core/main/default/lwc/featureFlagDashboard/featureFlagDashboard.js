import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFlags from '@salesforce/apex/FeatureFlagAdminController.getFlags';
import getCategories from '@salesforce/apex/FeatureFlagAdminController.getCategories';
import toggleEmergencyDisable from '@salesforce/apex/FeatureFlagAdminController.toggleEmergencyDisable';
import bulkUpdateFlags from '@salesforce/apex/FeatureFlagAdminController.bulkUpdateFlags';
import createFlag from '@salesforce/apex/FeatureFlagAdminController.createFlag';
import deleteFlag from '@salesforce/apex/FeatureFlagAdminController.deleteFlag';

const STATUS_FILTERS = [
    { value: 'all', label: 'All', pillClass: 'status-pill' },
    { value: 'active', label: 'Active', pillClass: 'status-pill' },
    { value: 'disabled', label: 'Disabled', pillClass: 'status-pill' },
    { value: 'expiring', label: 'Expiring Soon', pillClass: 'status-pill' },
    { value: 'expired', label: 'Expired', pillClass: 'status-pill' },
    { value: 'emergencydisabled', label: 'Emergency Disabled', pillClass: 'status-pill' },
];

const SOURCE_FILTERS = [
    { value: 'all', label: 'All Sources', pillClass: 'status-pill' },
    { value: 'Deployed', label: 'Deployed', pillClass: 'status-pill' },
    { value: 'Code', label: 'Code', pillClass: 'status-pill' },
];

const TYPE_ICONS = {
    Boolean: 'utility:toggle',
    Percentage: 'utility:pie_chart',
    Variant: 'utility:variation2',
};

/**
 * @description Flag dashboard component. Renders a searchable, sortable,
 *              filterable flag list with inline emergency-disable and bulk ops.
 *              Exposes a public filterByStatus() method for the shell banner.
 */
export default class FeatureFlagDashboard extends LightningElement {

    // ─── State ───────────────────────────────────────────────────────────────

    searchTerm = '';
    selectedCategory = null;
    selectedStatus = 'all';
    selectedSource = 'all';
    sortField = 'label';
    sortAscending = true;

    @track selectedKeys = new Set();

    isLoading = false;
    errorMessage;

    // Flag CRUD modal state
    showCreateModal = false;

    _wiredFlags;
    _wiredCategories;

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getFlags, { category: '$selectedCategory', status: '$wireStatus' })
    wiredFlags(result) {
        this._wiredFlags = result;
        if (result.error) {
            this.errorMessage = result.error?.body?.message ?? 'Error loading flags';
        }
    }

    @wire(getCategories)
    wiredCategories(result) {
        this._wiredCategories = result;
    }

    // ─── Getters: wire passthrough ────────────────────────────────────────────

    get wireStatus() {
        return this.selectedStatus === 'all' ? null : this.selectedStatus;
    }

    get rawFlags() {
        return this._wiredFlags?.data ?? [];
    }

    get categories() {
        return (this._wiredCategories?.data ?? []).map(cat => ({
            value: cat,
            pillClass: this.selectedCategory === cat
                ? 'status-pill status-pill_active' : 'status-pill'
        }));
    }

    get hasError() {
        return !!this.errorMessage;
    }

    // ─── Getters: display data ────────────────────────────────────────────────

    get displayedFlags() {
        let flags = this.rawFlags.slice();

        // Client-side search
        if (this.searchTerm) {
            const q = this.searchTerm.toLowerCase();
            flags = flags.filter(f =>
                (f.label ?? '').toLowerCase().includes(q) ||
                (f.developerName ?? '').toLowerCase().includes(q) ||
                (f.description ?? '').toLowerCase().includes(q)
            );
        }

        // Source filter
        if (this.selectedSource && this.selectedSource !== 'all') {
            flags = flags.filter(f => f.source === this.selectedSource);
        }

        // Sort
        flags = flags.slice().sort((a, b) => {
            let valA, valB;
            if (this.sortField === 'label') {
                valA = (a.label ?? '').toLowerCase();
                valB = (b.label ?? '').toLowerCase();
            } else if (this.sortField === 'expiration') {
                valA = a.expirationDate ?? '9999-12-31';
                valB = b.expirationDate ?? '9999-12-31';
            } else if (this.sortField === 'status') {
                valA = a.isEmergencyDisabled ? '0' : a.isExpired ? '1' : a.isActive ? '3' : '2';
                valB = b.isEmergencyDisabled ? '0' : b.isExpired ? '1' : b.isActive ? '3' : '2';
            }
            const cmp = valA < valB ? -1 : valA > valB ? 1 : 0;
            return this.sortAscending ? cmp : -cmp;
        });

        // Enrich each flag with display properties
        return flags.map(f => this._enrich(f));
    }

    get displayedCount() {
        return this.displayedFlags.length;
    }

    get totalCount() {
        return this.rawFlags.length;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && this.displayedFlags.length === 0;
    }

    get allSelected() {
        return this.displayedFlags.length > 0 &&
            this.displayedFlags.every(f => this.selectedKeys.has(f.developerName));
    }

    get noneSelected() {
        return this.selectedKeys.size === 0;
    }

    get statusFilters() {
        return STATUS_FILTERS.map(sf => ({
            ...sf,
            pillClass: this.selectedStatus === sf.value
                ? 'status-pill status-pill_active' : 'status-pill'
        }));
    }

    get hasActiveFilters() {
        return !!(this.searchTerm || this.selectedCategory || this.selectedStatus !== 'all' || this.selectedSource !== 'all');
    }

    get allPillClass() {
        return !this.selectedCategory
            ? 'status-pill status-pill_active' : 'status-pill';
    }

    get enablePillClass() {
        return this.noneSelected
            ? 'action-pill action-pill_enable' : 'action-pill action-pill_enable';
    }

    get disablePillClass() {
        return this.noneSelected
            ? 'action-pill action-pill_disable' : 'action-pill action-pill_disable';
    }

    get sortByLabel() {
        return this.sortField === 'label';
    }

    get sortByExpiration() {
        return this.sortField === 'expiration';
    }

    get sortIconLabel() {
        return this.sortAscending ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get sortIconExpiration() {
        return this.sortAscending ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get sourceFilters() {
        return SOURCE_FILTERS.map(sf => ({
            ...sf,
            pillClass: this.selectedSource === sf.value
                ? 'status-pill status-pill_active' : 'status-pill'
        }));
    }

    // ─── Data enrichment ─────────────────────────────────────────────────────

    /**
     * Adds computed display properties to a raw FlagSummary wire record.
     * Returns a plain object (not mutating the wire record).
     */
    _enrich(f) {
        const isSelected = this.selectedKeys.has(f.developerName);

        // Status label + badge class
        let statusLabel, statusBadgeClass;
        if (f.isEmergencyDisabled) {
            statusLabel = 'Emergency Disable';
            statusBadgeClass = 'status-badge status-badge_emergencydisabled';
        } else if (f.isExpired) {
            statusLabel = 'Expired';
            statusBadgeClass = 'status-badge status-badge_expired';
        } else if (f.isExpiringSoon) {
            statusLabel = 'Expiring Soon';
            statusBadgeClass = 'status-badge status-badge_warning';
        } else if (f.isActive) {
            statusLabel = 'Active';
            statusBadgeClass = 'status-badge status-badge_active';
        } else {
            statusLabel = 'Disabled';
            statusBadgeClass = 'status-badge status-badge_disabled';
        }

        // Expiration display
        let expirationLabel, expirationClass;
        if (f.expirationDate) {
            const days = Math.round(
                (new Date(f.expirationDate) - new Date()) / (1000 * 60 * 60 * 24)
            );
            expirationLabel = days < 0
                ? `Expired ${Math.abs(days)}d ago`
                : days === 0 ? 'Expires today'
                    : `${days}d left`;
            expirationClass = days <= 0 ? 'expiry-text expiry-text_red'
                : days <= 7 ? 'expiry-text expiry-text_orange' : 'expiry-text';
        }

        // Emergency-disable button appearance
        const emergencyDisableIcon = f.isEmergencyDisabled ? 'utility:clear' : 'utility:ban';
        const emergencyDisableAlt = f.isEmergencyDisabled ? 'Remove emergency disable' : 'Activate emergency disable';
        const emergencyDisableVariant = f.isEmergencyDisabled ? 'error' : 'border';

        // Row highlight
        const rowClass = f.isEmergencyDisabled
            ? 'slds-hint-parent row-emergencydisabled'
            : isSelected ? 'slds-hint-parent row-selected' : 'slds-hint-parent';

        const rolloutBarStyle = f.rolloutPercent != null
            ? `width:${f.rolloutPercent}%` : 'width:0%';

        return {
            ...f,
            isSelected,
            checkboxId: `cb-${f.developerName}`,
            statusLabel,
            statusBadgeClass,
            expirationLabel,
            expirationClass,
            emergencyDisableIcon,
            emergencyDisableAlt,
            emergencyDisableVariant,
            rowClass,
            rolloutBarStyle,
            typeIcon: TYPE_ICONS[f.type] ?? 'utility:toggle',
            isPercentage: f.type === 'Percentage',
            hasVariants: f.type === 'Variant' && f.variantKeys?.length > 0,
            sourceBadgeClass: f.source === 'Code'
                ? 'source-badge source-badge_code'
                : 'source-badge source-badge_deployed',
            isCodeSource: f.source === 'Code',
        };
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleCategoryFilter(event) {
        this.selectedCategory = event.currentTarget.dataset.category;
    }

    handleClearCategoryFilter() {
        this.selectedCategory = null;
    }

    handleClearAllFilters() {
        this.searchTerm = '';
        this.selectedCategory = null;
        this.selectedStatus = 'all';
        this.selectedSource = 'all';
    }

    handleStatusFilter(event) {
        this.selectedStatus = event.currentTarget.dataset.status;
    }

    handleSourceFilter(event) {
        this.selectedSource = event.currentTarget.dataset.source;
    }

    handleSort(event) {
        const newField = event.currentTarget.dataset.sort;
        if (this.sortField === newField) {
            this.sortAscending = !this.sortAscending;
        } else {
            this.sortField = newField;
            this.sortAscending = true;
        }
    }

    handleSelectAll(event) {
        if (event.detail.checked) {
            this.displayedFlags.forEach(f => this.selectedKeys.add(f.developerName));
        } else {
            this.selectedKeys = new Set();
        }
        // Trigger reactivity on the Set
        this.selectedKeys = new Set(this.selectedKeys);
    }

    handleRowSelect(event) {
        const key = event.currentTarget.dataset.key;
        if (event.detail.checked) {
            this.selectedKeys.add(key);
        } else {
            this.selectedKeys.delete(key);
        }
        this.selectedKeys = new Set(this.selectedKeys);
    }

    handleCheckboxDblClick(event) {
        event.stopPropagation();
    }

    handleViewFlag(event) {
        const flagKey = event.currentTarget.dataset.key;
        this.dispatchEvent(new CustomEvent('viewflag', { detail: { flagKey } }));
    }

    handleRowDoubleClick(event) {
        const flagKey = event.currentTarget.dataset.key;
        if (flagKey) {
            this.dispatchEvent(new CustomEvent('viewflag', { detail: { flagKey } }));
        }
    }

    async handleEmergencyDisableToggle(event) {
        const flagKey = event.currentTarget.dataset.key;
        const isActive = event.currentTarget.dataset.emergencyDisabled === 'true';
        const makeActive = !isActive; // toggle

        this.isLoading = true;
        try {
            await toggleEmergencyDisable({ flagKey, active: makeActive });
            await refreshApex(this._wiredFlags);
            this.dispatchEvent(new CustomEvent('emergencydisabletoggled', {
                detail: { flagKey, active: makeActive }
            }));
            this.dispatchEvent(new ShowToastEvent({
                title: makeActive ? 'Emergency Disable Activated' : 'Emergency Disable Removed',
                message: `Flag "${flagKey}" is now ${makeActive ? 'emergency-disabled' : 'restored'}.`,
                variant: makeActive ? 'warning' : 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not toggle emergency disable',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleBulkEnable() {
        await this._bulkAction('enable');
    }

    async handleBulkDisable() {
        await this._bulkAction('disable');
    }

    async _bulkAction(action) {
        if (this.selectedKeys.size === 0) return;
        const flagKeys = Array.from(this.selectedKeys);
        this.isLoading = true;
        try {
            await bulkUpdateFlags({ flagKeys, action });
            await refreshApex(this._wiredFlags);
            this.selectedKeys = new Set();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `${flagKeys.length} flag(s) ${action}d.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('emergencydisabletoggled'));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? `Could not ${action} flags`,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Flag CRUD ───────────────────────────────────────────────────────────

    get existingCategoryValues() {
        return this._wiredCategories?.data ?? [];
    }

    handleNewFlag() {
        this.showCreateModal = true;
    }

    handleCreateModalCancel() {
        this.showCreateModal = false;
    }

    async handleCreateModalSave(event) {
        const input = event.detail;
        try {
            const result = await createFlag({ input });
            this.showCreateModal = false;
            await refreshApex(this._wiredFlags);
            await refreshApex(this._wiredCategories);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Flag Created',
                message: result.isAsync
                    ? `CMDT deployment queued for "${input.flagKey}". It will appear after deployment completes.`
                    : `Flag "${input.flagKey}" created successfully.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('flagcreated', { detail: { flagKey: input.flagKey } }));
        } catch (err) {
            const modal = this.template.querySelector('c-feature-flag-form-modal');
            if (modal) modal.resetSaving();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Creating Flag',
                message: err?.body?.message ?? 'Could not create flag',
                variant: 'error'
            }));
        }
    }

    async handleBulkDelete() {
        if (this.selectedKeys.size === 0) return;
        const flagKeys = Array.from(this.selectedKeys);
        // eslint-disable-next-line no-alert, no-restricted-globals
        if (!confirm(`Delete ${flagKeys.length} flag(s) and all associated rules, variants, and assignments? This cannot be undone.`)) {
            return;
        }
        this.isLoading = true;
        try {
            await Promise.all(flagKeys.map(key => {
                const flag = this.rawFlags.find(f => f.developerName === key);
                const source = flag?.source ?? 'Code';
                return deleteFlag({ flagKey: key, source });
            }));
            await refreshApex(this._wiredFlags);
            this.selectedKeys = new Set();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Flags Deleted',
                message: `${flagKeys.length} flag(s) and associated data deleted.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('flagdeleted'));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not delete flags',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Public API (called by shell banner) ──────────────────────────────────

    /** @api */
    filterByStatus(status) {
        this.selectedStatus = status;
    }
}
