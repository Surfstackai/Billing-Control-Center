import { LightningElement, api } from 'lwc';

const OPTIONS = [
    { label: 'Today', value: 'Today' },
    { label: 'This Week', value: 'This Week' },
    { label: 'This Month', value: 'This Month' },
    { label: 'This Year', value: 'This Year' }
];

export default class BillingControlCenterDateFilter extends LightningElement {
    _selectedFilterKey = 'Today';
    _compact = false;

    currentFilterKey = 'Today';

    @api
    get selectedFilterKey() {
        return this._selectedFilterKey;
    }

    set selectedFilterKey(value) {
        this._selectedFilterKey = value || 'Today';
        this.currentFilterKey = this._selectedFilterKey;
    }

    @api
    get compact() {
        return this._compact;
    }

    set compact(value) {
        this._compact = Boolean(value);
    }

    get comboboxVariant() {
        return this.compact ? 'label-hidden' : 'standard';
    }

    get containerClass() {
        return `bcc-date-filter${this.compact ? ' bcc-date-filter_compact' : ''}`;
    }

    get options() {
        return OPTIONS;
    }

    handleFilterChange(event) {
        this.currentFilterKey = event.detail.value;
        this.emitChange();
    }

    emitChange() {
        this.dispatchEvent(
            new CustomEvent('datefilterchange', {
                detail: {
                    filterKey: this.currentFilterKey
                }
            })
        );
    }
}