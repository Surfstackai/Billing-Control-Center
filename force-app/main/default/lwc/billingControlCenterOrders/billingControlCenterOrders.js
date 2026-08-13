import { LightningElement, api } from 'lwc';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getOrdersRuntimeData from '@salesforce/apex/BillingControl_DataProvider.getOrdersRuntimeData';
import {
    MIN_COLUMN_WIDTH,
    ORDERS_COLUMN_WIDTHS_KEY,
    columnWidthStyle,
    loadColumnWidths,
    saveColumnWidths
} from 'c/billingControlCenterColumnResize';
import { decorateAccountGroups, sortRowsWithAccountGroup } from 'c/billingControlCenterAccountGroup';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');

const BUCKET_KEYS = [
    'UNSCHEDULED',
    'SCHEDULED',
    'SCHEDULED_TODAY',
    'COMPLETED_THIS_WEEK',
    'COMPLETED_THIS_MONTH',
    'NO_OPPORTUNITY',
    'NO_SERVICE_APPOINTMENT',
    'MULTIPLE_OPPORTUNITIES'
];
const ORDERS_DATASET_KEY = 'ORDERS_WORK_ORDERS';
const ordersRuntimeCache = new Map();

const DEFAULT_SORT_FIELD = 'accountUrl';
const DEFAULT_HERO_TITLE = 'Work Order Ledger';
const DEFAULT_HERO_SUBTITLE = 'Accounting Reconciliation';
const DEFAULT_TABLE_TITLE = 'Work Order Ledger by bucket';
const DEFAULT_REFRESH_LABEL = 'Refresh';

const KPI_CONFIG_PRIMARY = [
    {
        key: 'unscheduled',
        developerKey: 'UNSCHEDULED',
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Unscheduled Work',
        icon: 'utility:date_input',
        hint: 'Service appointments with a blank Scheduled Start.'
    },
    {
        key: 'scheduled',
        developerKey: 'SCHEDULED',
        revenueKey: 'scheduledRevenue',
        countKey: 'scheduledCount',
        title: 'Scheduled Work',
        icon: 'utility:clock',
        hint: 'Service appointments with a Scheduled Start that is not today.'
    },
    {
        key: 'scheduledToday',
        developerKey: 'SCHEDULED_TODAY',
        revenueKey: 'scheduledTodayRevenue',
        countKey: 'scheduledTodayCount',
        title: 'Scheduled for Today',
        icon: 'utility:sync',
        hint: 'Service appointments whose Scheduled Start is today.'
    },
    {
        key: 'completedThisWeek',
        developerKey: 'COMPLETED_THIS_WEEK',
        revenueKey: 'completedThisWeekRevenue',
        countKey: 'completedThisWeekCount',
        title: 'Completed This Week',
        icon: 'utility:check',
        hint: 'Service appointments completed this week (by Actual End).'
    }
];

const KPI_CONFIG_SECONDARY = [
    {
        key: 'completedThisMonth',
        developerKey: 'COMPLETED_THIS_MONTH',
        revenueKey: 'completedThisMonthRevenue',
        countKey: 'completedThisMonthCount',
        title: 'Completed This Month',
        icon: 'utility:monthlyview',
        hint: 'Service appointments completed this calendar month (by Actual End).'
    },
    {
        key: 'noOpportunity',
        developerKey: 'NO_OPPORTUNITY',
        revenueKey: 'noOpportunityRevenue',
        countKey: 'noOpportunityCount',
        title: 'Work Orders with No Opportunities',
        icon: 'utility:warning',
        hint: 'Work Orders with no Opportunity_WorkOrder junction.'
    },
    {
        key: 'noServiceAppointment',
        developerKey: 'NO_SERVICE_APPOINTMENT',
        revenueKey: 'noServiceAppointmentRevenue',
        countKey: 'noServiceAppointmentCount',
        title: 'No Service Appointment',
        icon: 'utility:ban',
        hint: 'Work Orders with no Service Appointment.'
    },
    {
        key: 'multipleOpportunities',
        developerKey: 'MULTIPLE_OPPORTUNITIES',
        revenueKey: 'multipleOpportunitiesRevenue',
        countKey: 'multipleOpportunitiesCount',
        title: 'Multiple Opportunities',
        icon: 'utility:multi_select_checkbox',
        hint: 'Work Orders linked to more than one Opportunity.'
    }
];

