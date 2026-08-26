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
    'READY_TO_SCHEDULE',
    'SCHEDULED_APPOINTMENTS',
    'IN_PROGRESS'
];
const SECTION_LABELS = {
    READY_TO_SCHEDULE: 'Ready to Schedule',
    SCHEDULED_APPOINTMENTS: 'Scheduled Appointments',
    IN_PROGRESS: 'In Progress'
};
const ORDERS_DATASET_KEY = 'ORDERS_WORK_ORDERS';
const ordersRuntimeCache = new Map();

const DEFAULT_SORT_FIELD = 'accountUrl';
const WORK_ORDER_SORT_FIELD = 'workOrderUrl';
const LIST_VIEW_ACCOUNT = 'account';
const LIST_VIEW_WORK_ORDER = 'workOrder';
const WORK_ORDER_VIEW_LEAD_KEYS = ['WORK_TYPE', 'WORK_ORDER', 'ACCOUNT', 'OPPORTUNITY', 'SERVICE_APPOINTMENTS'];
const WORK_TYPE_GROUP_OTHER = 'OTHER';
const WORK_TYPE_GROUP_PIT_CLEANING = 'PIT_CLEANING';
const WORK_TYPE_GROUP_LABELS = {
    [WORK_TYPE_GROUP_OTHER]: 'Other',
    [WORK_TYPE_GROUP_PIT_CLEANING]: 'Pit Cleaning'
};
const DEFAULT_HERO_TITLE = 'Work Order Ledger';
const DEFAULT_HERO_SUBTITLE = 'Accounting Reconciliation';
const DEFAULT_TABLE_TITLE = 'Work Order Ledger by bucket';
const DEFAULT_REFRESH_LABEL = 'Refresh';

const KPI_CONFIGS = [
    {
        key: 'readyToSchedule',
        developerKey: 'READY_TO_SCHEDULE',
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Ready to Schedule',
        icon: 'utility:date_input',
        hint: 'Work Orders with no scheduled start/end and no actual start/end.'
    },
    {
        key: 'scheduledAppointments',
        developerKey: 'SCHEDULED_APPOINTMENTS',
        revenueKey: 'scheduledRevenue',
        countKey: 'scheduledCount',
        title: 'Scheduled Appointments',
        icon: 'utility:event',
        hint: 'Work Orders with a scheduled start and end, and no actual start or end.'
    },
    {
        key: 'inProgress',
        developerKey: 'IN_PROGRESS',
        revenueKey: 'inProgressRevenue',
        countKey: 'inProgressCount',
        title: 'In Progress',
        icon: 'utility:sync',
        hint: 'Work Orders with an actual start and no actual end.'
    }
];
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
        developerKey: 'WORK_TYPE',
        configFieldApiName: 'workTypeName',
        label: 'Work Type',
        fieldName: 'workTypeName',
        type: 'text',
        sortable: true
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
        developerKey: 'EARLIEST_START',
        configFieldApiName: 'earliestStartTime',
        label: 'Earliest Start Permitted',
        fieldName: 'earliestStartTime',
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
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
        developerKey: 'OPPORTUNITY_AMOUNT',
        configFieldApiName: 'opportunityAmount',
        label: 'Opportunity Amount',
        fieldName: 'opportunityAmount',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'VISIT_AMOUNT',
        configFieldApiName: 'visitAmount',
        label: 'Visit Amount',
        fieldName: 'visitAmount',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'OWNER',
        configFieldApiName: 'ownerName',
        label: 'Account Owner',
        fieldName: 'accountOwnerName',
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
    WORK_TYPE: 'work-type',
    WORK_ORDER: 'work-order',
    SERVICE_APPOINTMENTS: 'service-appointment',
    EARLIEST_START: 'earliest-start',
    SCHEDULED_START: 'earliest-start',
    ACTUAL_START: 'earliest-start',
    SUBJECT: 'subject',
    OPPORTUNITY_AMOUNT: 'opportunity-amount',
    VISIT_AMOUNT: 'visit-amount',
    OWNER: 'owner',
    VIEW_LEDGER: 'view-ledger'
};

