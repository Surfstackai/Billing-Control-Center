import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import searchOpportunities from '@salesforce/apex/LookupSearchController.searchOpportunities';

const SEARCH_DELAY_MS = 250;

export default class WorkOrderOpportunityLookup extends LightningElement {
    @api label = 'Opportunity';
    @api placeholder = 'Search opportunities';
    @api required = false;
    @api allowedOpportunityIdsCsv;

    @track results = [];
    @track searchText = '';
    @track isDropdownOpen = false;
    @track errorMessage;

    _selectedOpportunityId;
    selectedOpportunityName;
    searchTimeout;
    connected = false;

    @api
    get selectedOpportunityId() {
        return this._selectedOpportunityId;
    }

    set selectedOpportunityId(value) {
        this._selectedOpportunityId = value;
    }

    connectedCallback() {
        this.connected = true;
        this.runSearch();
    }

    get allowedOpportunityIds() {
        if (!this.allowedOpportunityIdsCsv) {
            return [];
        }

        return this.allowedOpportunityIdsCsv
            .split(',')
            .map((id) => id.trim())
            .filter((id) => Boolean(id));
    }

    get hasSelection() {
        return Boolean(this.selectedOpportunityId);
    }

    get showDropdown() {
        return this.isDropdownOpen && !this.hasSelection;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get containerClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
            this.showDropdown ? 'slds-is-open' : ''
        }`;
    }

    handleInputFocus() {
        this.isDropdownOpen = true;
        if (!this.results.length) {
            this.runSearch();
        }
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
        this.isDropdownOpen = true;

        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.runSearch();
        }, SEARCH_DELAY_MS);
    }

    async runSearch() {
        if (!this.connected) {
            return;
        }

        if (!this.allowedOpportunityIds.length) {
            this.results = [];
            this.errorMessage = this.required ? 'No open opportunities are available for this work order.' : null;
            return;
        }

        try {
            const opportunities = await searchOpportunities({
                allowedIds: this.allowedOpportunityIds,
                searchText: this.searchText
            });

            this.results = (opportunities || []).map((item) => ({
                ...item,
                detail: this.buildDetail(item)
            }));
            this.errorMessage = null;
        } catch (error) {
            this.results = [];
            this.errorMessage =
                error?.body?.message || 'We could not load the filtered opportunity list.';
        }
    }

    buildDetail(item) {
        const parts = [];

        if (item.stageName) {
            parts.push(item.stageName);
        }

        if (item.amount !== null && item.amount !== undefined) {
            parts.push(
                new Intl.NumberFormat('en-US', {
                    style: 'currency',
                    currency: 'USD',
                    maximumFractionDigits: 2
                }).format(item.amount)
            );
        }

        return parts.join(' | ');
    }

    handleSelect(event) {
        this.selectedOpportunityId = event.currentTarget.dataset.id;
        this.selectedOpportunityName = event.currentTarget.dataset.name;
        this.isDropdownOpen = false;
        this.searchText = '';
        this.dispatchFlowValueChange();
    }

    handleClearSelection() {
        this.selectedOpportunityId = null;
        this.selectedOpportunityName = null;
        this.searchText = '';
        this.isDropdownOpen = true;
        this.dispatchFlowValueChange();
        this.runSearch();
    }

    dispatchFlowValueChange() {
        this.dispatchEvent(
            new FlowAttributeChangeEvent('selectedOpportunityId', this.selectedOpportunityId)
        );
    }
    @api
    validate() {
        if (this.required && !this.selectedOpportunityId) {
            return {
                isValid: false,
                errorMessage: 'Select an opportunity to continue.'
            };
        }

        return { isValid: true };
    }
}