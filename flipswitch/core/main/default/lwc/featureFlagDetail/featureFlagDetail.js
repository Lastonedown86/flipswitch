import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFlagDetail from '@salesforce/apex/FeatureFlagAdminController.getFlagDetail';
import toggleEmergencyDisable from '@salesforce/apex/FeatureFlagAdminController.toggleEmergencyDisable';
import previewEvaluation from '@salesforce/apex/FeatureFlagAdminController.previewEvaluation';
import promoteRegistryFlag from '@salesforce/apex/FeatureFlagAdminController.promoteRegistryFlag';
import getMetrics from '@salesforce/apex/FeatureFlagAdminController.getMetrics';
import updateFlagDefinition from '@salesforce/apex/FeatureFlagAdminController.updateFlagDefinition';
import deleteFlagApex from '@salesforce/apex/FeatureFlagAdminController.deleteFlag';
import getCategories from '@salesforce/apex/FeatureFlagAdminController.getCategories';

const REASON_CLASSES = {
    RULE_MATCH: 'reason-badge reason-badge_rule',
    DEFAULT: 'reason-badge reason-badge_default',
    EMERGENCY_DISABLE: 'reason-badge reason-badge_emergencydisable',
    EXPIRED: 'reason-badge reason-badge_expired',
    CACHE_HIT: 'reason-badge reason-badge_cache',
    CIRCUIT_BREAKER: 'reason-badge reason-badge_error',
    NOT_CONFIGURED: 'reason-badge reason-badge_default'
};

const EVAL_STEPS = [
    {
        key: 'emergencydisable',
        label: 'Emergency Disable',
        icon: 'utility:ban',
        desc: 'Is_Active__c = false or Emergency_Disable rule'
    },
    { key: 'expiration', label: 'Expiration', icon: 'utility:clock', desc: 'Expiration_Date__c < TODAY' },
    { key: 'user', label: 'User Rule', icon: 'utility:user', desc: 'Exact user ID match' },
    { key: 'profile', label: 'Profile Rule', icon: 'utility:identity', desc: 'Profile-based targeting' },
    { key: 'permset', label: 'Permission Set', icon: 'utility:lock', desc: 'Permission Set membership' },
    { key: 'segment', label: 'Segment Rule', icon: 'utility:groups', desc: 'Custom segment membership' },
    { key: 'custom', label: 'Custom Field', icon: 'utility:database', desc: 'Custom field value match' },
    { key: 'percentage', label: 'Percentage', icon: 'utility:chart', desc: 'SHA-256 hash-based rollout' },
    { key: 'default', label: 'Default Value', icon: 'utility:fallback', desc: 'Falls through to Default_Value__c' }
];

const MAX_HISTORY = 5;

/**
 * @description Flag detail component: displays metadata, inline metrics,
 *              usage snippets (Apex/LWC/Flow), evaluation flow diagram,
 *              delegates rule/variant management to featureFlagRuleBuilder,
 *              and provides an interactive evaluation preview panel with history.
 */
export default class FeatureFlagDetail extends LightningElement {
    /** @api Public — set by featureFlagAdmin shell */
    @api flagKey;

    isLoading = false;
    errorMessage;

    // Snippet panel state
    activeSnippetTab = 'apex';

    // Preview panel state
    previewUserId = '';
    @track previewAttrs = [{ id: 'attr-0', key: '', value: '' }];
    _attrIdCounter = 1;
    previewResult;
    isPreviewLoading = false;
    simulationHistory = [];

    // Evaluation flow diagram
    showEvalFlow = false;

    _wiredDetail;
    _wiredMetrics;

