import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const CHANNEL = '/event/FlipSwitch_Evaluation__e';
const MAX_LOGS = 500; // Cap in-memory to prevent heap overflow
const SAMPLING_RATE_NOTICE =
    'Note: evaluation logs are sampled. Not all evaluations appear here. Check FlipSwitch_Config__mdt for the configured sampling rate.';

const REASON_OPTIONS = [
    { label: 'All Reasons',    value: '' },
    { label: 'Rule Match',     value: 'RULE_MATCH' },
    { label: 'Default',        value: 'DEFAULT' },
    { label: 'Emergency Disable', value: 'EMERGENCY_DISABLE' },
    { label: 'Expired',        value: 'EXPIRED' },
    { label: 'Cache Hit',      value: 'CACHE_HIT' },
    { label: 'Circuit Breaker', value: 'CIRCUIT_BREAKER' },
];

const REASON_BADGE_CLASSES = {
    RULE_MATCH:      'reason-badge reason-badge_rule',
    DEFAULT:         'reason-badge reason-badge_default',
    EMERGENCY_DISABLE: 'reason-badge reason-badge_emergency-disable',
    EXPIRED:         'reason-badge reason-badge_expired',
    CACHE_HIT:       'reason-badge reason-badge_cache',
    CIRCUIT_BREAKER: 'reason-badge reason-badge_error',
};

/**
 * @description Evaluation logs tab. Subscribes to the FlipSwitch_Evaluation__e
 *              Platform Event channel via EMP API for real-time streaming.
 *              Supports filtering by flag key, reason, and date range.
 *              Provides CSV export of the visible log set.
 */
export default class FeatureFlagEvalLogs extends LightningElement {

    /** @api Optional — pre-filter to this flag key when set by shell */
    @api flagKey;

    @track logs = [];

    filterFlagKey  = '';
    filterReason   = '';
    filterDateFrom = '';
    filterDateTo   = '';

    isStreaming    = false;
    newUnseenCount = 0;

