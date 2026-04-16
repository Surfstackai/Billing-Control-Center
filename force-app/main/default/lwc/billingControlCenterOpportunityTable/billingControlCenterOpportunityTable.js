import { LightningElement, api } from 'lwc';

const COLUMN_CONFIG = [
    { label: 'Service Appointment #', fieldName: 'serviceAppointmentNumber' },
    { label: 'Opportunity Name', fieldName: 'opportunityName' },
    { label: 'Account', fieldName: 'accountName' },
    { label: 'Work Order Number', fieldName: 'workOrderNumber' },
    { label: 'Completion Date', fieldName: 'completionDateTime' },
    { label: 'Technician', fieldName: 'technicianName' },
    { label: 'Billable Amount', fieldName: 'billableAmount' },
    { label: 'Billing Status', fieldName: 'billingStatus' }
];

export default class BillingControlCenterOpportunityTable extends LightningElement {
    _opportunityGroups = [];
    displayedRows = [];
    selectedRowIds = [];
    sortedBy = 'completionDateTime';
    sortDirection = 'desc';

    @api emptyMessage = 'No records found.';
    @api tableLabel = 'Service appointments grouped by opportunity';

    @api
    set opportunityGroups(value) {
        this._opportunityGroups = (value || []).map(group => ({
            ...group,
            rows: (group.rows || []).map(row => ({ ...row }))
        }));
        this.pruneState();
        this.rebuildRows();
    }

    get opportunityGroups() {
        return this._opportunityGroups;
    }

    get hasRows() {
        return this.totalRowCount > 0;
    }

    get totalRowCount() {
        return this._opportunityGroups.reduce((sum, group) => sum + (group.rows || []).length, 0);
    }

    get allRowsSelected() {
        return this.totalRowCount > 0 && this.selectedRowIds.length === this.totalRowCount;
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
            this.sortDirection = fieldName === 'completionDateTime' ? 'desc' : 'asc';
        }
        this.rebuildRows();
    }

    handleSelectAll(event) {
        if (event.target.checked) {
            const ids = [];
            for (const group of this._opportunityGroups) {
                for (const row of group.rows || []) {
                    ids.push(row.serviceAppointmentId);
                }
            }
            this.selectedRowIds = ids;
        } else {
            this.selectedRowIds = [];
        }
        this.rebuildRows();
        this.notifySelectionChange();
    }

    handleRowSelection(event) {
        const rowId = event.target.dataset.id;
        if (!rowId) {
            return;
        }

        const selected = new Set(this.selectedRowIds);
        if (event.target.checked) {
            selected.add(rowId);
        } else {
            selected.delete(rowId);
        }
        this.selectedRowIds = Array.from(selected);
        this.rebuildRows();
        this.notifySelectionChange();
    }

    handleNavigateToServiceAppointment(event) {
        const rowId = event.currentTarget.dataset.id;
        if (!rowId) {
            return;
        }
        window.open('/lightning/r/ServiceAppointment/' + rowId + '/view', '_blank');
    }

    handleNavigateToWorkOrder(event) {
        const workOrderId = event.currentTarget.dataset.id;
        if (!workOrderId) {
            return;
        }
        window.open('/lightning/r/WorkOrder/' + workOrderId + '/view', '_blank');
    }

    pruneState() {
        const availableRowIds = new Set();
        for (const group of this._opportunityGroups) {
            for (const row of group.rows || []) {
                availableRowIds.add(row.serviceAppointmentId);
            }
        }

        this.selectedRowIds = this.selectedRowIds.filter(id => availableRowIds.has(id));
    }

    rebuildRows() {
        const selectedIds = new Set(this.selectedRowIds);

        const flattenedRows = [];
        for (const group of this._opportunityGroups) {
            for (const row of group.rows || []) {
                flattenedRows.push({
                    ...row,
                    opportunityId: row.opportunityId || group.opportunityId,
                    opportunityName: row.opportunityName || group.opportunityName,
                    accountName: row.accountName || group.accountName
                });
            }
        }

        this.displayedRows = flattenedRows
            .sort((left, right) => this.compareValues(left[this.sortedBy], right[this.sortedBy], this.sortDirection))
            .map(row => ({
                ...row,
                key: `${row.opportunityId || 'NO_OPP'}-${row.serviceAppointmentId}`,
                isSelected: selectedIds.has(row.serviceAppointmentId),
                selectLabel: `Select ${row.serviceAppointmentNumber || row.serviceAppointmentId}`,
                hasWorkOrder: !!row.workOrderId
            }));
    }

    notifySelectionChange() {
        const selectedIds = new Set(this.selectedRowIds);
        const selectedRows = [];
        for (const group of this._opportunityGroups) {
            for (const row of group.rows || []) {
                if (selectedIds.has(row.serviceAppointmentId)) {
                    selectedRows.push({ ...row });
                }
            }
        }

        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: {
                selectedIds: [...this.selectedRowIds],
                selectedCount: this.selectedRowIds.length,
                selectedRows
            }
        }));
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

        return String(leftValue).localeCompare(String(rightValue), undefined, {
            numeric: true,
            sensitivity: 'base'
        }) * multiplier;
    }
}