const SKIP_CONFIG_COLUMN_KEYS = new Set([
    'EXPAND',
    'DEPOSIT',
    'PARTS',
    'INVOICE',
    'ATTENTION',
    'WORK_ORDER_STATUS',
    'RECONCILIATION',
    'STATUS',
    'DIARY_STATUS'
]);

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
        if (developerKey === 'CREATED_DATE' || developerKey === 'COMPLETED_DATE') {
            configByKey.set('EARLIEST_START', configColumn);
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
            developerKey === 'VIEW_LEDGER'
                ? 'Ledger'
                : developerKey === 'OWNER'
                  ? 'Account Owner'
                  : developerKey === 'OPPORTUNITY_AMOUNT'
                  ? 'Opportunity Amount'
                  : developerKey === 'VISIT_AMOUNT'
                    ? 'Visit Amount'
                    : developerKey === 'EARLIEST_START'
                    ? 'Earliest Start Permitted'
                    : developerKey === 'WORK_TYPE'
                      ? 'Work Type'
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
        const isVisitAmount = developerKey === 'VISIT_AMOUNT';
        const isCurrencyAmount = isOpportunityAmount || isVisitAmount;
        const colModifier = COL_MODIFIER_BY_KEY[developerKey] || 'default';
        const widthStyle = columnWidthStyle(columnWidths?.[developerKey]);

        return {
            ...column,
            key: developerKey || fieldName || `column-${index}`,
            fieldName,
            developerKey,
            isSorted,
            ariaSort: isSorted ? (isAscending ? 'ascending' : 'descending') : 'none',
            sortIcon: isAscending ? 'utility:arrowup' : 'utility:arrowdown',
            sortAltText: isAscending ? 'Sorted ascending' : 'Sorted descending',
            isLeadColumn: index === 0,
            isAccount: developerKey === 'ACCOUNT',
            isOpportunity: developerKey === 'OPPORTUNITY',
            isWorkType: developerKey === 'WORK_TYPE',
            isWorkOrder: developerKey === 'WORK_ORDER',
            isServiceAppointment: developerKey === 'SERVICE_APPOINTMENTS',
            isEarliestStart: developerKey === 'EARLIEST_START',
            isScheduledStart: developerKey === 'SCHEDULED_START',
            isActualStart: developerKey === 'ACTUAL_START',
            isSubject: developerKey === 'SUBJECT',
            isOpportunityAmount,
            isVisitAmount,
            isOwner: developerKey === 'OWNER',
            isLedgerAction: developerKey === 'VIEW_LEDGER',
            colClass: `grouped-diary-table__col grouped-diary-table__col--${colModifier}`,
            colStyle: widthStyle,
            headerStyle: widthStyle,
            headerClass: `grouped-diary-table__header bcc-resizable-header${isCurrencyAmount ? ' grouped-diary-table__header--opportunity-amount' : ''}`,
            cellClass: `grouped-diary-table__cell${isCurrencyAmount ? ' grouped-diary-table__cell--opportunity-amount' : ''}`
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

    const opportunitySearchTerms = relatedOpportunities.reduce((terms, opportunity) => {
        terms.push(opportunity.opportunityName, opportunity.ownerName);
        return terms;
    }, []);

    const searchIndex = [
        row.accountName,
        row.opportunityName,
        row.workTypeName,
        row.workOrderNumber,
        row.subject,
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
        visitAmountValue: row.visitAmount,
        hasVisitAmount: row.visitAmount !== undefined && row.visitAmount !== null,
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

    if (sortField === 'opportunityAmount' || sortField === 'visitAmount') {
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

    if (
        sortField === 'createdDate'
        || sortField === 'completedDate'
        || sortField === 'earliestStartTime'
        || sortField === 'schedStartTime'
        || sortField === 'actualStartTime'
    ) {
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

function sortWorkOrderRows(rows, fieldName, direction, groupByAccount = true) {
    if (groupByAccount) {
        return sortRowsWithAccountGroup(rows, fieldName, direction, compareRowValues);
    }
    const directionMultiplier = direction === 'desc' ? -1 : 1;
    return [...(rows || [])].sort((left, right) => {
        const primary = compareRowValues(left, right, fieldName, directionMultiplier);
        if (primary !== 0) {
            return primary;
        }
        const tieLeft = left?.rowKey != null ? String(left.rowKey) : String(left?.key || '');
        const tieRight = right?.rowKey != null ? String(right.rowKey) : String(right?.key || '');
        return tieLeft.localeCompare(tieRight);
    });
}

function isPitCleaningText(value) {
    const text = String(value || '').trim();
    return /pit\s*clean/i.test(text) || /preventa?tive\s+maintenance/i.test(text);
}

function isPitCleaningWorkType(row) {
    const values = [
        row?.workTypeName,
        row?.subject,
        row?.opportunityName,
        ...((row?.relatedOpportunities || []).map(opportunity => opportunity.opportunityName))
    ];
    return values.some(value => isPitCleaningText(value));
}

function workTypeGroupKey(row) {
    return isPitCleaningWorkType(row) ? WORK_TYPE_GROUP_PIT_CLEANING : WORK_TYPE_GROUP_OTHER;
}

function summarizeWorkTypeSplit(rows) {
    const pit = { count: 0, amount: 0 };
    const other = { count: 0, amount: 0 };
    (rows || []).forEach(row => {
        if (row?.billedBadge === true) {
            return;
        }
        const target = isPitCleaningWorkType(row) ? pit : other;
        target.count += 1;
        const amount = Number(row.operationalAmount ?? row.visitAmount ?? row.opportunityAmount);
        if (Number.isFinite(amount)) {
            target.amount += amount;
        }
    });
    return { pit, other };
}

function formatSplitColumn(key, label, summary) {
    return {
        key,
        label,
        metricText: CURRENCY_FORMATTER.format(summary.amount || 0),
        countText: `${NUMBER_FORMATTER.format(summary.count || 0)} records`
    };
}

function sumOpportunityAmount(rows) {
    return (rows || []).reduce((sum, row) => {
        const amount = Number(row.opportunityAmountValue ?? row.opportunityAmount);
        return Number.isFinite(amount) ? sum + amount : sum;
    }, 0);
}

function sumVisitAmount(rows) {
    return (rows || []).reduce((sum, row) => {
        const amount = Number(row.visitAmountValue ?? row.visitAmount ?? row.opportunityAmountValue ?? row.opportunityAmount);
        return Number.isFinite(amount) ? sum + amount : sum;
    }, 0);
}

function buildWorkTypeGroups(pitRows, otherRows, bucketKey, expandedKeys) {
    return [
        { groupKey: WORK_TYPE_GROUP_PIT_CLEANING, rows: pitRows },
        { groupKey: WORK_TYPE_GROUP_OTHER, rows: otherRows }
    ].map(({ groupKey, rows }) => {
        const key = `${bucketKey}-${groupKey}`;
        const isExpanded = expandedKeys.has(key);
        const totalAmount = sumOpportunityAmount(rows);
        const totalVisitAmount = sumVisitAmount(rows);
        return {
            key,
            groupKey,
            label: WORK_TYPE_GROUP_LABELS[groupKey],
            rows,
            rowCount: rows.length,
            appointmentCount: countAppointments(rows),
            totalAmount,
            totalVisitAmount,
            hasAmount: rows.some(row => row.hasOpportunityAmount),
            hasVisitAmount: rows.some(row => row.hasVisitAmount),
            isExpanded,
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            expandAltText: isExpanded ? `Collapse ${WORK_TYPE_GROUP_LABELS[groupKey]}` : `Expand ${WORK_TYPE_GROUP_LABELS[groupKey]}`
        };
    });
}

function columnsForListView(columns, listViewMode) {
    if (listViewMode !== LIST_VIEW_WORK_ORDER) {
        return columns;
    }
    const byKey = new Map(
        (columns || []).map(column => [normalizeConfigKey(column.developerKey), column])
    );
    const leading = WORK_ORDER_VIEW_LEAD_KEYS.map(key => byKey.get(key)).filter(Boolean);
    const used = new Set(WORK_ORDER_VIEW_LEAD_KEYS);
    const rest = (columns || []).filter(
        column => !used.has(normalizeConfigKey(column.developerKey))
    );
    return [...leading, ...rest];
}

const BUCKET_DATE_COLUMNS = {
    SCHEDULED_APPOINTMENTS: {
        developerKey: 'SCHEDULED_START',
        configFieldApiName: 'schedStartTime',
        label: 'Scheduled Start',
        fieldName: 'schedStartTime'
    },
    IN_PROGRESS: {
        developerKey: 'ACTUAL_START',
        configFieldApiName: 'actualStartTime',
        label: 'Actual Start',
        fieldName: 'actualStartTime'
    }
};

function columnsForBucket(columns, listViewMode, bucketKey) {
    const viewColumns = columnsForListView(columns, listViewMode);
    const dateColumn = BUCKET_DATE_COLUMNS[normalizeConfigKey(bucketKey)];
    if (!dateColumn) {
        return viewColumns;
    }
    return viewColumns.map(column => {
        if (normalizeConfigKey(column.developerKey) !== 'EARLIEST_START') {
            return column;
        }
        return {
            ...column,
            ...dateColumn
        };
    });
}

function defaultSortFieldForView(listViewMode) {
    return listViewMode === LIST_VIEW_WORK_ORDER ? WORK_ORDER_SORT_FIELD : DEFAULT_SORT_FIELD;
}

function defaultSortState(listViewMode = LIST_VIEW_ACCOUNT) {
    const next = {};
    const sortedBy = defaultSortFieldForView(listViewMode);
    for (const key of BUCKET_KEYS) {
        next[key] = { sortedBy, sortDirection: 'asc' };
    }
    return next;
}

function cloneRuntimeData(value) {
    return value ? JSON.parse(JSON.stringify(value)) : value;
}

function buildRuntimeCacheKey(dateFilter, opportunityOwnerId) {
    return JSON.stringify({
        dateFilter: dateFilter || null,
        opportunityOwnerId: opportunityOwnerId || null
    });
}

function apexRefreshToken(dateFilter, opportunityOwnerId, forceRefresh) {
    if (forceRefresh) {
        return Date.now();
    }
    const raw = buildRuntimeCacheKey(dateFilter, opportunityOwnerId);
    let hash = 2166136261;
    for (let i = 0; i < raw.length; i += 1) {
        hash ^= raw.charCodeAt(i);
        hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0) || 1;
}

export default class BillingControlCenterOrders extends LightningElement {
    _dateFilter = { ...DEFAULT_DATE_FILTER };
    _dateFilterSignature = JSON.stringify(DEFAULT_DATE_FILTER);
    _isConnected = false;
    _loadSequence = 0;
    opportunityOwnerId;
    userPickerDisplayInfo = {
        primaryField: 'Name',
        additionalFields: ['Username']
    };
    userPickerMatchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Username' }]
    };

    @api useExternalToolbar = false;

    workOrderColumns = WORK_ORDER_COLUMNS;
    /** @type {{ bucketKey: string, sectionLabel: string, rows: object[] }[]} */
    sections = [];
    searchKey = '';
    viewState = {
        listViewMode: LIST_VIEW_ACCOUNT,
        sortState: defaultSortState(),
        expandedWorkTypeGroups: []
    };
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
    _sectionRev = 0;
    _sectionCacheKey = '';
    _cachedAccordionSections = [];
    _resizeState;
    _boundResizeMove;
    _boundResizeEnd;

    get listViewMode() {
        return this.viewState.listViewMode;
    }

    get sortState() {
        return this.viewState.sortState;
    }

    get expandedWorkTypeGroups() {
        return this.viewState.expandedWorkTypeGroups;
    }

    setViewState(patch) {
        this.viewState = {
            ...this.viewState,
            ...patch
        };
    }

    @api
    get dateFilter() {
        return this._dateFilter;
    }

    set dateFilter(value) {
        this.applyDateFilter(value);
    }

    applyDateFilter(value) {
        const normalizedValue = value ? { ...value } : { ...DEFAULT_DATE_FILTER };
        const signature = JSON.stringify(normalizedValue);
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

    get kpiTiles() {
        return this.buildKpiTilesFromDefinitions(KPI_CONFIGS);
    }

    get isWorkOrderView() {
        return this.listViewMode === LIST_VIEW_WORK_ORDER;
    }

    get isAccountView() {
        return this.listViewMode !== LIST_VIEW_WORK_ORDER;
    }

    get woViewButtonClass() {
        return `view-by__option${this.isWorkOrderView ? ' view-by__option_selected' : ''}`;
    }

    get accountViewButtonClass() {
        return `view-by__option${this.isAccountView ? ' view-by__option_selected' : ''}`;
    }

    get viewSwitchKnobClass() {
        return `view-by__knob${this.isWorkOrderView ? ' view-by__knob_left' : ' view-by__knob_right'}`;
    }

    get accordionSections() {
        const cacheKey = this.buildSectionCacheKey();
        if (cacheKey === this._sectionCacheKey) {
            return this._cachedAccordionSections;
        }
        const sections = this.computeAccordionSections();
        this._sectionCacheKey = cacheKey;
        this._cachedAccordionSections = sections;
        return sections;
    }

    buildSectionCacheKey() {
        return JSON.stringify({
            rev: this._sectionRev,
            mode: this.listViewMode,
            sort: this.sortState,
            search: this.searchKey,
            expanded: this.expandedWorkTypeGroups,
            configLoaded: this.ordersConfigLoaded,
            datasetActive: this.ordersDatasetIsActive,
            widths: this.columnWidths
        });
    }

    computeAccordionSections() {
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
                configRecord?.label
                    || runtimeSection.sectionLabel
                    || definition?.title
                    || SECTION_LABELS[bucketKey]
                    || bucketKey,
                q,
                Number(configRecord?.displayOrder || (index + 1) * 10)
            );
        });
    }

    get totalWorkOrderRows() {
        return this.accordionSections.reduce(
            (sum, section) => sum + (section.visibleWorkOrderCount || 0),
            0
        );
    }

    get searchSummary() {
        if (!this.searchKey.trim()) {
            return `${this.totalWorkOrderRows} work order rows across buckets`;
        }
        return `Showing ${this.totalWorkOrderRows} matching work order rows`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    handleListViewSelect(event) {
        const next = event.currentTarget?.dataset?.view;
        if ((next !== LIST_VIEW_ACCOUNT && next !== LIST_VIEW_WORK_ORDER) || next === this.listViewMode) {
            return;
        }
        const previousDefault = defaultSortFieldForView(this.listViewMode);
        const nextDefault = defaultSortFieldForView(next);
        const nextSort = {};
        for (const key of BUCKET_KEYS) {
            const current = this.sortState[key] || { sortedBy: previousDefault, sortDirection: 'asc' };
            nextSort[key] =
                current.sortedBy === previousDefault
                    ? { sortedBy: nextDefault, sortDirection: 'asc' }
                    : { ...current };
        }
        this.viewState = {
            listViewMode: next,
            sortState: nextSort,
            expandedWorkTypeGroups: []
        };
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
        this._dateFilter = {
            filterKey,
            startDate: filterKey === 'Custom' ? detail.startDate || null : null,
            endDate: filterKey === 'Custom' ? detail.endDate || null : null
        };
        this._dateFilterSignature = JSON.stringify(this._dateFilter);
        if (this._isConnected) {
            this.loadData(true);
        }
    }

    handleOpportunityOwnerChange(event) {
        const nextOwnerId = event.detail?.recordId || null;
        if (nextOwnerId === this.opportunityOwnerId) {
            return;
        }
        this.opportunityOwnerId = nextOwnerId;
        if (this._isConnected) {
            this.loadData();
        }
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
        if (definition.useLines) {
            const weekCount = NUMBER_FORMATTER.format(this.kpiState.completedThisWeekCount || 0);
            const weekRevenue = CURRENCY_FORMATTER.format(this.kpiState.completedThisWeekRevenue || 0);
            const monthCount = NUMBER_FORMATTER.format(this.kpiState.completedThisMonthCount || 0);
            const monthRevenue = CURRENCY_FORMATTER.format(this.kpiState.completedThisMonthRevenue || 0);
            return {
                ...definition,
                title: configRecord?.label || definition.title,
                icon: configRecord?.iconName || definition.icon,
                metricText: '',
                countText: '',
                lines: [
                    { key: 'week', text: `This Week: ${weekCount} | ${weekRevenue}` },
                    { key: 'month', text: `This Month: ${monthCount} | ${monthRevenue}` }
                ]
            };
        }

        const section = (this.sections || []).find(
            candidate => normalizeConfigKey(candidate.bucketKey) === normalizeConfigKey(definition.developerKey)
        );
        const split = summarizeWorkTypeSplit(section?.rows);

        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: CURRENCY_FORMATTER.format(this.kpiState[definition.revenueKey] || 0),
            countText: `${NUMBER_FORMATTER.format(this.kpiState[definition.countKey] || 0)} records`,
            splitColumns: [
                formatSplitColumn('pit-cleaning', 'Pit Cleaning', split.pit),
                formatSplitColumn('other', 'Other', split.other)
            ]
        };
    }

    buildAccordionSection(section, label, searchKey, sectionOrder) {
        let rows = (section.rows || []).map(row => ({ ...row }));
        if (searchKey) {
            rows = rows.filter(row => rowMatchesSearch(row, searchKey));
        }

        const bucketSort = this.sortState[section.bucketKey] || {
            sortedBy: defaultSortFieldForView(this.listViewMode),
            sortDirection: 'asc'
        };
        const groupByAccount = !this.isWorkOrderView;
        rows = sortWorkOrderRows(rows, bucketSort.sortedBy, bucketSort.sortDirection, groupByAccount);
        const visibleAppointmentCount = countAppointments(rows);
        const columns = buildRenderableColumns(
            columnsForBucket(this.workOrderColumns, this.listViewMode, section.bucketKey),
            bucketSort.sortedBy,
            bucketSort.sortDirection,
            this.columnWidths
        );
        const preparedRow = (row) => ({
            ...row,
            displayKey: row.rowKey,
            reconciliationStatus: row.reconciliationStatus || row.status,
            isLedgerActionDisabled: !row.ledgerId
        });
        const decorateGroupRows = (groupRows) => {
            const preparedRows = groupRows.map(preparedRow);
            return groupByAccount
                ? decorateAccountGroups(preparedRows)
                : preparedRows.map(row => ({
                      ...row,
                      showAccountName: true,
                      isAccountGroupStart: true,
                      rowClass: 'slds-hint-parent grouped-diary-table__row'
                  }));
        };
        const otherRows = [];
        const pitRows = [];
        rows.forEach(row => {
            if (workTypeGroupKey(row) === WORK_TYPE_GROUP_PIT_CLEANING) {
                pitRows.push(row);
            } else {
                otherRows.push(row);
            }
        });
        const workTypeGroups = buildWorkTypeGroups(
            decorateGroupRows(pitRows),
            decorateGroupRows(otherRows),
            section.bucketKey,
            new Set(this.expandedWorkTypeGroups)
        );

        return {
            bucketKey: section.bucketKey,
            sectionLabel: label,
            titleWithCount: `${label} (${visibleAppointmentCount})`,
            workTypeGroups,
            filteredRows: workTypeGroups.flatMap(group => group.rows),
            isEmpty: rows.length === 0,
            visibleWorkOrderCount: rows.length,
            sortedBy: bucketSort.sortedBy,
            sortDirection: bucketSort.sortDirection,
            columns: columns,
            visibleAppointmentCount,
            sectionOrder
        };
    }

    handleToggleWorkTypeGroup(event) {
        const groupKey = event.currentTarget?.dataset?.groupKey;
        if (!groupKey) {
            return;
        }
        const nextExpanded = new Set(this.expandedWorkTypeGroups);
        if (nextExpanded.has(groupKey)) {
            nextExpanded.delete(groupKey);
        } else {
            nextExpanded.add(groupKey);
        }
        this.setViewState({ expandedWorkTypeGroups: Array.from(nextExpanded) });
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
        this.setViewState({
            sortState: {
                ...this.sortState,
                [bucketKey]: { sortedBy: fieldName, sortDirection }
            }
        });
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
        const cacheKey = buildRuntimeCacheKey(this.dateFilter, this.opportunityOwnerId);
        // A slow earlier request must never overwrite a newer date filter's result.
        this._loadSequence = (this._loadSequence || 0) + 1;
        const loadSequence = this._loadSequence;

        try {
            if (forceRefresh) {
                ordersRuntimeCache.delete(cacheKey);
            } else if (ordersRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(ordersRuntimeCache.get(cacheKey)));
                return;
            }

            const refreshToken = apexRefreshToken(
                this.dateFilter,
                this.opportunityOwnerId,
                forceRefresh
            );
            const runtimeData = await getOrdersRuntimeData({
                refreshToken: forceRefresh ? Date.now() : refreshToken,
                dateFilter: {
                    filterKey: this.dateFilter?.filterKey || DEFAULT_DATE_FILTER.filterKey,
                    startDate: this.dateFilter?.startDate || null,
                    endDate: this.dateFilter?.endDate || null
                },
                opportunityOwnerId: this.opportunityOwnerId || null
            });
            ordersRuntimeCache.set(cacheKey, cloneRuntimeData(runtimeData));
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.applyRuntimeData(runtimeData);
        } catch (error) {
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.providerWarnings = [];
            this.kpiState = {};
            this.sections = [];
            this._sectionRev += 1;
            this.setViewState({
                sortState: defaultSortState(this.listViewMode),
                expandedWorkTypeGroups: []
            });
            this.errorMessage = this.reduceError(error);
        } finally {
            if (loadSequence === this._loadSequence) {
                this.isLoading = false;
            }
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
        this._sectionRev += 1;
        this.setViewState({
            sortState: defaultSortState(this.listViewMode),
            expandedWorkTypeGroups: []
        });
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

            if (this.ordersKpisByKey.COMPLETED || this.ordersSectionsByKey.COMPLETED_NOT_BILLED) {
                console.warn(
                    'Orders config still includes Completed cards. Work Order Ledger now shows Ready, Scheduled, and In Progress only.'
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
        this._sectionRev += 1;
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