    _subscription;
    _lastScrollTop = 0;

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        // Pre-fill flag key filter if prop is set
        if (this.flagKey) {
            this.filterFlagKey = this.flagKey;
        }
        this._subscribeToEvents();
    }

    disconnectedCallback() {
        this._unsubscribeFromEvents();
    }

    // ─── EMP API ──────────────────────────────────────────────────────────────

    async _subscribeToEvents() {
        onError(error => {
            console.error('[FeatureFlagEvalLogs] EMP API error:', error);
            this.isStreaming = false;
        });

        try {
            this._subscription = await subscribe(
                CHANNEL,
                -1, // replay from tip (new events only)
                (message) => this._handleIncomingEvent(message)
            );
            this.isStreaming = true;
        } catch (err) {
            console.error('[FeatureFlagEvalLogs] Subscribe failed:', err);
            this.isStreaming = false;
        }
    }

    _unsubscribeFromEvents() {
        if (this._subscription) {
            unsubscribe(this._subscription, () => {});
            this._subscription = null;
            this.isStreaming = false;
        }
    }

    _handleIncomingEvent(message) {
        const payload = message?.data?.payload;
        if (!payload) return;

        const log = this._buildLogEntry({
            flagKey:  payload.Flag_Key__c,
            userId:   payload.User_Id__c,
            result:   payload.Result__c,
            reason:   payload.Evaluation_Reason__c,
            context:  payload.Context__c,
            ts:       payload.Timestamp__c ?? new Date().toISOString(),
        });

        // Prepend — newest first; cap at MAX_LOGS
        this.logs = [log, ...this.logs].slice(0, MAX_LOGS);
        this.newUnseenCount++;
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get reasonOptions() {
        return REASON_OPTIONS;
    }

    get samplingRateNotice() {
        return SAMPLING_RATE_NOTICE;
    }

    get isStreaming() {
        return this._isStreaming;
    }

    set isStreaming(value) {
        this._isStreaming = value;
    }

    get streamingLabel() {
        return this._isStreaming ? 'Live' : 'Disconnected';
    }

    get streamingIndicatorClass() {
        return `streaming-indicator${this._isStreaming ? ' streaming-indicator_live' : ''}`;
    }

    get streamingDotClass() {
        return `streaming-dot${this._isStreaming ? ' streaming-dot_live' : ''}`;
    }

    get streamingTitle() {
        return this._isStreaming
            ? 'Connected to FlipSwitch_Evaluation__e Platform Event channel'
            : 'Not connected to Platform Event channel';
    }

    get displayedLogs() {
        return this.logs
            .filter(log => {
                if (this.filterFlagKey && !log.flagKey?.toLowerCase().includes(this.filterFlagKey.toLowerCase())) return false;
                if (this.filterReason  && log.reason !== this.filterReason) return false;
                if (this.filterDateFrom && log.isoDate < this.filterDateFrom) return false;
                if (this.filterDateTo   && log.isoDate > this.filterDateTo)   return false;
                return true;
            });
    }

    get displayedCount() {
        return this.displayedLogs.length;
    }

    get totalCount() {
        return this.logs.length;
    }

    get isEmpty() {
        return this.logs.length === 0;
    }

    get hasNewLogs() {
        return this.newUnseenCount > 0;
    }

    get newLogsBadge() {
        return `+${this.newUnseenCount} new`;
    }

    // ─── Log entry builder ────────────────────────────────────────────────────

    _buildLogEntry({ flagKey, userId, result, reason, context, ts }) {
        const date     = new Date(ts);
        const isoDate  = date.toISOString().substring(0, 10);
        const timeLabel = date.toLocaleTimeString([], {
            hour: '2-digit', minute: '2-digit', second: '2-digit'
        });

        const reasonBadgeClass = REASON_BADGE_CLASSES[reason] ?? 'reason-badge';

        const resultClass = result === 'true' || result === 'enabled'
            ? 'result-value result-value_enabled'
            : 'result-value result-value_disabled';

        const rowClass = reason === 'EMERGENCY_DISABLE' || reason === 'CIRCUIT_BREAKER'
            ? 'log-row log-row--alert' : 'log-row';

        return {
            id:             `${ts}_${Math.random()}`,
            flagKey,
            userId,
            userLabel:      userId ? userId.substring(0, 15) + '…' : '(unknown)',
            userAvatarUrl:  null, // would need a user query to get picture URL
            result,
            reason,
            context,
            isoDate,
            timeLabel,
            reasonBadgeClass,
            resultClass,
            rowClass,
        };
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleFilterChange(event) {
        const filter = event.currentTarget.dataset.filter;
        const value  = event.target.value;
        if (filter === 'flagKey')   this.filterFlagKey  = value;
        if (filter === 'reason')    this.filterReason   = value;
        if (filter === 'dateFrom')  this.filterDateFrom = value;
        if (filter === 'dateTo')    this.filterDateTo   = value;
        this.newUnseenCount = 0;
    }

    handleExportCsv() {
        const rows = this.displayedLogs;
        if (!rows.length) return;

        const headers = ['Time', 'Flag Key', 'User ID', 'Result', 'Reason'];
        const csvRows = rows.map(r =>
            [r.timeLabel, r.flagKey, r.userId, r.result, r.reason]
                .map(v => `"${(v ?? '').toString().replace(/"/g, '""')}"`)
                .join(',')
        );
        const csv  = [headers.join(','), ...csvRows].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url  = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href     = url;
        a.download = `flipswitch_eval_logs_${new Date().toISOString().substring(0,10)}.csv`;
        a.click();
        URL.revokeObjectURL(url);

        this.dispatchEvent(new ShowToastEvent({
            title: 'Exported',
            message: `${rows.length} log rows exported to CSV.`,
            variant: 'success'
        }));
    }
}