const KPI_CONFIGS = [...KPI_CONFIG_PRIMARY, ...KPI_CONFIG_SECONDARY];
const DEFAULT_DATE_FILTER = { filterKey: 'This Year' };

const WORK_ORDER_COLUMNS = [
    {
        developerKey: 'ACCOUNT',
        configFieldApiName: 'accountName',
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
        developerKey: 'OPPORTUNITY',
        configFieldApiName: 'opportunityName',
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
        developerKey: 'WORK_ORDER',
        configFieldApiName: 'workOrderNumber',
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
        developerKey: 'SERVICE_APPOINTMENTS',
        configFieldApiName: 'serviceAppointmentDisplay',
        label: 'Service Appointments',
        fieldName: 'serviceAppointmentDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'CREATED_DATE',
        configFieldApiName: 'createdDate',
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
    {
        developerKey: 'SUBJECT',
        configFieldApiName: 'subject',
        label: 'Subject',
        fieldName: 'subject',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'RECONCILIATION',
        configFieldApiName: 'reconciliationStatus',
        label: 'Reconciliation Status',
        fieldName: 'reconciliationStatus',
        type: 'text',
        sortable: true
    },
    {
        developerKey: 'OPPORTUNITY_AMOUNT',
        configFieldApiName: 'opportunityAmount',
        label: 'Opportunity Amount',
        fieldName: 'opportunityAmount',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'OWNER',
        configFieldApiName: 'ownerName',
        label: 'Owner',
        fieldName: 'ownerName',
        type: 'text',
        sortable: true
    },
    {
        developerKey: 'VIEW_LEDGER',
        configFieldApiName: 'viewLedger',
        label: 'Ledger',
        fieldName: 'ledgerId',
        type: 'action',
        sortable: false
    }
];

const COL_MODIFIER_BY_KEY = {
    ACCOUNT: 'account',
    OPPORTUNITY: 'opportunity',
    WORK_ORDER: 'work-order',
    SERVICE_APPOINTMENTS: 'service-appointment',
    CREATED_DATE: 'created-date',
    SUBJECT: 'subject',
    RECONCILIATION: 'reconciliation',
    OPPORTUNITY_AMOUNT: 'opportunity-amount',
    OWNER: 'owner',
    VIEW_LEDGER: 'view-ledger'
};

const SKIP_CONFIG_COLUMN_KEYS = new Set([
    'EXPAND',
    'DEPOSIT',
    'PARTS',
    'INVOICE',
    'ATTENTION',
    'WORK_ORDER_STATUS'
]);
const RECONCILIATION_CONFIG_ALIASES = new Set(['STATUS', 'DIARY_STATUS', 'WORK_ORDER_STATUS']);

function normalizeConfigKey(value) {
    return value ? String(value).trim().toUpperCase() : '';
}

function buildConfigMap(records) {
    const result = {};
    (records || []).forEach(record => {
        const key = normalizeConfigKey(record?.developerKey);
        if (key) {
            result[key] = record;
        }
    });
    return result;
}

function buildConfiguredColumns(configColumns) {
    if (!Array.isArray(configColumns) || configColumns.length === 0) {
        return WORK_ORDER_COLUMNS;
    }

    const configByKey = new Map();
    const configByField = new Map();
    configColumns.forEach(configColumn => {
        const developerKey = normalizeConfigKey(configColumn?.developerKey);
        if (developerKey && !SKIP_CONFIG_COLUMN_KEYS.has(developerKey)) {
            configByKey.set(developerKey, configColumn);
        }
        if (RECONCILIATION_CONFIG_ALIASES.has(developerKey)) {
            configByKey.set('RECONCILIATION', configColumn);
        }
        if (configColumn?.fieldApiName) {
            configByField.set(configColumn.fieldApiName, configColumn);
        }
    });

    return WORK_ORDER_COLUMNS.map(column => {
        const developerKey = normalizeConfigKey(column.developerKey);
        const configRecord =
            configByKey.get(developerKey) || configByField.get(column.configFieldApiName);
        const lockedLabel =
            developerKey === 'RECONCILIATION'
                ? 'Reconciliation Status'
                : developerKey === 'VIEW_LEDGER'
                  ? 'Ledger'
                  : developerKey === 'OPPORTUNITY_AMOUNT'
                    ? 'Opportunity Amount'
                    : null;
        return {
            ...column,
            label: lockedLabel || configRecord?.label || column.label
        };
    });
}

function buildRenderableColumns(columns, sortedBy, sortDirection, columnWidths) {
    return (columns || []).map((column, index) => {
        const developerKey = normalizeConfigKey(column.developerKey);
        const fieldName = column.fieldName || column.configFieldApiName;
        const isSorted = sortedBy === fieldName;
        const isAscending = sortDirection === 'asc';

        const isOpportunityAmount = developerKey === 'OPPORTUNITY_AMOUNT';
        const colModifier = COL_MODIFIER_BY_KEY[developerKey] || 'default';
        const widthStyle = columnWidthStyle(columnWidths?.[developerKey]);

        return {
            ...column,
            key: `${developerKey || fieldName || 'column'}-${index}`,
            fieldName,
            developerKey,
            isSorted,
            ariaSort: isSorted ? (isAscending ? 'ascending' : 'descending') : 'none',
            sortIcon: isAscending ? 'utility:arrowup' : 'utility:arrowdown',
            sortAltText: isAscending ? 'Sorted ascending' : 'Sorted descending',
            isAccount: developerKey === 'ACCOUNT',
            isOpportunity: developerKey === 'OPPORTUNITY',
            isWorkOrder: developerKey === 'WORK_ORDER',
            isServiceAppointment: developerKey === 'SERVICE_APPOINTMENTS',
            isCreatedDate: developerKey === 'CREATED_DATE',
            isSubject: developerKey === 'SUBJECT',
            isOpportunityAmount,
            isOwner: developerKey === 'OWNER',
            isReconciliation: developerKey === 'RECONCILIATION',
            isLedgerAction: developerKey === 'VIEW_LEDGER',
            colClass: `grouped-diary-table__col grouped-diary-table__col--${colModifier}`,
            colStyle: widthStyle,
            headerStyle: widthStyle,
            headerClass: `grouped-diary-table__header bcc-resizable-header${isOpportunityAmount ? ' grouped-diary-table__header--opportunity-amount' : ''}`,
            cellClass: `grouped-diary-table__cell${isOpportunityAmount ? ' grouped-diary-table__cell--opportunity-amount' : ''}`
        };
    });
}

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

function normalizeAppointmentRows(row) {
    const relatedServiceAppointments = (
        row.relatedServiceAppointments && row.relatedServiceAppointments.length
            ? row.relatedServiceAppointments
            : [row]
    ).map((appointment, index) => {
        const lineKey =
            appointment.rowKey ||
            appointment.serviceAppointmentId ||
            appointment.orderId ||
            `${row.rowKey || row.workOrderId || 'appointment'}-${index}`;

        return {
            ...appointment,
            lineKey,
            serviceAppointmentUrl: appointment.serviceAppointmentId
                ? `/lightning/r/ServiceAppointment/${appointment.serviceAppointmentId}/view`
                : null,
            createdDateValue: appointment.createdDate
        };
    });

    const relatedOpportunities = (
        row.relatedOpportunities && row.relatedOpportunities.length
            ? row.relatedOpportunities
            : row.opportunityId || row.opportunityName
              ? [{ opportunityId: row.opportunityId, opportunityName: row.opportunityName }]
              : []
    ).map((opportunity, index) => {
        const lineKey =
            opportunity.rowKey ||
            opportunity.opportunityId ||
            `${row.rowKey || row.workOrderId || 'opportunity'}-${index}`;
        return {
            ...opportunity,
            lineKey,
            opportunityUrl: opportunity.opportunityId
                ? `/lightning/r/Opportunity/${opportunity.opportunityId}/view`
                : null
        };
    });

    const appointmentSearchTerms = relatedServiceAppointments.reduce((terms, appointment) => {
        terms.push(
            appointment.serviceAppointmentDisplay,
            appointment.serviceAppointmentNumber,
            appointment.subject,
            appointment.status,
            appointment.ownerName
        );
        return terms;
    }, []);

    const opportunitySearchTerms = relatedOpportunities.map(opportunity => opportunity.opportunityName);

    const searchIndex = [
        row.accountName,
        row.opportunityName,
        row.workOrderNumber,
        row.subject,
        row.reconciliationStatus,
        row.accountOwnerName,
        row.ownerName,
        ...appointmentSearchTerms,
        ...opportunitySearchTerms
    ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

    return {
        ...row,
        relatedServiceAppointments,
        relatedOpportunities,
        opportunityAmountValue: row.opportunityAmount,
        hasOpportunityAmount: row.opportunityAmount !== undefined && row.opportunityAmount !== null,
        serviceAppointmentCount: row.serviceAppointmentCount || relatedServiceAppointments.length,
        searchIndex
    };
}

function rowMatchesSearch(row, searchKey) {
    if (!searchKey) {
        return true;
    }
    return (row.searchIndex || '').includes(searchKey);
}

function countAppointments(rows) {
    return (rows || []).reduce(
        (sum, row) => sum + (row.serviceAppointmentCount || row.relatedServiceAppointments?.length || 0),
        0
    );
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
    return sortRowsWithAccountGroup(rows, fieldName, direction, compareRowValues);
}

function defaultSortState() {
    const next = {};
    for (const key of BUCKET_KEYS) {
        next[key] = { sortedBy: DEFAULT_SORT_FIELD, sortDirection: 'asc' };
    }
    return next;
}

function cloneRuntimeData(value) {
    return value ? JSON.parse(JSON.stringify(value)) : value;
}

function buildRuntimeCacheKey(dateFilter) {
    return JSON.stringify(dateFilter || null);
}

export default class BillingControlCenterOrders extends LightningElement {
    _dateFilter = { ...DEFAULT_DATE_FILTER };
    _dateFilterSignature = JSON.stringify(DEFAULT_DATE_FILTER);
    _isConnected = false;

    @api useExternalToolbar = false;

    workOrderColumns = WORK_ORDER_COLUMNS;
    /** @type {{ bucketKey: string, sectionLabel: string, rows: object[] }[]} */
    sections = [];
    /** @type {Record<string, { sortedBy: string, sortDirection: string }>} */
    sortState = defaultSortState();
    searchKey = '';
    kpiState = {};
    errorMessage;
    providerWarnings = [];
    isLoading = true;
    ordersTabConfig;
    ordersConfigLoaded = false;
    ordersDatasetIsActive = true;
    ordersDatasetConfig;
    ordersKpisByKey = {};
    ordersSectionsByKey = {};
    ordersActionsByKey = {};
    columnWidths = {};
    selectedLedgerId;
    showLedgerModal = false;
    _resizeState;
    _boundResizeMove;
    _boundResizeEnd;

    @api
    get dateFilter() {
        return this._dateFilter;
    }

    set dateFilter(value) {
        const normalizedValue = value ? { ...value } : null;
        const signature = JSON.stringify(normalizedValue || {});
        if (signature === this._dateFilterSignature) {
            return;
        }

        this._dateFilter = normalizedValue;
        this._dateFilterSignature = signature;

        if (this._isConnected) {
            this.loadData();
        }
    }

    connectedCallback() {
        this._isConnected = true;
        this.columnWidths = loadColumnWidths(ORDERS_COLUMN_WIDTHS_KEY);
        this.loadOrdersConfig();
        this.loadData();
    }

    disconnectedCallback() {
        this.teardownColumnResize();
    }

    get heroTitle() {
        return this.ordersTabConfig?.label || DEFAULT_HERO_TITLE;
    }

    get heroSubtitle() {
        return DEFAULT_HERO_SUBTITLE;
    }

    get tableTitle() {
        return this.ordersTabConfig?.label
            ? `${this.ordersTabConfig.label} by bucket`
            : DEFAULT_TABLE_TITLE;
    }

    get showDiagnostics() {
        return hasBillingControlCenterAdminAccess && this.providerWarnings.length > 0;
    }

    get refreshLabel() {
        return this.ordersActionsByKey.REFRESH?.label || DEFAULT_REFRESH_LABEL;
    }

    get heroActions() {
        if (this.useExternalToolbar) {
            return [];
        }

        if (this.ordersConfigLoaded && !this.ordersActionsByKey.REFRESH) {
            return [];
        }

        return [
            {
                key: 'refresh',
                label: this.refreshLabel,
                iconName: 'utility:refresh',
                variant: 'brand',
                disabled: this.isLoading,
                title: this.refreshLabel
            }
        ];
    }

    get dateFilterKey() {
        return this.dateFilter?.filterKey || DEFAULT_DATE_FILTER.filterKey;
    }

    get dateFilterStart() {
        return this.dateFilter?.startDate || '';
    }

    get dateFilterEnd() {
        return this.dateFilter?.endDate || '';
    }

    get kpiTilesPrimary() {
        return this.buildKpiTilesFromDefinitions(KPI_CONFIG_PRIMARY);
    }

    get kpiTilesSecondary() {
        return this.buildKpiTilesFromDefinitions(KPI_CONFIG_SECONDARY);
    }

    get accordionSections() {
        const q = this.searchKey.trim().toLowerCase();
        const sectionsByKey = new Map(
            (this.sections || []).map(section => [normalizeConfigKey(section.bucketKey), section])
        );

        if (this.ordersConfigLoaded && !this.ordersDatasetIsActive) {
            return [];
        }

        return BUCKET_KEYS.map((bucketKey, index) => {
            const configRecord = this.ordersSectionsByKey[bucketKey];
            const runtimeSection = sectionsByKey.get(bucketKey) || {
                bucketKey,
                sectionLabel: configRecord?.label || bucketKey,
                rows: []
            };
            const definition = KPI_CONFIGS.find(tile => tile.developerKey === bucketKey);
            return this.buildAccordionSection(
                runtimeSection,
                configRecord?.label || runtimeSection.sectionLabel || definition?.title || bucketKey,
                q,
                Number(configRecord?.displayOrder || (index + 1) * 10)
            );
        });
    }

    get totalWorkOrderRows() {
        return this.accordionSections.reduce((sum, section) => sum + section.filteredRows.length, 0);
    }

    get searchSummary() {
        if (!this.searchKey.trim()) {
            return `${this.totalWorkOrderRows} work order rows across buckets`;
        }
        const shownCount = this.accordionSections.reduce((sum, s) => sum + s.filteredRows.length, 0);
        return `Showing ${shownCount} matching work order rows`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    handleViewLedger(event) {
        const host =
            event.currentTarget?.closest?.('[data-ledger-id]') ||
            event.target?.closest?.('[data-ledger-id]');
        const ledgerId = host?.dataset?.ledgerId;
        if (!ledgerId) {
            return;
        }
        this.selectedLedgerId = ledgerId;
        this.showLedgerModal = true;
    }

    handleCloseLedgerModal() {
        this.showLedgerModal = false;
        this.selectedLedgerId = undefined;
    }

    async handleRefresh() {
        await this.loadData(true);
    }

    @api
    async refreshData() {
        await this.handleRefresh();
    }

    handleHeroActionClick(event) {
        if (event.detail?.key === 'refresh') {
            this.handleRefresh();
        }
    }

    handleDateFilterChange(event) {
        const detail = event.detail || {};
        const filterKey = detail.filterKey || DEFAULT_DATE_FILTER.filterKey;
        this.dateFilter = {
            filterKey,
            startDate: filterKey === 'Custom' ? detail.startDate || null : null,
            endDate: filterKey === 'Custom' ? detail.endDate || null : null
        };
    }

    buildKpiTilesFromDefinitions(definitions) {
        if (this.ordersConfigLoaded && !this.ordersDatasetIsActive) {
            return [];
        }

        return definitions.map(definition => {
            const configRecord = this.ordersKpisByKey[normalizeConfigKey(definition.developerKey)];
            return this.buildKpiTile(definition, configRecord);
        });
    }

    buildKpiTile(definition, configRecord) {
        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: CURRENCY_FORMATTER.format(this.kpiState[definition.revenueKey] || 0),
            countText: `${NUMBER_FORMATTER.format(this.kpiState[definition.countKey] || 0)} records`
        };
    }

    buildAccordionSection(section, label, searchKey, sectionOrder) {
        let rows = (section.rows || []).map(row => ({ ...row }));
        if (searchKey) {
            rows = rows.filter(row => rowMatchesSearch(row, searchKey));
        }

        const bucketSort = this.sortState[section.bucketKey] || {
            sortedBy: DEFAULT_SORT_FIELD,
            sortDirection: 'asc'
        };
        rows = sortWorkOrderRows(rows, bucketSort.sortedBy, bucketSort.sortDirection);
        const visibleAppointmentCount = countAppointments(rows);
        const columns = buildRenderableColumns(
            this.workOrderColumns,
            bucketSort.sortedBy,
            bucketSort.sortDirection,
            this.columnWidths
        );
        const displayRows = decorateAccountGroups(
            rows.map(row => ({
                ...row,
                displayKey: row.rowKey,
                reconciliationStatus: row.reconciliationStatus || row.status,
                isLedgerActionDisabled: !row.ledgerId
            }))
        );

        return {
            bucketKey: section.bucketKey,
            sectionLabel: label,
            titleWithCount: `${label} (${visibleAppointmentCount})`,
            filteredRows: displayRows,
            isEmpty: rows.length === 0,
            sortedBy: bucketSort.sortedBy,
            sortDirection: bucketSort.sortDirection,
            columns: columns,
            visibleAppointmentCount,
            sectionOrder
        };
    }

    handleHeaderSort(event) {
        const bucketKey = event.currentTarget?.dataset?.bucket;
        const fieldName = event.currentTarget?.dataset?.field;
        if (!bucketKey || !fieldName || fieldName === 'ledgerId' || !this.sortState[bucketKey]) {
            return;
        }

        const currentSort = this.sortState[bucketKey];
        const sortDirection =
            currentSort.sortedBy === fieldName && currentSort.sortDirection === 'asc' ? 'desc' : 'asc';
        this.sortState = {
            ...this.sortState,
            [bucketKey]: { sortedBy: fieldName, sortDirection }
        };
    }

    handleColumnResizeStart(event) {
        event.preventDefault();
        event.stopPropagation();
        const columnKey = event.currentTarget?.dataset?.columnKey;
        if (!columnKey) {
            return;
        }
        const header = event.currentTarget.closest('th');
        const startWidth = header ? header.getBoundingClientRect().width : MIN_COLUMN_WIDTH;
        this.teardownColumnResize();
        this._resizeState = {
            columnKey,
            startX: event.clientX,
            startWidth
        };
        this._boundResizeMove = this.handleColumnResizeMove.bind(this);
        this._boundResizeEnd = this.handleColumnResizeEnd.bind(this);
        window.addEventListener('mousemove', this._boundResizeMove);
        window.addEventListener('mouseup', this._boundResizeEnd);
    }

    handleColumnResizeMove(event) {
        if (!this._resizeState) {
            return;
        }
        const nextWidth = Math.max(
            MIN_COLUMN_WIDTH,
            this._resizeState.startWidth + (event.clientX - this._resizeState.startX)
        );
        this.columnWidths = {
            ...this.columnWidths,
            [this._resizeState.columnKey]: nextWidth
        };
    }

    handleColumnResizeEnd() {
        saveColumnWidths(ORDERS_COLUMN_WIDTHS_KEY, this.columnWidths);
        this.teardownColumnResize();
    }

    teardownColumnResize() {
        if (this._boundResizeMove) {
            window.removeEventListener('mousemove', this._boundResizeMove);
        }
        if (this._boundResizeEnd) {
            window.removeEventListener('mouseup', this._boundResizeEnd);
        }
        this._boundResizeMove = undefined;
        this._boundResizeEnd = undefined;
        this._resizeState = undefined;
    }

    async loadData(forceRefresh = false) {
        this.isLoading = true;
        this.errorMessage = undefined;
        const cacheKey = buildRuntimeCacheKey(this.dateFilter);

        try {
            if (forceRefresh) {
                ordersRuntimeCache.delete(cacheKey);
            } else if (ordersRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(ordersRuntimeCache.get(cacheKey)));
                return;
            }

            const refreshToken = forceRefresh ? Date.now() : null;
            const runtimeData = await getOrdersRuntimeData({
                refreshToken,
                dateFilter: this.dateFilter || null
            });
            ordersRuntimeCache.set(cacheKey, cloneRuntimeData(runtimeData));
            this.applyRuntimeData(runtimeData);
        } catch (error) {
            this.providerWarnings = [];
            this.kpiState = {};
            this.sections = [];
            this.sortState = defaultSortState();
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyRuntimeData(runtimeData) {
        this.providerWarnings = runtimeData?.warnings || [];
        (runtimeData?.warnings || []).forEach(warning => console.warn(warning));
        const kpis = runtimeData?.kpis;
        const bucketSections = runtimeData?.bucketSections;

        this.kpiState = { ...(kpis || {}) };
        const normalizedSections = (bucketSections || []).map(s => ({
            bucketKey: s.bucketKey,
            sectionLabel: s.sectionLabel,
            serviceAppointmentCount: s.serviceAppointmentCount || 0,
            rows: (s.rows || []).map((r, index) => {
                const rowKey = r.rowKey || r.serviceAppointmentId || r.workOrderId || `${s.bucketKey}-${index}`;
                return {
                    ...normalizeAppointmentRows({
                        ...r,
                        rowKey,
                        accountUrl: accountRecordUrl(r.accountId),
                        opportunityUrl: opportunityRecordUrl(r.opportunityId),
                        workOrderUrl: workOrderRecordUrl(r.workOrderId)
                    }),
                    rowKey,
                };
            })
        }));
        this.sections = [...normalizedSections];
        this.sortState = defaultSortState();
    }

    async loadOrdersConfig() {
        try {
            const config = await getTabConfig({ developerKey: 'ORDERS' });
            if (!config) {
                console.warn('Billing Control Center Orders config not found. Using default presentation.');
                return;
            }

            this.ordersTabConfig = config;
            this.ordersConfigLoaded = true;
            this.ordersKpisByKey = buildConfigMap(config.kpis);
            this.ordersSectionsByKey = buildConfigMap(config.sections);
            this.ordersActionsByKey = buildConfigMap(config.actions);
            this.workOrderColumns = buildConfiguredColumns(config.columns);
            this.ordersDatasetConfig = (config.datasets || []).find(
                dataset => normalizeConfigKey(dataset?.developerKey) === ORDERS_DATASET_KEY
            );
            this.ordersDatasetIsActive = Boolean(this.ordersDatasetConfig);

            if (!this.ordersDatasetIsActive) {
                console.warn(
                    'Orders dataset config ORDERS_WORK_ORDERS is missing or inactive. Rendering safe empty state for config-driven Orders UI.'
                );
            }

            if (this.ordersKpisByKey.IN_PROGRESS && !this.ordersKpisByKey.SCHEDULED_TODAY) {
                console.warn(
                    'Orders config includes IN_PROGRESS, but the current runtime still renders SCHEDULED_TODAY. Using default labels for unmatched buckets.'
                );
            }
        } catch (error) {
            console.warn(
                'Failed to load Billing Control Center Orders config. Using default presentation.',
                error
            );
            this.ordersTabConfig = undefined;
            this.ordersConfigLoaded = false;
            this.ordersDatasetIsActive = true;
            this.ordersDatasetConfig = undefined;
            this.ordersKpisByKey = {};
            this.ordersSectionsByKey = {};
            this.ordersActionsByKey = {};
            this.workOrderColumns = WORK_ORDER_COLUMNS;
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