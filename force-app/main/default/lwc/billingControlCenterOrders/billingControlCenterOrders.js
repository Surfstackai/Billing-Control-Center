import { LightningElement } from 'lwc';

import getKpis from '@salesforce/apex/BillingControl_Orders.getKpis';
import getBucketWorkOrders from '@salesforce/apex/BillingControl_Orders.getBucketWorkOrders';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');

const BUCKET_KEYS = ['UNSCHEDULED', 'SCHEDULED', 'SCHEDULED_TODAY', 'COMPLETED_TODAY'];

const DEFAULT_SORT_FIELD = 'workOrderUrl';

const KPI_CONFIG = [
    {
        key: 'unscheduled',
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Unscheduled Work',
        icon: 'utility:date_input',
        hint: 'Work orders in For Clearance or For Appointment Booking.'
    },
    {
        key: 'scheduled',
        revenueKey: 'scheduledRevenue',
        countKey: 'scheduledCount',
        title: 'Scheduled Work',
        icon: 'utility:clock',
        hint: 'Work orders with at least one Scheduled or In Progress service appointment.'
    },
    {
        key: 'scheduledToday',
        revenueKey: 'scheduledTodayRevenue',
        countKey: 'scheduledTodayCount',
        title: 'Scheduled for Today',
        icon: 'utility:sync',
        hint: 'Service appointments scheduled or in progress today.'
    },
    {
        key: 'completedToday',
        revenueKey: 'completedTodayRevenue',
        countKey: 'completedTodayCount',
        title: 'Completed Today',
        icon: 'utility:check',
        hint: 'Service appointments completed today.'
    }
];

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
    for (const key of BUCKET_KEYS) {
        next[key] = { sortedBy: DEFAULT_SORT_FIELD, sortDirection: 'asc' };
    }
    return next;
}

export default class BillingControlCenterOrders extends LightningElement {
    workOrderColumns = WORK_ORDER_COLUMNS;
    /** @type {{ bucketKey: string, sectionLabel: string, rows: object[] }[]} */
    sections = [];
    /** @type {Record<string, { sortedBy: string, sortDirection: string }>} */
    sortState = defaultSortState();
    searchKey = '';
    kpiState = {};
    errorMessage;
    isLoading = true;

    connectedCallback() {
        this.loadData();
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            formattedRevenue: CURRENCY_FORMATTER.format(this.kpiState[tile.revenueKey] || 0),
            formattedCount: `${NUMBER_FORMATTER.format(this.kpiState[tile.countKey] || 0)} records`
        }));
    }

    get accordionSections() {
        const q = this.searchKey.trim().toLowerCase();
        return (this.sections || []).map(section => {
            let rows = (section.rows || []).map(r => ({ ...r }));
            if (q) {
                rows = rows.filter(row =>
                    [
                        row.workOrderNumber,
                        row.serviceAppointmentDisplay,
                        row.subject,
                        row.status,
                        row.serviceAppointmentNumber,
                        row.accountName,
                        row.opportunityName,
                        row.ownerName
                    ]
                        .filter(Boolean)
                        .some(value => String(value).toLowerCase().includes(q))
                );
            }

            const bucketSort = this.sortState[section.bucketKey] || {
                sortedBy: DEFAULT_SORT_FIELD,
                sortDirection: 'asc'
            };
            rows = sortWorkOrderRows(rows, bucketSort.sortedBy, bucketSort.sortDirection);

            return {
                bucketKey: section.bucketKey,
                sectionLabel: section.sectionLabel,
                titleWithCount: `${section.sectionLabel} (${rows.length})`,
                filteredRows: rows,
                isEmpty: rows.length === 0,
                sortedBy: bucketSort.sortedBy,
                sortDirection: bucketSort.sortDirection
            };
        });
    }

    get totalWorkOrderRows() {
        return (this.sections || []).reduce((sum, s) => sum + (s.rows || []).length, 0);
    }

    get searchSummary() {
        if (!this.searchKey.trim()) {
            return `${this.totalWorkOrderRows} records across buckets`;
        }
        const shownCount = this.accordionSections.reduce((sum, s) => sum + s.filteredRows.length, 0);
        return `Showing ${shownCount} matching records`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    async handleRefresh() {
        await this.loadData(true);
    }

    handleWorkOrderSort(event) {
        const bucketKey = this.readBucketKeyFromEvent(event);
        if (!bucketKey || !this.sortState[bucketKey]) {
            return;
        }

        const { fieldName, sortDirection } = event.detail;
        this.sortState = {
            ...this.sortState,
            [bucketKey]: { sortedBy: fieldName, sortDirection }
        };
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

        try {
            const refreshToken = forceRefresh ? Date.now() : null;
            const [kpis, bucketSections] = await Promise.all([
                getKpis({ refreshToken }),
                getBucketWorkOrders({ refreshToken })
            ]);

            this.kpiState = { ...(kpis || {}) };
            const normalizedSections = (bucketSections || []).map(s => ({
                bucketKey: s.bucketKey,
                sectionLabel: s.sectionLabel,
                rows: (s.rows || []).map((r, index) => {
                    const rowKey = r.rowKey || r.serviceAppointmentId || r.workOrderId || `${s.bucketKey}-${index}`;
                    return {
                        ...r,
                        rowKey,
                        accountUrl: accountRecordUrl(r.accountId),
                        opportunityUrl: opportunityRecordUrl(r.opportunityId),
                        workOrderUrl: workOrderRecordUrl(r.workOrderId)
                    };
                })
            }));
            this.sections = [...normalizedSections];
            this.sortState = defaultSortState();
        } catch (error) {
            this.kpiState = {};
            this.sections = [];
            this.sortState = defaultSortState();
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
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