    // Flag CRUD state
    showEditModal = false;
    showDeleteConfirm = false;
    isDeleting = false;
    existingCategories = [];

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getFlagDetail, { flagKey: '$flagKey' })
    wiredDetail(result) {
        this._wiredDetail = result;
        this.isLoading = false;
        if (result.error) {
            this.errorMessage = result.error?.body?.message ?? 'Error loading flag detail';
        } else {
            this.errorMessage = undefined;
        }
    }

    @wire(getMetrics, { flagKey: '$flagKey', startDateStr: null, endDateStr: null })
    wiredMetrics(result) {
        this._wiredMetrics = result;
    }

    @wire(getCategories)
    wiredCategories(result) {
        if (result.data) {
            this.existingCategories = result.data;
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
        if (s.isEmergencyDisabled) return 'Emergency Disable';
        if (s.isExpired) return 'Expired';
        if (s.isExpiringSoon) return 'Expiring Soon';
        if (s.isActive) return 'Active';
        return 'Disabled';
    }

    get statusBadgeClass() {
        const s = this.flagDetail?.summary;
        if (!s) return 'status-badge';
        if (s.isEmergencyDisabled) return 'status-badge status-badge_emergencydisable';
        if (s.isExpired) return 'status-badge status-badge_expired';
        if (s.isExpiringSoon) return 'status-badge status-badge_warning';
        if (s.isActive) return 'status-badge status-badge_active';
        return 'status-badge status-badge_disabled';
    }

    get categoryDisplay() {
        return this.flagDetail?.summary?.category ?? '—';
    }

    // ── Inline metrics getters ──────────────────────────────────────────────

    get metrics() {
        return this._wiredMetrics?.data;
    }

    get hasMetrics() {
        return !!this.metrics && this.metrics.totalEvaluations > 0;
    }

    get metricsTotal() {
        return this.metrics?.totalEvaluations?.toLocaleString() ?? '0';
    }

    get metricsUniqueUsers() {
        return this.metrics?.uniqueUsers?.toLocaleString() ?? '0';
    }

    get metricsCBTrips() {
        return this.metrics?.circuitBreakerTrips?.toLocaleString() ?? '0';
    }

    get metricsCBClass() {
        return (this.metrics?.circuitBreakerTrips ?? 0) > 0
            ? 'mini-kpi__value mini-kpi__value_warning'
            : 'mini-kpi__value';
    }

    get activeRuleCount() {
        const rules = this.flagDetail?.rules;
        if (!rules) return '0';
        return rules.filter((r) => r.Is_Active__c).length.toString();
    }

    // ── Evaluation flow getters ─────────────────────────────────────────────

    get evalSteps() {
        const rules = this.flagDetail?.rules ?? [];
        const activeTypes = new Set(rules.filter((r) => r.Is_Active__c).map((r) => r.Rule_Type__c));
        return EVAL_STEPS.map((step, idx) => ({
            ...step,
            index: idx + 1,
            isActive:
                step.key === 'emergencydisable' ||
                step.key === 'expiration' ||
                step.key === 'default' ||
                activeTypes.has(this._evalStepToRuleType(step.key)),
            cssClass:
                'eval-step' +
                (step.key === 'emergencydisable' ||
                step.key === 'expiration' ||
                step.key === 'default' ||
                activeTypes.has(this._evalStepToRuleType(step.key))
                    ? ' eval-step_active'
                    : ' eval-step_inactive')
        }));
    }

    _evalStepToRuleType(key) {
        const map = {
            user: 'User',
            profile: 'Profile',
            permset: 'Permission_Set',
            segment: 'Segment',
            custom: 'Custom_Field',
            percentage: 'Percentage'
        };
        return map[key] ?? key;
    }

    get evalFlowIcon() {
        return this.showEvalFlow ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get expirationLabel() {
        const exp = this.flagDetail?.summary?.expirationDate;
        if (!exp) return '';
        const days = Math.round((new Date(exp) - new Date()) / (1000 * 60 * 60 * 24));
        return days < 0
            ? `Expired ${Math.abs(days)}d ago`
            : days === 0
              ? 'Expires today'
              : `Expires in ${days} day${days === 1 ? '' : 's'}`;
    }

    get expirationClass() {
        const exp = this.flagDetail?.summary?.expirationDate;
        if (!exp) return '';
        const days = Math.round((new Date(exp) - new Date()) / (1000 * 60 * 60 * 24));
        return days <= 0 ? 'expiry-text expiry-text_red' : days <= 7 ? 'expiry-text expiry-text_orange' : 'expiry-text';
    }

    get isEmergencyDisabled() {
        return this.flagDetail?.summary?.isEmergencyDisabled ?? false;
    }

    get emergencyDisableLabel() {
        return this.isEmergencyDisabled ? 'Remove Emergency Disable' : 'Emergency Disable';
    }

    get emergencyDisableVariant() {
        return this.isEmergencyDisabled ? 'success' : 'destructive';
    }

    get emergencyDisableIcon() {
        return this.isEmergencyDisabled ? 'utility:check' : 'utility:ban';
    }

    // ── Source getters ──────────────────────────────────────────────────────

    get sourceLabel() {
        return this.flagDetail?.summary?.source ?? 'Deployed';
    }

    get sourceBadgeClass() {
        return this.sourceLabel === 'Code' ? 'source-badge source-badge_code' : 'source-badge source-badge_deployed';
    }

    get isCodeSource() {
        return this.sourceLabel === 'Code';
    }

    get isDeployedSource() {
        return this.flagDetail?.source === 'Deployed';
    }

    get deleteButtonLabel() {
        return this.isDeleting ? 'Deleting…' : 'Delete Flag';
    }

    // ── Snippet getters ──────────────────────────────────────────────────────

    get apexSnippetVariant() {
        return this.activeSnippetTab === 'apex' ? 'brand' : 'neutral';
    }

    get lwcSnippetVariant() {
        return this.activeSnippetTab === 'lwc' ? 'brand' : 'neutral';
    }

    get flowSnippetVariant() {
        return this.activeSnippetTab === 'flow' ? 'brand' : 'neutral';
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
        if (this.activeSnippetTab === 'flow') {
            return `Flow: Use the "Evaluate Feature Flag" action\n  Input:  Flag_Key = "${key}"\n  Output: {!isEnabled} → Boolean\n          {!variantKey} → Text\n          {!payload} → Text\n\nUse a Decision element after to branch\non the {!isEnabled} output variable.`;
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

    // ── Simulation history getters ──────────────────────────────────────────

    get hasSimulationHistory() {
        return this.simulationHistory.length > 0;
    }

    get hasNoSimulationHistory() {
        return this.simulationHistory.length === 0;
    }

    get simulationHistoryFormatted() {
        return this.simulationHistory.map((h, idx) => ({
            ...h,
            key: `sim-${idx}`,
            enabledClass: h.isEnabled ? 'preview-enabled_yes' : 'preview-enabled_no',
            enabledLabel: h.isEnabled ? 'true' : 'false',
            reasonClass: REASON_CLASSES[h.reason] ?? 'reason-badge'
        }));
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleSnippetTab(event) {
        this.activeSnippetTab = event.currentTarget.dataset.snippet;
    }

    handleCopySnippet() {
        const snippet = this.activeSnippet;
        if (!snippet) return;
        navigator.clipboard.writeText(snippet).then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Copied',
                    message: 'Code snippet copied to clipboard',
                    variant: 'success'
                })
            );
        });
    }

    handleCopyKey() {
        const key = this.flagDetail?.summary?.developerName;
        if (!key) return;
        navigator.clipboard.writeText(key).then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Copied',
                    message: `Flag key "${key}" copied to clipboard`,
                    variant: 'success'
                })
            );
        });
    }

    handleActionMenu(event) {
        const action = event.detail.value;
        if (action === 'emergencydisable') {
            this.handleEmergencyDisableToggle();
        } else if (action === 'promote') {
            this.handlePromoteFlag();
        } else if (action === 'edit') {
            this.handleEditFlag();
        } else if (action === 'delete') {
            this.handleDeleteFlag();
        }
    }

    async handleEmergencyDisableToggle() {
        const flagKey = this.flagDetail?.summary?.developerName;
        if (!flagKey) return;
        const activate = !this.isEmergencyDisabled;
        this.isLoading = true;
        try {
            await toggleEmergencyDisable({ flagKey, active: activate });
            await refreshApex(this._wiredDetail);
            this.dispatchEvent(
                new CustomEvent('emergencydisabletoggled', {
                    detail: { flagKey, active: activate }
                })
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: activate ? 'Emergency Disable Activated' : 'Emergency Disable Removed',
                    message: `Flag "${flagKey}" is now ${activate ? 'emergency-disabled' : 'restored'}.`,
                    variant: activate ? 'warning' : 'success'
                })
            );
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: err?.body?.message ?? 'Could not toggle emergency disable',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunPreview() {
        const flagKey = this.flagDetail?.summary?.developerName;
        if (!flagKey) return;

        let attrsJsonString = null;
        const validAttrs = this.previewAttrs.filter((a) => a.key && a.key.trim().length > 0);
        if (validAttrs.length > 0) {
            const attrsObj = {};
            validAttrs.forEach((a) => {
                attrsObj[a.key.trim()] = a.value;
            });
            attrsJsonString = JSON.stringify(attrsObj);
        }

        this.isPreviewLoading = true;
        this.previewResult = null;
        try {
            const result = await previewEvaluation({
                flagKey,
                userId: this.previewUserId || null,
                attrsJson: attrsJsonString || null
            });
            this.previewResult = result;
            // Store in simulation history
            const entry = {
                timestamp: new Date().toLocaleTimeString(),
                userId: this.previewUserId || '(current user)',
                attrs: attrsJsonString || '—',
                isEnabled: result.isEnabled,
                variant: result.variant || null,
                reason: result.reason
            };
            this.simulationHistory = [entry, ...this.simulationHistory].slice(0, MAX_HISTORY);
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Preview Error',
                    message: err?.body?.message ?? 'Could not run preview',
                    variant: 'error'
                })
            );
        } finally {
            this.isPreviewLoading = false;
        }
    }

    handlePreviewUserChange(event) {
        this.previewUserId = event.target.value;
    }

    handleAddAttr() {
        this.previewAttrs.push({ id: `attr-${this._attrIdCounter++}`, key: '', value: '' });
    }

    handleRemoveAttr(event) {
        const id = event.currentTarget.dataset.id;
        this.previewAttrs = this.previewAttrs.filter((a) => a.id !== id);
        if (this.previewAttrs.length === 0) {
            this.handleAddAttr();
        }
    }

    handleAttrKeyChange(event) {
        const id = event.currentTarget.dataset.id;
        const attr = this.previewAttrs.find((a) => a.id === id);
        if (attr) attr.key = event.target.value;
    }

    handleAttrValueChange(event) {
        const id = event.currentTarget.dataset.id;
        const attr = this.previewAttrs.find((a) => a.id === id);
        if (attr) attr.value = event.target.value;
    }

    handleRulesChanged() {
        refreshApex(this._wiredDetail);
    }

    handleVariantsChanged() {
        refreshApex(this._wiredDetail);
    }

    handleToggleEvalFlow() {
        this.showEvalFlow = !this.showEvalFlow;
    }

    handleClearHistory() {
        this.simulationHistory = [];
    }

    handleViewLogs() {
        this.dispatchEvent(
            new CustomEvent('navigatetologs', {
                detail: { flagKey: this.flagDetail?.summary?.developerName }
            })
        );
    }

    handleViewAnalytics() {
        this.dispatchEvent(
            new CustomEvent('navigatetoanalytics', {
                detail: { flagKey: this.flagDetail?.summary?.developerName }
            })
        );
    }

    async handlePromoteFlag() {
        const flagKey = this.flagDetail?.summary?.developerName;
        if (!flagKey) return;
        this.isLoading = true;
        try {
            await promoteRegistryFlag({ flagKey });
            await refreshApex(this._wiredDetail);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Flag Promoted',
                    message: `"${flagKey}" has been marked for promotion to CMDT.`,
                    variant: 'success'
                })
            );
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: err?.body?.message ?? 'Could not promote flag',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    // ── Flag CRUD ────────────────────────────────────────────────────────────

    get deleteChildCount() {
        const rules = this.flagDetail?.rules?.length ?? 0;
        const variants = this.flagDetail?.variants?.length ?? 0;
        const parts = [];
        if (rules > 0) parts.push(`${rules} rule${rules > 1 ? 's' : ''}`);
        if (variants > 0) parts.push(`${variants} variant${variants > 1 ? 's' : ''}`);
        return parts.length > 0 ? parts.join(' and ') : 'no child records';
    }

    handleEditFlag() {
        this.showEditModal = true;
        // Set flag data on the modal after render
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const modal = this.template.querySelector('c-feature-flag-form-modal');
            if (modal) {
                const s = this.flagDetail.summary;
                modal.setFlagData({
                    developerName: s.developerName,
                    label: s.label,
                    description: s.description,
                    type: s.type,
                    defaultValue: s.defaultValue,
                    category: s.category,
                    expirationDate: s.expirationDate,
                    isActive: s.isActive,
                    source: this.flagDetail.source
                });
            }
        }, 0);
    }

    handleEditModalCancel() {
        this.showEditModal = false;
    }

    async handleEditModalSave(event) {
        const input = event.detail;
        input.storageTarget = this.flagDetail?.source === 'Deployed' ? 'CMDT' : 'Registry';
        try {
            const result = await updateFlagDefinition({ input });
            this.showEditModal = false;
            await refreshApex(this._wiredDetail);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Flag Updated',
                    message: result.isAsync
                        ? `CMDT deployment queued for "${input.flagKey}". Changes will appear after deployment.`
                        : `Flag "${input.flagKey}" updated successfully.`,
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('flagupdated', {
                    detail: { flagKey: input.flagKey }
                })
            );
        } catch (err) {
            const modal = this.template.querySelector('c-feature-flag-form-modal');
            if (modal) modal.resetSaving();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Updating Flag',
                    message: err?.body?.message ?? 'Could not update flag',
                    variant: 'error'
                })
            );
        }
    }

    handleDeleteFlag() {
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
    }

    async handleDeleteConfirm() {
        const flagKey = this.flagDetail?.summary?.developerName;
        const source = this.flagDetail?.source ?? 'Code';
        if (!flagKey) return;
        this.isDeleting = true;
        try {
            await deleteFlagApex({ flagKey, source });
            this.showDeleteConfirm = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Flag Deleted',
                    message:
                        source === 'Deployed'
                            ? `Flag "${flagKey}" marked for removal. Children deleted.`
                            : `Flag "${flagKey}" and all associated data deleted.`,
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('flagdeleted', {
                    detail: { flagKey }
                })
            );
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Deleting Flag',
                    message: err?.body?.message ?? 'Could not delete flag',
                    variant: 'error'
                })
            );
        } finally {
            this.isDeleting = false;
        }
    }
}
