import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFlagDetail    from '@salesforce/apex/FeatureFlagAdminController.getFlagDetail';
import toggleKillSwitch from '@salesforce/apex/FeatureFlagAdminController.toggleKillSwitch';
import previewEvaluation from '@salesforce/apex/FeatureFlagAdminController.previewEvaluation';

const REASON_CLASSES = {
    RULE_MATCH:      'reason-badge reason-badge_rule',
    DEFAULT:         'reason-badge reason-badge_default',
    KILL_SWITCH:     'reason-badge reason-badge_killswitch',
    EXPIRED:         'reason-badge reason-badge_expired',
    CACHE_HIT:       'reason-badge reason-badge_cache',
    CIRCUIT_BREAKER: 'reason-badge reason-badge_error',
};

/**
 * @description Flag detail component: displays metadata, usage snippets,
 *              delegates rule/variant management to featureFlagRuleBuilder,
 *              and provides an interactive evaluation preview panel.
 */
export default class FeatureFlagDetail extends LightningElement {

    /** @api Public — set by featureFlagAdmin shell */
    @api flagKey;

    isLoading        = false;
    errorMessage;

    // Snippet panel state
    activeSnippetTab = 'apex';

    // Preview panel state
    previewUserId    = '';
    previewAttrsJson = '';
    previewResult;
    isPreviewLoading = false;

