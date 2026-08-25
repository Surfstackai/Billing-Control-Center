import { LightningElement, api } from 'lwc';

const OPTIONS = [
    { label: 'Current Year', value: 'This Year' },
    { label: 'This Month', value: 'This Month' },
    { label: 'This Quarter', value: 'This Quarter' },
    { label: 'Prior Year', value: 'Last Year' },
    { label: 'Date Range', value: 'Custom' }
];

const DEFAULT_FILTER_KEY = 'This Year';

function toIsoDate(value) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
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
            this.currentStartDate = '';
            this.currentEndDate = '';
            this.emitChange();
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

    emitChange() {
        this.dispatchEvent(
            new CustomEvent('datefilterchange', {
                detail: {
                    filterKey: this.currentFilterKey,
                    startDate: this.isCustomRange ? this.currentStartDate : null,
                    endDate: this.isCustomRange ? this.currentEndDate : null
                }
            })
        );
    }
}
