import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFlags      from '@salesforce/apex/FeatureFlagAdminController.getFlags';
import getCategories from '@salesforce/apex/FeatureFlagAdminController.getCategories';
import toggleKillSwitch from '@salesforce/apex/FeatureFlagAdminController.toggleKillSwitch';
import bulkUpdateFlags  from '@salesforce/apex/FeatureFlagAdminController.bulkUpdateFlags';

const STATUS_FILTERS = [
    { value: 'all',        label: 'All',          pillClass: 'status-pill' },
    { value: 'active',     label: 'Active',        pillClass: 'status-pill' },
    { value: 'disabled',   label: 'Disabled',      pillClass: 'status-pill' },
    { value: 'expired',    label: 'Expired',       pillClass: 'status-pill' },
    { value: 'killswitch', label: 'Kill-Switched', pillClass: 'status-pill' },
];

const TYPE_ICONS = {
    Boolean:    'utility:toggle',
    Percentage: 'utility:pie_chart',
    Variant:    'utility:variation2',
};

/**
 * @description Flag dashboard component. Renders a searchable, sortable,
 *              filterable flag list with inline kill-switch and bulk ops.
 *              Exposes a public filterByStatus() method for the shell banner.
 */
export default class FeatureFlagDashboard extends LightningElement {

    // ─── State ───────────────────────────────────────────────────────────────

    searchTerm      = '';
    selectedCategory = null;
    selectedStatus   = 'all';
    sortField        = 'label';
    sortAscending    = true;

    @track selectedKeys = new Set();

    isLoading   = false;
    errorMessage;

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
                valA = a.isKillSwitched ? '0' : a.isExpired ? '1' : a.isActive ? '3' : '2';
                valB = b.isKillSwitched ? '0' : b.isExpired ? '1' : b.isActive ? '3' : '2';
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

    get allPillClass() {
        return !this.selectedCategory
            ? 'status-pill status-pill_active' : 'status-pill';
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

    // ─── Data enrichment ─────────────────────────────────────────────────────

    /**
     * Adds computed display properties to a raw FlagSummary wire record.
     * Returns a plain object (not mutating the wire record).
     */
    _enrich(f) {
        const isSelected = this.selectedKeys.has(f.developerName);

        // Status label + badge class
        let statusLabel, statusBadgeClass;
        if (f.isKillSwitched) {
            statusLabel = 'Kill Switch';
            statusBadgeClass = 'status-badge status-badge_killswitch';
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

        // Kill-switch button appearance
        const killSwitchIcon    = f.isKillSwitched ? 'utility:clear' : 'utility:ban';
        const killSwitchAlt     = f.isKillSwitched ? 'Remove kill switch' : 'Activate kill switch';
        const killSwitchVariant = f.isKillSwitched ? 'error' : 'border';

        // Row highlight
        const rowClass = f.isKillSwitched
            ? 'slds-hint-parent row-killswitched'
            : isSelected ? 'slds-hint-parent row-selected' : 'slds-hint-parent';

        const rolloutBarStyle = f.rolloutPercent != null
            ? `width:${f.rolloutPercent}%` : 'width:0%';

        return {
            ...f,
            isSelected,
            statusLabel,
            statusBadgeClass,
            expirationLabel,
            expirationClass,
            killSwitchIcon,
            killSwitchAlt,
            killSwitchVariant,
            rowClass,
            rolloutBarStyle,
            typeIcon: TYPE_ICONS[f.type] ?? 'utility:toggle',
            isPercentage: f.type === 'Percentage',
            hasVariants:  f.type === 'Variant' && f.variantKeys?.length > 0,
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

    handleStatusFilter(event) {
        this.selectedStatus = event.currentTarget.dataset.status;
    }

    handleSort(event) {
        const newField = event.currentTarget.dataset.sort;
        if (this.sortField === newField) {
            this.sortAscending = !this.sortAscending;
        } else {
            this.sortField    = newField;
            this.sortAscending = true;
        }
    }

    handleSelectAll(event) {
        if (event.target.checked) {
            this.displayedFlags.forEach(f => this.selectedKeys.add(f.developerName));
        } else {
            this.selectedKeys = new Set();
        }
        // Trigger reactivity on the Set
        this.selectedKeys = new Set(this.selectedKeys);
    }

    handleRowSelect(event) {
        const key = event.currentTarget.dataset.key;
        if (event.target.checked) {
            this.selectedKeys.add(key);
        } else {
            this.selectedKeys.delete(key);
        }
        this.selectedKeys = new Set(this.selectedKeys);
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

    async handleKillSwitchToggle(event) {
        const flagKey     = event.currentTarget.dataset.key;
        const isActive    = event.currentTarget.dataset.killSwitched === 'true';
        const makeActive  = !isActive; // toggle

        this.isLoading = true;
        try {
            await toggleKillSwitch({ flagKey, active: makeActive });
            await refreshApex(this._wiredFlags);
            this.dispatchEvent(new CustomEvent('killswitchtoggled', {
                detail: { flagKey, active: makeActive }
            }));
            this.dispatchEvent(new ShowToastEvent({
                title: makeActive ? 'Kill Switch Activated' : 'Kill Switch Removed',
                message: `Flag "${flagKey}" is now ${makeActive ? 'kill-switched' : 'restored'}.`,
                variant: makeActive ? 'warning' : 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message ?? 'Could not toggle kill switch',
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
            this.dispatchEvent(new CustomEvent('killswitchtoggled'));
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

    // ─── Public API (called by shell banner) ──────────────────────────────────

    /** @api */
    filterByStatus(status) {
        this.selectedStatus = status;
    }
}