    _wiredDetail;

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getFlagDetail, { flagKey: '$flagKey' })
    wiredDetail(result) {
        this._wiredDetail = result;
        this.isLoading    = false;
        if (result.error) {
            this.errorMessage = result.error?.body?.message ?? 'Error loading flag detail';
        } else {
            this.errorMessage = undefined;
        }
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get flagDetail() {
        return this._wiredDetail?.data;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get statusLabel() {
        const s = this.flagDetail?.summary;
        if (!s) return '';
        if (s.isKillSwitched) return 'Kill Switch';
        if (s.isExpired)      return 'Expired';
        if (s.isExpiringSoon) return 'Expiring Soon';
        if (s.isActive)       return 'Active';
        return 'Disabled';
    }

    get statusBadgeClass() {
        const s = this.flagDetail?.summary;
        if (!s) return 'status-badge';
        if (s.isKillSwitched) return 'status-badge status-badge_killswitch';
        if (s.isExpired)      return 'status-badge status-badge_expired';
        if (s.isExpiringSoon) return 'status-badge status-badge_warning';
        if (s.isActive)       return 'status-badge status-badge_active';
        return 'status-badge status-badge_disabled';
    }

    get categoryDisplay() {
        return this.flagDetail?.summary?.category ?? '—';
    }

    get expirationLabel() {
        const exp = this.flagDetail?.summary?.expirationDate;
        if (!exp) return '';
        const days = Math.round((new Date(exp) - new Date()) / (1000 * 60 * 60 * 24));
        return days < 0 ? `Expired ${Math.abs(days)}d ago`
            : days === 0 ? 'Expires today'
            : `Expires in ${days} day${days === 1 ? '' : 's'}`;
    }

    get expirationClass() {
        const exp = this.flagDetail?.summary?.expirationDate;
        if (!exp) return '';
        const days = Math.round((new Date(exp) - new Date()) / (1000 * 60 * 60 * 24));
        return days <= 0 ? 'expiry-text expiry-text_red'
            : days <= 7 ? 'expiry-text expiry-text_orange' : 'expiry-text';
    }

    get isKillSwitched() {
        return this.flagDetail?.summary?.isKillSwitched ?? false;
    }

    get killSwitchLabel() {
        return this.isKillSwitched ? 'Remove Kill Switch' : 'Kill Switch';
    }

    get killSwitchVariant() {
        return this.isKillSwitched ? 'success' : 'destructive';
    }

    get killSwitchIcon() {
        return this.isKillSwitched ? 'utility:check' : 'utility:ban';
    }

    // ── Snippet getters ──────────────────────────────────────────────────────

    get apexSnippetVariant() {
        return this.activeSnippetTab === 'apex' ? 'brand' : 'neutral';
    }

    get lwcSnippetVariant() {
        return this.activeSnippetTab === 'lwc' ? 'brand' : 'neutral';
    }

    get activeSnippet() {
        const key = this.flagDetail?.summary?.developerName ?? 'YOUR_FLAG_KEY';
        const type = this.flagDetail?.summary?.type;
        if (this.activeSnippetTab === 'apex') {
            if (type === 'Variant') {
                return `// Quick static\nString variant = FeatureFlag.getVariant('${key}');\n\n// Fluent\nString variant = FeatureFlag.flag('${key}')\n    .forUser(userId)\n    .fallback('control')\n    .getVariant();`;
            }
            return `// Quick static\nBoolean enabled = FeatureFlag.isEnabled('${key}');\n\n// Fluent with fallback\nBoolean enabled = FeatureFlag.flag('${key}')\n    .forUser(userId)\n    .fallback(false)\n    .isEnabled();`;
        }
        // LWC snippet
        if (type === 'Variant') {
            return `<c-feature-flag-variant flag-key="${key}">\n    <div slot="control">Control UI</div>\n    <div slot="treatment_a">Treatment A</div>\n</c-feature-flag-variant>`;
        }
        return `<c-feature-flag-gate flag-key="${key}">\n    <div slot="enabled">New feature UI</div>\n    <div slot="disabled">Legacy UI</div>\n</c-feature-flag-gate>`;
    }

    // ── Preview getters ──────────────────────────────────────────────────────

    get previewEnabledIcon() {
        return this.previewResult?.isEnabled ? 'utility:check' : 'utility:close';
    }

    get previewEnabledClass() {
        return this.previewResult?.isEnabled
            ? 'preview-enabled preview-enabled_yes'
            : 'preview-enabled preview-enabled_no';
    }

    get previewEnabledLabel() {
        return this.previewResult?.isEnabled ? 'true' : 'false';
    }

    get previewReasonClass() {
        const reason = this.previewResult?.reason ?? '';
        return REASON_CLASSES[reason] ?? 'reason-badge';
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleSnippetTab(event) {
        this.activeSnippetTab = event.currentTarget.dataset.snippet;
    }

    handleCopyKey() {
        const key = this.flagDetail?.summary?.developerName;
        if (!key) return;
        navigator.clipboard.writeText(key).then(() => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Copied',
                message: `Flag key "${key}" copied to clipboard`,
                variant: 'success'
            }));
        });
    }

    async handleKillSwitchToggle() {
        const flagKey = this.flagDetail?.summary?.developerName;
        if (!flagKey) return;
        const activate = !this.isKillSwitched;
        this.isLoading = true;
        try {
            await toggleKillSwitch({ flagKey, active: activate });
            await refreshApex(this._wiredDetail);
            this.dispatchEvent(new CustomEvent('killswitchtoggled', {
                detail: { flagKey, active: activate }
            }));
            this.dispatchEvent(new ShowToastEvent({
                title: activate ? 'Kill Switch Activated' : 'Kill Switch Removed',
                message: `Flag "${flagKey}" is now ${activate ? 'kill-switched' : 'restored'}.`,
                variant: activate ? 'warning' : 'success'
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

    async handleRunPreview() {
        const flagKey = this.flagDetail?.summary?.developerName;
        if (!flagKey) return;
        this.isPreviewLoading = true;
        this.previewResult    = null;
        try {
            this.previewResult = await previewEvaluation({
                flagKey,
                userId:    this.previewUserId   || null,
                attrsJson: this.previewAttrsJson || null,
            });
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Preview Error',
                message: err?.body?.message ?? 'Could not run preview',
                variant: 'error'
            }));
        } finally {
            this.isPreviewLoading = false;
        }
    }

    handlePreviewUserChange(event) {
        this.previewUserId = event.target.value;
    }

    handlePreviewAttrsChange(event) {
        this.previewAttrsJson = event.target.value;
    }

    handleRulesChanged() {
        refreshApex(this._wiredDetail);
    }

    handleVariantsChanged() {
        refreshApex(this._wiredDetail);
    }
}
