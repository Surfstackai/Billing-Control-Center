import { LightningElement } from 'lwc';

import getOpportunityBillingMetrics from '@salesforce/apex/BillingControl_Invoicing.getOpportunityBillingMetrics';
import getReadyForBillingOpportunities from '@salesforce/apex/BillingControl_Invoicing.getReadyForBillingOpportunities';

const KPI_CONFIG = [
    {
        key: 'readyForBillingLast2Days',
        title: 'Ready for Billing (Last 2 Days)',
        icon: 'utility:check',
        hint: 'Billing Status = Ready for Billing',
        isCurrency: false
    },
    {
        key: 'awaitedBilling',
        title: 'Awaited Billing',
        icon: 'utility:clock',
        hint: 'Ready for Billing before the last 2 days',
        isCurrency: false
    },
    {
        key: 'outstandingReceivables',
        title: 'Outstanding Receivables',
        icon: 'utility:moneybag',
        hint: 'Billing Status = Billed (Outstanding Receivable)',
        isCurrency: false
    },
    {
        key: 'totalUnbilledRevenue',
        title: 'Total Unbilled Revenue',
        icon: 'utility:money',
        hint: 'Opportunity Amount where billing is still ready',
        isCurrency: true
    }
];

const COLUMN_CONFIG = [
    { label: 'Name', fieldName: 'name' },
    { label: 'Account', fieldName: 'accountName' },
    { label: 'Stage', fieldName: 'stage' },
    { label: 'Amount', fieldName: 'amount' },
    { label: 'Close Date', fieldName: 'closeDate' },
    { label: 'Owner', fieldName: 'ownerName' }
];

export default class BillingControlCenterOpportunityOrders extends LightningElement {
    opportunities = [];
    metrics = {};
    displayedRows = [];
    selectedRowIds = [];
    expandedRowIds = [];
    sortedBy = 'closeDate';
    sortDirection = 'asc';
    isLoading = true;
    errorMessage;

    connectedCallback() {
        this.loadData();
    }

    get hasRows() {
        return this.displayedRows.length > 0;
    }

    get selectedCount() {
        return this.selectedRowIds.length;
    }

    get allRowsSelected() {
        return this.displayedRows.length > 0 && this.selectedRowIds.length === this.displayedRows.length;
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            value: this.metrics[tile.key] || 0
        }));
    }

    get displayedOpportunityCount() {
        return this.displayedRows.length;
    }

    get headerTitle() {
        return `Orders Pending Completion (${this.displayedOpportunityCount})`;
    }

    get headerSubtitle() {
        return `${this.displayedOpportunityCount} items � Sorted by Status`;
    }

    get columns() {
        return COLUMN_CONFIG.map(column => {
            const isSorted = this.sortedBy === column.fieldName;
            const isAscending = this.sortDirection === 'asc';

            return {
                ...column,
                isSorted,
                ariaSort: isSorted ? (isAscending ? 'ascending' : 'descending') : 'none',
                sortIcon: isAscending ? 'utility:arrowup' : 'utility:arrowdown',
                sortAltText: isAscending ? 'Sorted ascending' : 'Sorted descending'
            };
        });
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.field;
        if (!fieldName) {
            return;
        }

        if (this.sortedBy === fieldName) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = fieldName;
            this.sortDirection = 'asc';
        }

        this.rebuildRows();
    }

    handleSelectAll(event) {
        this.selectedRowIds = event.target.checked ? this.displayedRows.map(row => row.opportunityId) : [];
        this.rebuildRows();
    }

    handleRowSelection(event) {
        const opportunityId = event.target.dataset.id;
        if (!opportunityId) {
            return;
        }

        const nextSelection = new Set(this.selectedRowIds);
        if (event.target.checked) {
            nextSelection.add(opportunityId);
        } else {
            nextSelection.delete(opportunityId);
        }

        this.selectedRowIds = Array.from(nextSelection);
        this.rebuildRows();
    }

    handleToggleRow(event) {
        const opportunityId = event.currentTarget.dataset.id;
        if (!opportunityId) {
            return;
        }

        const nextExpanded = new Set(this.expandedRowIds);
        if (nextExpanded.has(opportunityId)) {
            nextExpanded.delete(opportunityId);
        } else {
            nextExpanded.add(opportunityId);
        }

        this.expandedRowIds = Array.from(nextExpanded);
        this.rebuildRows();
    }

    handleNavigateToOpportunity(event) {
        const opportunityId = event.currentTarget.dataset.id;
        if (!opportunityId) {
            return;
        }

        window.open('/lightning/r/Opportunity/' + opportunityId + '/view', '_blank');
    }

    openWorkOrder(event) {
        const workOrderId = event.currentTarget.dataset.id;
        if (!workOrderId) {
            return;
        }

        window.open('/lightning/r/WorkOrder/' + workOrderId + '/view', '_blank');
    }

    async handleRefresh() {
        await this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const [metrics, opportunities] = await Promise.all([
                getOpportunityBillingMetrics(),
                getReadyForBillingOpportunities()
            ]);

            this.metrics = metrics || {};
            this.opportunities = (opportunities || []).map(opportunity => ({
                ...opportunity,
                workOrders: (opportunity.workOrders || []).map(workOrder => ({
                    id: workOrder.id,
                    workOrderNumber: workOrder.workOrderNumber,
                    subject: workOrder.subject,
                    priority: workOrder.priority,
                    workTypeName: workOrder.workTypeName
                }))
            }));
            this.rebuildRows();
        } catch (error) {
            this.metrics = {};
            this.opportunities = [];
            this.displayedRows = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    rebuildRows() {
        const selectedIds = new Set(this.selectedRowIds);
        const expandedIds = new Set(this.expandedRowIds);
        const sortedOpportunities = [...this.opportunities].sort((left, right) =>
            this.compareValues(left[this.sortedBy], right[this.sortedBy], this.sortDirection)
        );

        this.displayedRows = sortedOpportunities.map(opportunity => {
            const isExpanded = expandedIds.has(opportunity.opportunityId);
            return {
                ...opportunity,
                isSelected: selectedIds.has(opportunity.opportunityId),
                isExpanded,
                hasWorkOrders: (opportunity.workOrders || []).length > 0,
                expandIcon: isExpanded ? 'utility:dash' : 'utility:add',
                expandAltText: isExpanded ? 'Collapse Work Orders' : 'Expand Work Orders',
                workOrderHeaderKey: opportunity.opportunityId + '-work-order-header',
                selectLabel: `Select ${opportunity.name}`,
                workOrders: (opportunity.workOrders || []).map(workOrder => ({
                    ...workOrder,
                    workOrderNumber: workOrder.workOrderNumber || '',
                    key: `${opportunity.opportunityId}-${workOrder.id}`
                }))
            };
        });
    }

    compareValues(leftValue, rightValue, direction) {
        const multiplier = direction === 'asc' ? 1 : -1;

        if (leftValue === rightValue) {
            return 0;
        }
        if (leftValue === null || leftValue === undefined || leftValue === '') {
            return 1 * multiplier;
        }
        if (rightValue === null || rightValue === undefined || rightValue === '') {
            return -1 * multiplier;
        }
        if (typeof leftValue === 'number' && typeof rightValue === 'number') {
            return (leftValue - rightValue) * multiplier;
        }

        const leftDate = Date.parse(leftValue);
        const rightDate = Date.parse(rightValue);
        if (!Number.isNaN(leftDate) && !Number.isNaN(rightDate)) {
            return (leftDate - rightDate) * multiplier;
        }

        return String(leftValue).localeCompare(String(rightValue)) * multiplier;
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map(item => item.message).join(', ');
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}
