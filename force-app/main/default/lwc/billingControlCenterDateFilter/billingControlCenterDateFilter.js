import { LightningElement, api } from 'lwc';

const OPTIONS = [
    { label: 'Current Year', value: 'This Year' },
    { label: 'This Month', value: 'This Month' },
    { label: 'This Quarter', value: 'This Quarter' },
    { label: 'Prior Year', value: 'Last Year' },
    { label: 'Date Range', value: 'Custom' }
];

const DEFAULT_FILTER_KEY = 'This Month';

function toIsoDate(value) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function formatDisplayDate(isoDate) {
    if (!isoDate) {
        return '';
    }
    const parts = String(isoDate).split('-');
    if (parts.length !== 3) {
        return isoDate;
    }
    const [year, month, day] = parts;
    return `${month}/${day}/${year}`;
}

function presetBounds(filterKey, today = new Date()) {
    const year = today.getFullYear();
    const month = today.getMonth();
    if (filterKey === 'This Month') {
        return {
            start: new Date(year, month, 1),
            end: new Date(year, month + 1, 0)
        };
    }
    if (filterKey === 'This Quarter') {
        const startMonth = Math.floor(month / 3) * 3;
        return {
            start: new Date(year, startMonth, 1),
            end: new Date(year, startMonth + 3, 0)
        };
    }
    if (filterKey === 'Last Year') {
        return {
            start: new Date(year - 1, 0, 1),
            end: new Date(year - 1, 11, 31)
        };
    }
    return {
        start: new Date(year, 0, 1),
        end: new Date(year, 11, 31)
    };
}

/**
 * Resolve a date-filter selection into the ISO bounds Apex must query.
 * Presets always send start/end so a dropped filterKey cannot fall back to Current Year.
 */
export function resolveDateRange(filterKey, startDate, endDate, today = new Date()) {
    const key = filterKey || DEFAULT_FILTER_KEY;
    if (key === 'Custom') {
        return {
            filterKey: key,
            startDate: startDate || null,
            endDate: endDate || null
        };
    }
    const bounds = presetBounds(key, today);
    return {
        filterKey: key,
        startDate: toIsoDate(bounds.start),
        endDate: toIsoDate(bounds.end)
    };
}

export default class BillingControlCenterDateFilter extends LightningElement {
    _selectedFilterKey = DEFAULT_FILTER_KEY;
    _startDate = '';
    _endDate = '';

    currentFilterKey = DEFAULT_FILTER_KEY;
    currentStartDate = '';
    currentEndDate = '';
    @api compact = false;
    @api label = 'Date Range';

    @api
    get selectedFilterKey() {
        return this._selectedFilterKey;
    }

    set selectedFilterKey(value) {
        this._selectedFilterKey = value || DEFAULT_FILTER_KEY;
        this.currentFilterKey = this._selectedFilterKey;
    }

    @api
    get startDate() {
        return this._startDate;
    }

    set startDate(value) {
        this._startDate = value || '';
        this.currentStartDate = this._startDate;
    }

    @api
    get endDate() {
        return this._endDate;
    }

    set endDate(value) {
        this._endDate = value || '';
        this.currentEndDate = this._endDate;
    }

    get containerClass() {
        return `bcc-date-filter${this.compact ? ' bcc-date-filter_compact' : ''}`;
    }

    get menuLabel() {
        const selected = OPTIONS.find(option => option.value === this.currentFilterKey);
        return selected ? selected.label : 'Date Filter';
    }

    get resolvedBounds() {
        return resolveDateRange(this.currentFilterKey, this.currentStartDate, this.currentEndDate);
    }

    get boundsLabel() {
        const bounds = this.resolvedBounds;
        if (!bounds.startDate || !bounds.endDate) {
            return '';
        }
        return `${formatDisplayDate(bounds.startDate)} – ${formatDisplayDate(bounds.endDate)}`;
    }

    get showBoundsLabel() {
        return !this.isCustomRange && Boolean(this.boundsLabel);
    }

    get options() {
        return OPTIONS.map(option => ({
            ...option,
            checked: option.value === this.currentFilterKey
        }));
    }

    get isCustomRange() {
        return this.currentFilterKey === 'Custom';
    }

    handleMenuSelect(event) {
        const nextKey = event.detail.value;
        this.currentFilterKey = nextKey;
        if (nextKey !== 'Custom') {
            const resolved = resolveDateRange(nextKey);
            this.currentStartDate = resolved.startDate || '';
            this.currentEndDate = resolved.endDate || '';
            this.emitChange(resolved);
            return;
        }
        if (!this.currentStartDate || !this.currentEndDate) {
            const today = new Date();
            this.currentStartDate = toIsoDate(new Date(today.getFullYear(), 0, 1));
            this.currentEndDate = toIsoDate(today);
        }
        this.emitChange();
    }

    handleStartDateChange(event) {
        this.currentStartDate = event.detail.value || '';
        this.emitCustomIfComplete();
    }

    handleEndDateChange(event) {
        this.currentEndDate = event.detail.value || '';
        this.emitCustomIfComplete();
    }

    emitCustomIfComplete() {
        if (!this.isCustomRange || !this.currentStartDate || !this.currentEndDate) {
            return;
        }
        this.emitChange();
    }

    emitChange(detail) {
        this.dispatchEvent(
            new CustomEvent('datefilterchange', {
                detail:
                    detail ||
                    resolveDateRange(this.currentFilterKey, this.currentStartDate, this.currentEndDate)
            })
        );
    }
}
