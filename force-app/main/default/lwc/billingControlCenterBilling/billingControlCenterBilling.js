import { LightningElement } from 'lwc';

import getServiceAppointmentBillingMetricsWithRefresh from '@salesforce/apex/BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh';
import getBillableServiceAppointmentGroupsWithRefresh from '@salesforce/apex/BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh';

const KPI_CONFIG = [
    {
        key: 'completedMoreThan2Days',
        title: 'Aged Completed Work (>2 Days)',
        icon: 'utility:clock',
        hint: 'Completed service appointments older than 2 days, unbilled.',
        isCurrency: false
    },
    {
        key: 'readyToBill',
        title: 'Billable Service Appointments',
        icon: 'utility:check',
        hint: 'Completed and unbilled service appointments.',
        isCurrency: false
    },
    {
        key: 'unbilledRevenue',
        title: 'Uninvoiced Revenue',
        icon: 'utility:money',
        hint: 'Derived from service appointment billable amounts.',
        isCurrency: true
    }
];

const CATEGORY_KEYS = ['AGED_COMPLETED', 'READY_TO_BILL', 'UNBILLED_REVENUE'];
const DEFAULT_SORT_FIELD = 'workOrderUrl';

const WORK_ORDER_COLUMNS = [
    {
        label: 'Account',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'accountName' },
            target: '_blank'
        }
    },
    {
        label: 'Opportunity',
        fieldName: 'opportunityUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'opportunityName' },
            target: '_blank'
        }
    },
    {
        label: 'Work Order',
        fieldName: 'workOrderUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'workOrderNumber' },
            target: '_blank'
        }
    },
    {
        label: 'Service Appointments',
        fieldName: 'serviceAppointmentDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }
    },
    { label: 'Subject', fieldName: 'subject', type: 'text', sortable: true, wrapText: true },
    { label: 'Work Order Status', fieldName: 'status', type: 'text', sortable: true },
    {
        label: 'Opportunity Amount',
        fieldName: 'opportunityAmount',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true }
];

function accountRecordUrl(accountId) {
    if (!accountId) {
        return null;
    }
    return `/lightning/r/Account/${accountId}/view`;
}

function opportunityRecordUrl(opportunityId) {
    if (!opportunityId) {
        return null;
    }
    return `/lightning/r/Opportunity/${opportunityId}/view`;
}

function workOrderRecordUrl(workOrderId) {
    if (!workOrderId) {
        return null;
    }
    return `/lightning/r/WorkOrder/${workOrderId}/view`;
}

function resolveSortField(fieldName) {
    if (fieldName === 'accountUrl') {
        return 'accountName';
    }
    if (fieldName === 'opportunityUrl') {
        return 'opportunityName';
    }
    if (fieldName === 'workOrderUrl') {
        return 'workOrderNumber';
    }
    return fieldName;
}

function compareRowValues(left, right, fieldName, directionMultiplier) {
    const sortField = resolveSortField(fieldName);
    let leftValue = left[sortField];
    let rightValue = right[sortField];

    if (leftValue == null && rightValue == null) {
        return 0;
    }
    if (leftValue == null) {
        return 1 * directionMultiplier;
    }
    if (rightValue == null) {
        return -1 * directionMultiplier;
    }

    if (sortField === 'opportunityAmount') {
        const leftNumber = Number(leftValue);
        const rightNumber = Number(rightValue);
        if (leftNumber < rightNumber) {
            return -1 * directionMultiplier;
        }
        if (leftNumber > rightNumber) {
            return 1 * directionMultiplier;
        }
        return 0;
    }

    if (sortField === 'createdDate') {
        const leftTime = new Date(leftValue).getTime();
        const rightTime = new Date(rightValue).getTime();
        if (leftTime < rightTime) {
            return -1 * directionMultiplier;
        }
        if (leftTime > rightTime) {
            return 1 * directionMultiplier;
        }
        return 0;
    }

    return (
        String(leftValue).localeCompare(String(rightValue), undefined, {
            numeric: true,
            sensitivity: 'base'
        }) * directionMultiplier
    );
}

function sortWorkOrderRows(rows, fieldName, direction) {
    const directionMultiplier = direction === 'desc' ? -1 : 1;
    return [...rows].sort((left, right) => {
        const primary = compareRowValues(left, right, fieldName, directionMultiplier);
        if (primary !== 0) {
            return primary;
        }
        const tieLeft = left.rowKey != null ? String(left.rowKey) : '';
        const tieRight = right.rowKey != null ? String(right.rowKey) : '';
        return tieLeft.localeCompare(tieRight) * directionMultiplier;
    });
}

