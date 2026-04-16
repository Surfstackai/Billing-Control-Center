import { LightningElement } from 'lwc';

import getKpis from '@salesforce/apex/BillingControl_Orders.getKpis';
import getBucketWorkOrders from '@salesforce/apex/BillingControl_Orders.getBucketWorkOrders';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');

const BUCKET_KEYS = ['UNSCHEDULED', 'SCHEDULED', 'IN_PROGRESS'];

const DEFAULT_SORT_FIELD = 'workOrderUrl';

const KPI_CONFIG = [
    {
        key: 'unscheduled',
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Unscheduled Work Value',
        icon: 'utility:date_input',
        hint: 'Closed Won (last 3 years): at least one linked work order in "For Clearance" or "For Appointment Booking".'
    },
    {
        key: 'scheduled',
        revenueKey: 'scheduledRevenue',
        countKey: 'scheduledCount',
        title: 'Scheduled Work Value',
        icon: 'utility:clock',
        hint: 'Closed Won: Work order Appointments Booked with a Scheduled service appointment.'
    },
    {
        key: 'inProgress',
        revenueKey: 'inProgressRevenue',
        countKey: 'inProgressCount',
        title: 'In Progress Work Value',
        icon: 'utility:sync',
        hint: 'Closed Won: Work order Appointments Booked with an In Progress service appointment (takes precedence).'
    }
];

const WORK_ORDER_COLUMNS = [
    {
        label: 'Work Order #',
        fieldName: 'workOrderUrl',
        type: 'url',
        sortable: true,
        initialWidth: 130,
        typeAttributes: {
            label: { fieldName: 'workOrderNumber' },
            target: '_self'
        }
    },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        sortable: true,
        initialWidth: 130,
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }
    },
    { label: 'Account', fieldName: 'accountName', type: 'text', sortable: true, initialWidth: 160 },
    { label: 'Subject', fieldName: 'subject', type: 'text', sortable: true, wrapText: true },
    { label: 'WO Status', fieldName: 'status', type: 'text', sortable: true, initialWidth: 150 },
    { label: 'Opportunity', fieldName: 'opportunityName', type: 'text', sortable: true, wrapText: true },
    {
        label: 'Opp Amount',
        fieldName: 'opportunityAmount',
        type: 'currency',
        sortable: true,
        initialWidth: 120,
        typeAttributes: { currencyCode: 'USD' }
    },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true, initialWidth: 140 }
];

function workOrderRecordUrl(workOrderId) {
    if (!workOrderId) {
        return null;
    }
    return `/lightning/r/WorkOrder/${workOrderId}/view`;
}

function resolveSortField(fieldName) {
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
        const tieLeft = left.workOrderId != null ? String(left.workOrderId) : '';
        const tieRight = right.workOrderId != null ? String(right.workOrderId) : '';
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
            formattedCount: `${NUMBER_FORMATTER.format(this.kpiState[tile.countKey] || 0)} opportunities`
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
            return `${this.totalWorkOrderRows} work orders across buckets`;
        }
        const shown = this.accordionSections.reduce((sum, s) => sum + s.filteredRows.length, 0);
        return `Showing ${shown} matching work orders`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    async handleRefresh() {
        await this.loadData();
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

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const [kpis, bucketSections] = await Promise.all([getKpis(), getBucketWorkOrders()]);

            this.kpiState = kpis || {};
            this.sections = (bucketSections || []).map(s => ({
                bucketKey: s.bucketKey,
                sectionLabel: s.sectionLabel,
                rows: (s.rows || []).map(r => ({
                    ...r,
                    workOrderUrl: workOrderRecordUrl(r.workOrderId)
                }))
            }));
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