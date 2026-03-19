import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMetrics from '@salesforce/apex/FeatureFlagAdminController.getMetrics';

const SEGMENT_COLORS = [
    '#0176d3', '#6366f1', '#22c55e', '#f59e0b',
    '#ec4899', '#14b8a6', '#f97316', '#8b5cf6',
    '#ef4444', '#84cc16',
];

const CIRCUMFERENCE = 2 * Math.PI * 70; // r=70

/**
 * @description Analytics tab component. Renders a variant distribution donut,
 *              unique-user horizontal bars, and a daily volume sparkline —
 *              all using inline SVG/CSS (no external charting library required).
 *              Date range controls refresh all charts simultaneously.
 */
export default class FeatureFlagAnalytics extends LightningElement {

    /** @api Set by featureFlagAdmin shell */
    @api flagKey;

    isLoading  = false;
    errorMessage;

    // Date range — default last 30 days
    startDate = this._daysAgo(30);
    endDate   = this._daysAgo(0);

    _wiredMetrics;
    analytics;

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getMetrics, {
        flagKey:      '$flagKey',
        startDateStr: '$startDate',
        endDateStr:   '$endDate',
    })
    wiredMetrics(result) {
        this._wiredMetrics = result;
        this.isLoading     = false;
        if (result.data) {
            this.analytics    = result.data;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.analytics    = null;
            this.errorMessage = result.error?.body?.message ?? 'Error loading analytics';
        }
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get noFlagSelected() {
        return !this.flagKey;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasVariants() {
        return this.analytics?.variantStats?.length > 0;
    }

    get hasDailyStats() {
        return this.analytics?.dailyStats?.length > 0;
    }

    get variantCount() {
        return this.analytics?.variantStats?.length ?? 0;
    }

    // ── Donut chart ──────────────────────────────────────────────────────────

    get donutSegments() {
        if (!this.hasVariants) return [];
        const stats  = this.analytics.variantStats;
        const total  = this.analytics.totalEvaluations || 1;
        let offset   = 0;

        return stats.map((vs, idx) => {
            const fraction  = vs.count / total;
            const arcLen    = fraction * CIRCUMFERENCE;
            const dashArray = `${arcLen} ${CIRCUMFERENCE - arcLen}`;
            const dashOffset = -offset;
            offset += arcLen;
            return {
                key:        vs.variantKey ?? `v${idx}`,
                color:      SEGMENT_COLORS[idx % SEGMENT_COLORS.length],
                dashArray,
                dashOffset,
            };
        });
    }

    get variantLegendItems() {
        if (!this.hasVariants) return [];
        return this.analytics.variantStats.map((vs, idx) => ({
            key:        vs.variantKey ?? `v${idx}`,
            count:      vs.count,
            percentage: vs.percentage,
            dotStyle:   `background:${SEGMENT_COLORS[idx % SEGMENT_COLORS.length]}`,
        }));
    }

    // ── Unique user bars ─────────────────────────────────────────────────────

    get uniqueUserBars() {
        if (!this.hasVariants) return [];
        const maxUsers = Math.max(...this.analytics.variantStats.map(v => v.uniqueUsers), 1);
        return this.analytics.variantStats.map((vs, idx) => ({
            key:        vs.variantKey ?? `v${idx}`,
            uniqueUsers: vs.uniqueUsers,
            style:      `width:${(vs.uniqueUsers / maxUsers * 100).toFixed(1)}%;` +
                        `background:${SEGMENT_COLORS[idx % SEGMENT_COLORS.length]}`,
        }));
    }

    // ── Daily sparkline ──────────────────────────────────────────────────────

    get sparklineBars() {
        if (!this.hasDailyStats) return [];
        const stats  = this.analytics.dailyStats;
        const maxCnt = Math.max(...stats.map(d => d.count), 1);
        return stats.map(d => ({
            date:    d.evalDate,
            count:   d.count,
            style:   `height:${(d.count / maxCnt * 100).toFixed(1)}%;` +
                     `background:#0176d3`,
            tooltip: `${d.evalDate}: ${d.count} evaluations`,
        }));
    }

    get sparklineFirstDate() {
        return this.analytics?.dailyStats?.[0]?.evalDate ?? '';
    }

    get sparklineLastDate() {
        const stats = this.analytics?.dailyStats;
        return stats?.length > 0 ? stats[stats.length - 1].evalDate : '';
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    handleRefresh() {
        refreshApex(this._wiredMetrics);
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    _daysAgo(n) {
        const d = new Date();
        d.setDate(d.getDate() - n);
        return d.toISOString().substring(0, 10);
    }
}