function defaultSortState() {
    const next = {};
    for (const key of CATEGORY_KEYS) {
        next[key] = { sortedBy: DEFAULT_SORT_FIELD, sortDirection: 'asc' };
    }
    return next;
}

export default class BillingControlCenterBilling extends LightningElement {
    metrics = {};
    appointmentSections = [];
    selectedWorkOrderIds = new Set();
    selectedServiceAppointments = [];
    sortState = defaultSortState();
    searchKey = '';
    isLoading = true;
    isCompleteBillingModalOpen = false;
    errorMessage;

    workOrderColumns = WORK_ORDER_COLUMNS;

    connectedCallback() {
        this.loadData();
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            value: this.metrics[tile.key] || 0,
            countText: 'Service Appointments'
        }));
    }

    get isCompleteBillingDisabled() {
        return this.selectedServiceAppointments.length === 0;
    }

    get selectedOpportunityCount() {
        const opportunityIds = new Set(
            (this.selectedServiceAppointments || [])
                .map(row => row.opportunityId)
                .filter(Boolean)
        );
        return opportunityIds.size;
    }

    get accordionSections() {
        const q = this.searchKey.trim().toLowerCase();

        return (this.appointmentSections || []).map(section => {
            let rows = (section.rows || []).map(row => ({ ...row }));

            if (q) {
                rows = rows.filter(row =>
                    [
                        row.workOrderNumber,
                        row.serviceAppointmentDisplay,
                        row.subject,
                        row.status,
                        row.accountName,
                        row.opportunityName,
                        row.ownerName
                    ]
                        .filter(Boolean)
                        .some(value => String(value).toLowerCase().includes(q))
                );
            }

            const categorySort = this.sortState[section.categoryKey] || {
                sortedBy: DEFAULT_SORT_FIELD,
                sortDirection: 'asc'
            };
            rows = sortWorkOrderRows(rows, categorySort.sortedBy, categorySort.sortDirection);

            const selectedRowKeys = rows
                .filter(row => row.workOrderId && this.selectedWorkOrderIds.has(row.workOrderId))
                .map(row => row.rowKey);

            return {
                categoryKey: section.categoryKey,
                categoryLabel: section.categoryLabel,
                titleWithCount: `${section.categoryLabel} (${rows.length})`,
                filteredRows: rows,
                isEmpty: rows.length === 0,
                sortedBy: categorySort.sortedBy,
                sortDirection: categorySort.sortDirection,
                selectedRowKeys
            };
        });
    }

    get visibleAccordionSections() {
        return this.accordionSections.filter(section => section.categoryKey !== 'UNBILLED_REVENUE');
    }

    get completeBillingModalSelections() {
        return this.selectedServiceAppointments.map(row => ({
            serviceAppointmentId: row.serviceAppointmentId,
            serviceAppointmentNumber: row.serviceAppointmentNumber,
            opportunityId: row.opportunityId,
            opportunityName: row.opportunityName,
            accountName: row.accountName,
            workOrderNumber: row.workOrderNumber,
            completionDateTime: row.completionDateTime,
            technicianName: row.technicianName,
            billableAmount: row.billableAmount
        }));
    }

    get billableCount() {
        return this.metrics.readyToBill || 0;
    }

    get totalWorkOrderRows() {
        return (this.appointmentSections || []).reduce((sum, section) => sum + (section.rows || []).length, 0);
    }

    get searchSummary() {
        if (!this.searchKey.trim()) {
            return `${this.totalWorkOrderRows} records across buckets`;
        }
        const shownCount = this.visibleAccordionSections.reduce((sum, section) => sum + section.filteredRows.length, 0);
        return `Showing ${shownCount} matching records`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    handleOpenCompleteBillingModal() {
        if (this.isCompleteBillingDisabled) {
            return;
        }
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
        if (this.selectedServiceAppointments.length === 0) {
            return;
        }
        this.isCompleteBillingModalOpen = true;
    }

    handleCompleteBillingClose() {
        this.isCompleteBillingModalOpen = false;
    }

    async handleCompleteBillingSuccess() {
        this.isCompleteBillingModalOpen = false;
        this.selectedWorkOrderIds = new Set();
        this.selectedServiceAppointments = [];
        await this.loadData(true);
    }

    async handleRefresh() {
        this.selectedWorkOrderIds = new Set();
        this.selectedServiceAppointments = [];
        await this.loadData(true);
    }

    handleWorkOrderSort(event) {
        const categoryKey = this.readBucketKeyFromEvent(event);
        if (!categoryKey || !this.sortState[categoryKey]) {
            return;
        }

        const { fieldName, sortDirection } = event.detail;
        this.sortState = {
            ...this.sortState,
            [categoryKey]: { sortedBy: fieldName, sortDirection }
        };
    }

    handleRowSelection(event) {
        const categoryKey = this.readBucketKeyFromEvent(event);
        if (!categoryKey) {
            return;
        }

        const section = (this.appointmentSections || []).find(item => item.categoryKey === categoryKey);
        if (!section) {
            return;
        }

        const nextSelection = new Set(this.selectedWorkOrderIds);

        for (const row of section.rows || []) {
            if (row.workOrderId) {
                nextSelection.delete(row.workOrderId);
            }
        }

        for (const row of event.detail.selectedRows || []) {
            if (row && row.workOrderId) {
                nextSelection.add(row.workOrderId);
            }
        }

        this.selectedWorkOrderIds = nextSelection;
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
    }

    readBucketKeyFromEvent(event) {
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        for (const node of path) {
            if (node && node.dataset && node.dataset.bucket) {
                return node.dataset.bucket;
            }
        }
        return null;
    }

    async loadData(forceRefresh = false) {
        this.isLoading = true;
        this.errorMessage = undefined;
        const refreshToken = forceRefresh ? Date.now() : null;

        try {
            const [metrics, groups] = await Promise.all([
                getServiceAppointmentBillingMetricsWithRefresh({ refreshToken }),
                getBillableServiceAppointmentGroupsWithRefresh({ refreshToken })
            ]);

            this.metrics = { ...(metrics || {}) };
            this.appointmentSections = this.normalizeSections(groups || []);
            this.sortState = defaultSortState();
            this.pruneSelectedWorkOrders();
            this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
        } catch (error) {
            this.metrics = {};
            this.appointmentSections = [];
            this.selectedWorkOrderIds = new Set();
            this.selectedServiceAppointments = [];
            this.sortState = defaultSortState();
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    normalizeSections(sections) {
        return (sections || []).map(section => ({
            ...section,
            rows: (section.rows || []).map((row, index) => {
                const rowKey = row.rowKey || (row.workOrderId ? `WO-${row.workOrderId}` : `${section.categoryKey}-${index}`);
                const relatedServiceAppointments = (row.relatedServiceAppointments || []).map(appointment => ({
                    ...appointment,
                    accountName: appointment.accountName || row.accountName,
                    opportunityId: appointment.opportunityId || row.opportunityId,
                    opportunityName: appointment.opportunityName || row.opportunityName,
                    workOrderNumber: appointment.workOrderNumber || row.workOrderNumber
                }));

                return {
                    ...row,
                    rowKey,
                    accountUrl: accountRecordUrl(row.accountId),
                    opportunityUrl: opportunityRecordUrl(row.opportunityId),
                    workOrderUrl: workOrderRecordUrl(row.workOrderId),
                    relatedServiceAppointments
                };
            }),
            opportunityGroups: (section.opportunityGroups || []).map(group => ({
                ...group,
                rows: (group.rows || []).map(row => ({ ...row }))
            }))
        }));
    }

    pruneSelectedWorkOrders() {
        const availableWorkOrderIds = new Set();
        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                if (row.workOrderId) {
                    availableWorkOrderIds.add(row.workOrderId);
                }
            }
        }

        const prunedSelection = Array.from(this.selectedWorkOrderIds).filter(
            workOrderId => availableWorkOrderIds.has(workOrderId)
        );
        this.selectedWorkOrderIds = new Set(prunedSelection);
    }

    buildSelectedServiceAppointments() {
        if (!this.selectedWorkOrderIds.size) {
            return [];
        }

        const selectedRows = [];
        const seenServiceAppointmentIds = new Set();

        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                if (!row.workOrderId || !this.selectedWorkOrderIds.has(row.workOrderId)) {
                    continue;
                }

                const sourceAppointments = (row.relatedServiceAppointments || []).length
                    ? row.relatedServiceAppointments
                    : [row];

                for (const appointment of sourceAppointments) {
                    const serviceAppointmentId = appointment.serviceAppointmentId;
                    if (!serviceAppointmentId || seenServiceAppointmentIds.has(serviceAppointmentId)) {
                        continue;
                    }

                    seenServiceAppointmentIds.add(serviceAppointmentId);
                    selectedRows.push({
                        serviceAppointmentId,
                        serviceAppointmentNumber: appointment.serviceAppointmentNumber,
                        opportunityId: appointment.opportunityId || row.opportunityId,
                        opportunityName: appointment.opportunityName || row.opportunityName,
                        accountName: appointment.accountName || row.accountName,
                        workOrderNumber: appointment.workOrderNumber || row.workOrderNumber,
                        completionDateTime: appointment.completionDateTime,
                        technicianName: appointment.technicianName,
                        billableAmount: appointment.billableAmount
                    });
                }
            }
        }

        return selectedRows;
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