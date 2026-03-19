import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrgHealth from '@salesforce/apex/FeatureFlagAdminController.getOrgHealth';
import { refreshApex } from '@salesforce/apex';

/**
 * @description Shell component for the FlipSwitch Admin app.
 *              Manages global tab navigation, the org health strip,
 *              the emergency-disable alert banner, and cross-tab state
 *              (selected flag key flows to detail / logs / analytics tabs).
 */
export default class FeatureFlagAdmin extends LightningElement {
    /** Currently active tab value */
    activeTab = 'dashboard';

    /** Flag key selected in the dashboard — shared with detail/logs/analytics tabs */
    selectedFlagKey;

    /** Controls the slide-in detail drawer */
    isDrawerOpen = false;

    /** Wired result stored for refreshApex */
    _wiredHealth;

    @wire(getOrgHealth)
    wiredHealth(result) {
        this._wiredHealth = result;
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get orgHealth() {
        return this._wiredHealth?.data ?? {
            totalActive: 0,
            expiringSoon: 0,
            emergencyDisabled: 0,
            circuitBreakers: 0
        };
    }

    get hasEmergencyDisabledFlags() {
        return this.orgHealth.emergencyDisabled > 0;
    }

    get emergencyDisabledCount() {
        return this.orgHealth.emergencyDisabled;
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    /** Fired by featureFlagDashboard when a row is clicked */
    handleViewFlag(event) {
        this.selectedFlagKey = event.detail.flagKey;
        this.isDrawerOpen = true;
    }

    handleCloseDrawer() {
        this.isDrawerOpen = false;
    }

    /** Fired by featureFlagDashboard or featureFlagDetail on emergency-disable toggle */
    handleEmergencyDisableToggled() {
        refreshApex(this._wiredHealth);
    }

    /** Banner link: jump to dashboard filtered to emergency-disabled flags */
    handleEmergencyDisableBannerClick() {
        this.activeTab = 'dashboard';
        // Communicate filter intent to dashboard via a custom event on its element
        const dashboardEl = this.template.querySelector('c-feature-flag-dashboard');
        if (dashboardEl) {
            dashboardEl.filterByStatus('emergencydisable');
        }
    }

    /** Surface any unhandled errors as toast messages */
    errorCallback(error, stack) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Unexpected Error',
            message: error?.message ?? 'An unexpected error occurred',
            variant: 'error',
            mode: 'sticky'
        }));
        console.error('[featureFlagAdmin] Error:', error, stack);
    }
}
