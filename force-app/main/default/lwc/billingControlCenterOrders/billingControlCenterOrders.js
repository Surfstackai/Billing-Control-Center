import { LightningElement } from 'lwc';

import getKpis from '@salesforce/apex/BillingControl_Orders.getKpis';
import getBucketWorkOrders from '@salesforce/apex/BillingControl_Orders.getBucketWorkOrders';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');

const BUCKET_KEYS = ['UNSCHEDULED', 'SCHEDULED_BACKLOG', 'SCHEDULED_TODAY', 'COMPLETED_TODAY'];

const DEFAULT_SORT_FIELD = 'accountUrl';

const KPI_MODE_BACKLOG = 'backlog';
const KPI_MODE_SERVICE_APPOINTMENTS = 'serviceAppointments';

const KPI_CONFIG = [
    {
        key: 'unscheduled',
        mode: KPI_MODE_BACKLOG,
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Unscheduled Backlog',
        icon: 'utility:date_input',
        hint: 'Closed Won (last 3 years) with a work order still in "For Clearance" or "For Appointment Booking".'
    },
    {
        key: 'scheduledBacklog',
        mode: KPI_MODE_BACKLOG,
        revenueKey: 'scheduledBacklogRevenue',
        countKey: 'scheduledBacklogCount',
        title: 'Scheduled Backlog',
        icon: 'utility:clock',
        hint: 'Closed Won with a Scheduled or In Progress service appointment, including work scheduled for today.'
    },
    {
        key: 'scheduledToday',
        mode: KPI_MODE_SERVICE_APPOINTMENTS,
        countKey: 'serviceAppointmentsScheduledTodayCount',
        title: 'Scheduled for Today',
        icon: 'utility:event',
        hint: 'Service appointments with Status Scheduled or In Progress and SchedStartTime on today.'
    },
    {
        key: 'completedToday',
        mode: KPI_MODE_SERVICE_APPOINTMENTS,
        countKey: 'serviceAppointmentsCompletedTodayCount',
        title: 'Completed Today',
        icon: 'utility:success',
        hint: 'Service appointments with Status Completed and ActualEndTime on today.'
    }
];

const WORK_ORDER_COLUMNS = [
    {
        label: 'Account',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        initialWidth: 200,
        typeAttributes: {
            label: { fieldName: 'accountName' },
            target: '_self'
        }
    },
    {
        label: 'Opportunity',
        fieldName: 'opportunityUrl',
        type: 'url',
        sortable: true,
        initialWidth: 200,
        typeAttributes: {
            label: { fieldName: 'opportunityName' },
            target: '_self'
        }
    },
    {
        label: 'Work Order',
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
        label: 'Service Appointments',
        fieldName: 'serviceAppointmentsSummary',
        type: 'text',
        sortable: true,
        wrapText: true,
        initialWidth: 300
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
    { label: 'Subject', fieldName: 'subject', type: 'text', sortable: true, wrapText: true },
    { label: 'WO Status', fieldName: 'status', type: 'text', sortable: true, initialWidth: 150 },
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

function opportunityRecordUrl(opportunityId) {
    if (!opportunityId) {
        return null;
    }
    return `/lightning/r/Opportunity/${opportunityId}/view`;
}

function accountRecordUrl(accountId) {
    if (!accountId) {
        return null;
    }
    return `/lightning/r/Account/${accountId}/view`;
}

function resolveSortField(fieldName) {
    if (fieldName === 'workOrderUrl') {
        return 'workOrderNumber';
    }
    if (fieldName === 'opportunityUrl') {
        return 'opportunityName';
    }
    if (fieldName === 'accountUrl') {
        return 'accountName';
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
    /** @type {Promise<void> | null} */
    _loadInFlight = null;

    connectedCallback() {
        this.loadData();
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => {
            const count = this.kpiState[tile.countKey] || 0;
            const isBacklog = tile.mode === KPI_MODE_BACKLOG;
            const revenue = isBacklog ? this.kpiState[tile.revenueKey] || 0 : 0;
            return {
                ...tile,
                isBacklog,
                primaryValue: isBacklog
                    ? CURRENCY_FORMATTER.format(revenue)
                    : NUMBER_FORMATTER.format(count),
                secondaryValue: isBacklog
                    ? `${NUMBER_FORMATTER.format(count)} opportunities`
                    : 'service appointments'
            };
        });
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
                        row.ownerName,
                        row.serviceAppointmentsSummary
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

    loadData() {
        if (this._loadInFlight) {
            return this._loadInFlight;
        }
        this._loadInFlight = this.runLoad();
        return this._loadInFlight;
    }

    async runLoad() {
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
                    accountUrl: accountRecordUrl(r.accountId),
                    opportunityUrl: opportunityRecordUrl(r.opportunityId),
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
            this._loadInFlight = null;
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