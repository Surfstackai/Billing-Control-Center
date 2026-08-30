import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getTabRuntime from '@salesforce/apex/BillingControl_BillingReadiness.getTabRuntime';
import flagAppointmentForReview from '@salesforce/apex/BillingControl_BillingReadiness.flagAppointmentForReview';
import syncExistingInvoiceNumbers from '@salesforce/apex/BillingControl_Invoicing.syncExistingInvoiceNumbers';
import {
    MIN_COLUMN_WIDTH,
    INVOICING_COLUMN_WIDTHS_KEY,
    columnWidthStyle,
    loadColumnWidths,
    saveColumnWidths
} from 'c/billingControlCenterColumnResize';
import { decorateAccountGroups, sortRowsWithAccountGroup } from 'c/billingControlCenterAccountGroup';
import { resolveDateRange } from 'c/billingControlCenterDateFilter';

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');
const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2
});

const KPI_CONFIG = [
    {
        key: 'depositsDue',
        developerKey: 'DEPOSITS_DUE',
        title: 'Deposit Due',
        icon: 'utility:money',
        hint: 'Opportunities with a required deposit that has not been invoiced.',
        countKey: 'depositsDueCount',
        amountKey: 'depositsDueAmount'
    },
    {
        key: 'balancesReady',
        developerKey: 'BALANCES_READY',
        title: 'Ready to Bill',
        icon: 'utility:check',
        hint: 'Completed attributed visits that do not yet have an invoice line.',
        countKey: 'balancesReadyCount',
        amountKey: 'balancesReadyAmount'
    },
    {
        key: 'underInvoiced',
        developerKey: 'UNDER_INVOICED',
        title: 'Balance Remaining',
        icon: 'utility:warning',
        hint: 'All attributed completed visits are billed, but invoiced total is below the quote.',
        countKey: 'underInvoicedCount',
        amountKey: 'underInvoicedAmount'
    },
    {
        key: 'needsReview',
        developerKey: 'NEEDS_REVIEW',
        title: 'Needs Review',
        icon: 'utility:info',
        hint: 'Accounting exceptions: missing quote amount, unassigned visits, invalid invoice text, or flagged by Accounting.',
        countKey: 'needsReviewCount'
    }
];

const CATEGORY_KEYS = KPI_CONFIG.map(definition => definition.developerKey);
const INVOICING_DATASET_KEY = 'INVOICING_SERVICE_APPOINTMENTS';
const INVOICING_SECTION_KEY = 'READY_TO_INVOICE';
const invoicingRuntimeCache = new Map();
const DEFAULT_SORT_FIELD = 'accountUrl';
const DEFAULT_HERO_TITLE = 'Ready to Bill';
const DEFAULT_HERO_SUBTITLE =
    'Review billable Opportunities, inspect Work Order and visit evidence, then record invoices.';
const DEFAULT_TABLE_TITLE = 'Billable Opportunities';
const DEFAULT_REFRESH_LABEL = 'Refresh';
const DEFAULT_COMPLETE_BILLING_LABEL = 'Complete Billing';
const DEFAULT_INV_SYNC_LABEL = 'INV-Sync';
const DEFAULT_DATE_FILTER = resolveDateRange('This Month');

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
        developerKey: 'QUOTE_NUMBER',
        configFieldApiName: 'quoteNumber',
        label: 'Quote #',
        fieldName: 'quoteNumber',
        type: 'text',
        sortable: true
    },
    {
        developerKey: 'REASONS',
        configFieldApiName: 'reasonDisplay',
        label: 'Readiness',
        fieldName: 'reasonDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'INVOICE_NUMBER',
        configFieldApiName: 'invoiceChipDisplay',
        label: 'Invoices',
        fieldName: 'invoiceChipDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'OPPORTUNITY_AMOUNT',
        configFieldApiName: 'amountQuoted',
        label: 'Quoted',
        fieldName: 'amountQuoted',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'INVOICED_TOTAL',
        configFieldApiName: 'invoicedTotal',
        label: 'Invoiced',
        fieldName: 'invoicedTotal',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'REMAINING',
        configFieldApiName: 'remaining',
        label: 'Remaining',
        fieldName: 'remaining',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'PAID_TOTAL',
        configFieldApiName: 'paidTotal',
        label: 'Paid',
        fieldName: 'paidTotal',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'OUTSTANDING',
        configFieldApiName: 'outstanding',
        label: 'Outstanding',
        fieldName: 'outstanding',
        type: 'currency',
        sortable: true,
        typeAttributes: { currencyCode: 'USD' }
    },
    {
        developerKey: 'BILLING_STATUS',
        configFieldApiName: 'billingStatus',
        label: 'Billing Status',
        fieldName: 'billingStatus',
        type: 'text',
        sortable: true
    },
    {
        developerKey: 'SERVICE_APPOINTMENTS',
        configFieldApiName: 'serviceAppointmentDisplay',
        label: 'Evidence',
        fieldName: 'serviceAppointmentDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'FLAGS',
        configFieldApiName: 'flagItems',
        label: 'Flags',
        fieldName: 'flagItems',
        type: 'text',
        sortable: false
    },
    {
        developerKey: 'OWNER',
        configFieldApiName: 'ownerName',
        label: 'Salesperson',
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
    QUOTE_NUMBER: 'default',
    REASONS: 'default',
    INVOICE_NUMBER: 'invoice-number',
    SERVICE_APPOINTMENTS: 'service-appointment',
    FLAGS: 'default',
    OPPORTUNITY_AMOUNT: 'opportunity-amount',
    INVOICED_TOTAL: 'opportunity-amount',
    REMAINING: 'opportunity-amount',
    PAID_TOTAL: 'opportunity-amount',
    OUTSTANDING: 'opportunity-amount',
    BILLING_STATUS: 'status',
    OWNER: 'owner',
    VIEW_LEDGER: 'view-ledger'
};

function normalizeConfigKey(value) {
    return value ? String(value).trim().toUpperCase() : '';
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

    const defaultColumnsByKey = new Map();
    const defaultColumnsByField = new Map();
    WORK_ORDER_COLUMNS.forEach(column => {
        if (column.developerKey) {
            defaultColumnsByKey.set(normalizeConfigKey(column.developerKey), column);
        }
        if (column.configFieldApiName) {
            defaultColumnsByField.set(column.configFieldApiName, column);
        }
    });

    const matchedColumns = [];
    configColumns.forEach(configColumn => {
        const developerKey = normalizeConfigKey(configColumn?.developerKey);
        const matchedColumn =
            defaultColumnsByKey.get(developerKey) ||
            defaultColumnsByField.get(configColumn?.fieldApiName);

        if (!matchedColumn) {
            console.warn(
                `Skipping unsupported Invoicing column config: ${configColumn?.developerKey || configColumn?.fieldApiName || 'unknown'}`
            );
            return;
        }

        const resolvedLabel =
            developerKey === 'OPPORTUNITY_AMOUNT'
                ? 'Opportunity Amount'
                : developerKey === 'OWNER'
                    ? 'Account Owner'
                    : developerKey === 'CREATED_DATE'
                        ? 'Actual Completion Date'
                        : configColumn.label || matchedColumn.label;

        matchedColumns.push({
            ...matchedColumn,
            label: resolvedLabel
        });
    });

    if (matchedColumns.length === 0) {
        return WORK_ORDER_COLUMNS;
    }
    return injectViewLedgerColumn(injectFlagsColumn(injectInvoiceNumberColumn(matchedColumns)));
}

function injectInvoiceNumberColumn(columns) {
    const hasInvoiceNumber = columns.some(
        column => normalizeConfigKey(column.developerKey) === 'INVOICE_NUMBER'
    );
    if (hasInvoiceNumber) {
        return columns;
    }

    const invoiceNumberColumn = WORK_ORDER_COLUMNS.find(
        column => column.developerKey === 'INVOICE_NUMBER'
    );
    const workOrderIndex = columns.findIndex(
        column => normalizeConfigKey(column.developerKey) === 'WORK_ORDER'
    );
    const nextColumns = [...columns];
    if (workOrderIndex >= 0) {
        nextColumns.splice(workOrderIndex, 0, invoiceNumberColumn);
    } else {
        nextColumns.splice(2, 0, invoiceNumberColumn);
    }
    return nextColumns;
}

function injectFlagsColumn(columns) {
    const hasFlags = columns.some(
        column => normalizeConfigKey(column.developerKey) === 'FLAGS'
    );
    if (hasFlags) {
        return columns;
    }
    const flagsColumn = WORK_ORDER_COLUMNS.find(column => column.developerKey === 'FLAGS');
    if (!flagsColumn) {
        return columns;
    }
    const ledgerIndex = columns.findIndex(
        column => normalizeConfigKey(column.developerKey) === 'VIEW_LEDGER'
    );
    const nextColumns = [...columns];
    if (ledgerIndex >= 0) {
        nextColumns.splice(ledgerIndex, 0, flagsColumn);
    } else {
        nextColumns.push(flagsColumn);
    }
    return nextColumns;
}

function injectViewLedgerColumn(columns) {
    const hasViewLedger = columns.some(
        column => normalizeConfigKey(column.developerKey) === 'VIEW_LEDGER'
    );
    if (hasViewLedger) {
        return columns;
    }
    const viewLedgerColumn = WORK_ORDER_COLUMNS.find(
        column => column.developerKey === 'VIEW_LEDGER'
    );
    return viewLedgerColumn ? [...columns, viewLedgerColumn] : columns;
}

function buildRenderableColumns(columns, sortedBy, sortDirection, columnWidths) {
    return (columns || []).map((column, index) => {
        const developerKey = normalizeConfigKey(column.developerKey);
        const fieldName = column.fieldName || column.configFieldApiName;
        const isSorted = sortedBy === fieldName;
        const isAscending = sortDirection === 'asc';

        const isQuotedAmount = developerKey === 'OPPORTUNITY_AMOUNT';
        const isMoneyColumn =
            isQuotedAmount ||
            developerKey === 'INVOICED_TOTAL' ||
            developerKey === 'REMAINING' ||
            developerKey === 'PAID_TOTAL' ||
            developerKey === 'OUTSTANDING';
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
            isQuoteNumber: developerKey === 'QUOTE_NUMBER',
            isReasons: developerKey === 'REASONS',
            isInvoiceNumber: developerKey === 'INVOICE_NUMBER',
            isWorkOrder: developerKey === 'WORK_ORDER',
            isServiceAppointment: developerKey === 'SERVICE_APPOINTMENTS',
            isCreatedDate: developerKey === 'CREATED_DATE',
            isSubject: developerKey === 'SUBJECT',
            isStatus: developerKey === 'WORK_ORDER_STATUS',
            isOpportunityAmount: isQuotedAmount,
            isInvoicedTotal: developerKey === 'INVOICED_TOTAL',
            isRemaining: developerKey === 'REMAINING',
            isPaidTotal: developerKey === 'PAID_TOTAL',
            isOutstandingAmount: developerKey === 'OUTSTANDING',
            isFlags: developerKey === 'FLAGS',
            isBillingStatus: developerKey === 'BILLING_STATUS',
            isOwner: developerKey === 'OWNER',
            isLedgerAction: developerKey === 'VIEW_LEDGER',
            colClass: `grouped-diary-table__col grouped-diary-table__col--${colModifier}`,
            colStyle: widthStyle,
            headerStyle: widthStyle,
            headerClass: `grouped-diary-table__header bcc-resizable-header${isMoneyColumn ? ' grouped-diary-table__header--opportunity-amount' : ''}`,
            cellClass: `grouped-diary-table__cell${isMoneyColumn ? ' grouped-diary-table__cell--opportunity-amount' : ''}`
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

function formatActualEndTime(value) {
    if (!value) {
        return '';
    }
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
        return String(value);
    }
    return parsed.toLocaleString();
}

function buildFlagItems(readinessReasons) {
    const flags = [];
    const reasons = readinessReasons || [];
    if (reasons.includes('Visit not assigned to an Opportunity')) {
        flags.push({
            key: 'attribution',
            iconName: 'utility:lock',
            title: 'Visit not assigned to an Opportunity'
        });
    }
    if (reasons.includes('Missing quote amount')) {
        flags.push({
            key: 'no-amount',
            iconName: 'utility:ban',
            title: 'Missing quote amount'
        });
    }
    if (reasons.includes('Invoice reference needs review')) {
        flags.push({
            key: 'review',
            iconName: 'utility:note',
            title: 'Invoice reference needs review'
        });
    }
    if (reasons.includes('Flagged by Accounting')) {
        flags.push({
            key: 'flagged',
            iconName: 'utility:priority',
            title: 'Flagged by Accounting'
        });
    }
    if (reasons.includes('Balance Remaining')) {
        flags.push({
            key: 'under',
            iconName: 'utility:warning',
            title: 'Balance Remaining'
        });
    }
    return flags;
}

function flattenOpportunityEvidence(row) {
    if (Array.isArray(row?.relatedServiceAppointments) && row.relatedServiceAppointments.length) {
        return row.relatedServiceAppointments;
    }
    const related = [];
    for (const workOrder of row?.workOrders || []) {
        for (const appointment of workOrder.appointments || []) {
            related.push({
                serviceAppointmentId: appointment.serviceAppointmentId,
                serviceAppointmentNumber: appointment.serviceAppointmentNumber,
                serviceAppointmentDisplay: appointment.serviceAppointmentNumber,
                workOrderId: workOrder.workOrderId,
                workOrderNumber: workOrder.workOrderNumber,
                ledgerId: workOrder.ledgerId,
                billed: appointment.billed,
                invoiceNumber: appointment.billedInvoiceNumber || appointment.invoiceNumberHint,
                woInvoiceNumber: appointment.woInvStatusHint,
                description: appointment.description,
                serviceNote: appointment.serviceNote,
                technicianName: appointment.technicianName,
                completionDateTime: appointment.actualEndTime,
                status: appointment.status,
                opportunityId: row.opportunityId,
                opportunityName: row.opportunityName,
                accountName: row.accountName
            });
        }
    }
    return related;
}

function normalizeAppointmentRows(row) {
    const relatedServiceAppointments = flattenOpportunityEvidence(row).map((appointment, index) => {
        const lineKey =
            appointment.lineKey ||
            appointment.rowKey ||
            appointment.serviceAppointmentId ||
            `${row.rowKey || row.opportunityId || 'appointment'}-${index}`;

        return {
            ...appointment,
            lineKey,
            serviceAppointmentUrl: appointment.serviceAppointmentId
                ? `/lightning/r/ServiceAppointment/${appointment.serviceAppointmentId}/view`
                : null,
            createdDateValue: appointment.completionDateTime || appointment.createdDate
        };
    });

    const appointmentSearchTerms = relatedServiceAppointments.reduce((terms, appointment) => {
        terms.push(
            appointment.serviceAppointmentDisplay,
            appointment.serviceAppointmentNumber,
            appointment.workOrderNumber,
            appointment.description,
            appointment.serviceNote,
            appointment.invoiceNumber,
            appointment.technicianName
        );
        return terms;
    }, []);

    const invoices = (row.invoices || []).map((chip, index) => {
        const typePrefix =
            chip.invoiceType === 'Deposit' ? 'DP' : chip.invoiceType === 'Balance' ? 'Inv' : chip.invoiceType;
        const chipLabel = [typePrefix, chip.invoiceNumber].filter(Boolean).join(' ')
            + (chip.status ? ` · ${chip.status}` : '');
        return {
            ...chip,
            chipLabel,
            lineKey: `${chip.invoiceNumber || 'invoice'}-${index}`
        };
    });
    const invoiceChipDisplay = invoices
        .map(chip => chip.chipLabel || chip.invoiceNumber)
        .filter(Boolean)
        .join(', ');
    const reasonDisplay = (row.readinessReasons || []).join('; ');
    const firstLedgerId =
        row.ledgerId ||
        (row.workOrders || []).find(workOrder => workOrder.ledgerId)?.ledgerId;

    const searchIndex = [
        row.accountName,
        row.opportunityName,
        row.quoteNumber,
        reasonDisplay,
        invoiceChipDisplay,
        row.salespersonName,
        ...appointmentSearchTerms
    ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

    return {
        ...row,
        relatedServiceAppointments,
        invoices,
        invoiceChipDisplay,
        reasonDisplay,
        flagItems: buildFlagItems(row.readinessReasons),
        ledgerId: firstLedgerId,
        ownerName: row.ownerName || row.salespersonName,
        opportunityAmount: row.amountQuoted,
        opportunityAmountValue: row.amountQuoted,
        hasOpportunityAmount: row.amountQuoted !== undefined && row.amountQuoted !== null,
        serviceAppointmentCount: relatedServiceAppointments.length,
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
    return (rows || []).length;
}

function uniqueWorkOrderRowCount(sections, rowsForSection) {
    const keys = new Set();
    for (const section of sections || []) {
        for (const row of rowsForSection(section) || []) {
            keys.add(row.opportunityId || row.rowKey);
        }
    }
    return keys.size;
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

    if (sortField === 'createdDate' || sortField === 'completionDateTime') {
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
    for (const key of CATEGORY_KEYS) {
        next[key] = { sortedBy: DEFAULT_SORT_FIELD, sortDirection: 'asc' };
    }
    return next;
}

function hasInvMarker(value) {
    return typeof value === 'string' && value.toLowerCase().includes('inv');
}

function resolveInvSyncNumber(row) {
    const candidates = [row?.invoiceNumber, row?.woInvoiceNumber];
    for (const value of candidates) {
        if (hasInvMarker(value)) {
            return value.trim();
        }
    }
    return '';
}

export default class BillingControlCenterBilling extends LightningElement {
    _dateFilter = { ...DEFAULT_DATE_FILTER };
    _dateFilterSignature = JSON.stringify(DEFAULT_DATE_FILTER);
    _isConnected = false;
    _loadSequence = 0;
    _opportunityOwnerId = null;
    userPickerDisplayInfo = {
        primaryField: 'Name',
        additionalFields: ['Username']
    };
    userPickerMatchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Username' }]
    };

    @api useExternalToolbar = false;

    metrics = {};
    appointmentSections = [];
    selectedRowKeys = new Set();
    selectedEvidenceSaIds = new Set();
    flaggedEvidenceSaIds = new Set();
    expandedRowKeys = new Set();
    selectedServiceAppointments = [];
    isInvSyncRunning = false;
    sortState = defaultSortState();
    searchKey = '';
    isLoading = true;
    isRefreshing = false;
    selectedKpiKey;
    activeAccordionSections = [];
    isCompleteBillingModalOpen = false;
    selectedLedgerId;
    showLedgerModal = false;
    errorMessage;
    providerWarnings = [];
    configWarnings = [];
    invoicingTabConfig;
    invoicingConfigLoaded = false;
    invoicingDatasetIsActive = true;
    invoicingDatasetConfig;
    invoicingKpisByKey = {};
    invoicingSectionsByKey = {};
    invoicingActionsByKey = {};
    columnWidths = {};
    _resizeState;
    _boundResizeMove;
    _boundResizeEnd;

    workOrderColumns = WORK_ORDER_COLUMNS;

    @api
    get dateFilter() {
        return this._dateFilter;
    }

    set dateFilter(value) {
        const normalizedValue = resolveDateRange(
            value?.filterKey || DEFAULT_DATE_FILTER.filterKey,
            value?.startDate,
            value?.endDate
        );
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

    @api
    get opportunityOwnerId() {
        return this._opportunityOwnerId;
    }

    set opportunityOwnerId(value) {
        if (value === this._opportunityOwnerId) {
            return;
        }
        this._opportunityOwnerId = value;
        if (this._isConnected) {
            this.loadData();
        }
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

    connectedCallback() {
        this._isConnected = true;
        this.columnWidths = loadColumnWidths(INVOICING_COLUMN_WIDTHS_KEY);
        this.loadInvoicingConfig();
        this.loadData();
    }

    disconnectedCallback() {
        this.teardownColumnResize();
    }

    get heroTitle() {
        return this.invoicingTabConfig?.label || DEFAULT_HERO_TITLE;
    }

    get heroSubtitle() {
        return this.invoicingTabConfig?.description || DEFAULT_HERO_SUBTITLE;
    }

    get tableTitle() {
        return this.invoicingSectionsByKey.READY_TO_INVOICE?.label || DEFAULT_TABLE_TITLE;
    }

    get showDiagnostics() {
        return hasBillingControlCenterAdminAccess && this.diagnosticWarnings.length > 0;
    }

    get diagnosticWarnings() {
        return [...(this.providerWarnings || []), ...(this.configWarnings || [])];
    }

    get showTableShell() {
        if (!this.invoicingConfigLoaded) {
            return true;
        }

        const configuredSections = this.invoicingTabConfig?.sections || [];
        if (configuredSections.length === 0) {
            return false;
        }

        if (!this.invoicingSectionsByKey[INVOICING_SECTION_KEY]) {
            return true;
        }

        return this.invoicingDatasetIsActive;
    }

    get refreshLabel() {
        return this.invoicingActionsByKey.REFRESH?.label || DEFAULT_REFRESH_LABEL;
    }

    get toolbarRefreshLabel() {
        return this.isRefreshing ? 'Refreshing…' : this.refreshLabel;
    }

    get heroClass() {
        return this.useExternalToolbar ? 'hero hero_toolbar-only' : 'hero';
    }

    get showHeroIntro() {
        return !this.useExternalToolbar;
    }

    get showFullPageSpinner() {
        return this.isLoading && !(this.appointmentSections || []).length;
    }

    get isToolbarBusy() {
        return this.isLoading || this.isRefreshing || this.isInvSyncRunning;
    }

    get kpiLegendText() {
        return 'KPI tiles count Opportunities by readiness reason. An Opportunity can appear in more than one list.';
    }

    get overlapLegendText() {
        return 'Select a tile to jump to that readiness list.';
    }

    get activeSectionNames() {
        return this.activeAccordionSections;
    }

    get completeBillingLabel() {
        return this.invoicingActionsByKey.COMPLETE_BILLING?.label || DEFAULT_COMPLETE_BILLING_LABEL;
    }

    get heroActions() {
        if (this.useExternalToolbar) {
            return [];
        }

        if (this.invoicingConfigLoaded && !this.invoicingActionsByKey.REFRESH) {
            return [];
        }

        return [
            {
                key: 'refresh',
                label: this.toolbarRefreshLabel,
                iconName: 'utility:refresh',
                variant: 'neutral',
                disabled: this.isLoading || this.isRefreshing || this.isInvSyncRunning,
                title: this.toolbarRefreshLabel
            }
        ];
    }

    get tableActions() {
        if (!this.showTableShell) {
            return [];
        }

        if (this.invoicingConfigLoaded && !this.invoicingActionsByKey.COMPLETE_BILLING) {
            return [];
        }

        return [
            {
                key: 'invSync',
                label: DEFAULT_INV_SYNC_LABEL,
                variant: 'neutral',
                disabled: this.isLoading || this.isInvSyncRunning,
                title: 'Create invoices from existing SA/WO INV numbers in the current date range'
            },
            {
                key: 'completeBilling',
                label: this.completeBillingLabel,
                variant: 'brand',
                disabled: this.isCompleteBillingDisabled,
                title: this.completeBillingLabel
            }
        ];
    }

    get kpiTiles() {
        if (!this.invoicingConfigLoaded) {
            return [];
        }

        if (!this.invoicingDatasetIsActive) {
            return [];
        }

        const configuredKpis = this.invoicingTabConfig?.kpis || [];
        const configByKey = new Map(
            configuredKpis.map(configRecord => [normalizeConfigKey(configRecord?.developerKey), configRecord])
        );

        return KPI_CONFIG.map(definition =>
            this.buildKpiTile(definition, configByKey.get(normalizeConfigKey(definition.developerKey)))
        );
    }

    get isCompleteBillingDisabled() {
        return (
            this.isLoading
            || this.isRefreshing
            || this.isInvSyncRunning
            || (!this.selectedRowKeys.size && !this.selectedEvidenceSaIds.size)
        );
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
                rows = rows.filter(row => rowMatchesSearch(row, q));
            }

            const categorySort = this.sortState[section.categoryKey] || {
                sortedBy: DEFAULT_SORT_FIELD,
                sortDirection: 'asc'
            };
            rows = sortWorkOrderRows(rows, categorySort.sortedBy, categorySort.sortDirection);
            rows = decorateAccountGroups(
                rows.map(row => {
                    const isExpanded = row.rowKey ? this.expandedRowKeys.has(row.rowKey) : false;
                    const visitCount = row.completedEvidenceCount || row.relatedServiceAppointments?.length || 0;
                    return {
                    ...row,
                    flagItems: row.flagItems || buildFlagItems(row.readinessReasons),
                    isSelected: row.rowKey ? this.selectedRowKeys.has(row.rowKey) : false,
                    isExpanded,
                    showReviewBanner: row.showReviewBanner === true,
                    workOrders: (row.workOrders || []).map(workOrder => ({
                        ...workOrder,
                        appointments: (workOrder.appointments || []).map(appointment => ({
                            ...appointment,
                            canSelectAsEvidence: appointment.billed !== true,
                            isEvidenceSelected: this.selectedEvidenceSaIds.has(
                                appointment.serviceAppointmentId
                            ),
                            isFlaggedForReview:
                                appointment.flaggedForReview === true
                                || this.flaggedEvidenceSaIds.has(appointment.serviceAppointmentId),
                            flagReviewLabel:
                                appointment.flaggedForReview === true
                                || this.flaggedEvidenceSaIds.has(appointment.serviceAppointmentId)
                                    ? 'Flagged for review'
                                    : 'Flag for review',
                            actualEndTimeDisplay: formatActualEndTime(appointment.actualEndTime),
                            operationalUnassigned: !appointment.opportunityId,
                            evidenceSelectLabel:
                                'Include ' +
                                (appointment.serviceAppointmentNumber || 'visit') +
                                ' as invoice evidence',
                            parentOpportunityId: row.opportunityId,
                            parentOpportunityName: row.opportunityName,
                            parentAccountName: row.accountName,
                            parentWorkOrderId: workOrder.workOrderId,
                            parentWorkOrderNumber: workOrder.workOrderNumber,
                            opportunityAmount: row.amountQuoted,
                            invoiceableOpportunityAmount: row.remaining
                        }))
                    })),
                    evidenceToggleLabel: isExpanded
                        ? 'Hide evidence'
                        : `Evidence (${visitCount} visits, ${row.billedEvidenceCount || 0} billed)`,
                    evidenceRowKey: `${row.rowKey}-evidence`,
                    isLedgerActionDisabled: !row.ledgerId
                };
                })
            );
            const visibleOpportunityCount = countAppointments(rows);
            const definition = KPI_CONFIG.find(
                tile => normalizeConfigKey(tile.developerKey) === normalizeConfigKey(section.categoryKey)
            );
            const kpiCount = definition ? this.metrics[definition.countKey] : undefined;
            const listCount = visibleOpportunityCount;
            const showCountCaption =
                listCount !== undefined && kpiCount !== undefined && listCount !== kpiCount;
            const countCaption = showCountCaption
                ? `${listCount} Opportunities in list · ${kpiCount} Opportunities (KPI)`
                : undefined;

            return {
                categoryKey: section.categoryKey,
                categoryLabel: section.categoryLabel,
                titleWithCount: `${section.categoryLabel} (${visibleOpportunityCount} ${
                    visibleOpportunityCount === 1 ? 'Opportunity' : 'Opportunities'
                })`,
                filteredRows: rows,
                isEmpty: rows.length === 0,
                sortedBy: categorySort.sortedBy,
                sortDirection: categorySort.sortDirection,
                columns: buildRenderableColumns(
                    this.workOrderColumns,
                    categorySort.sortedBy,
                    categorySort.sortDirection,
                    this.columnWidths
                ),
                visibleOpportunityCount,
                kpiCount,
                listCount,
                showCountCaption,
                countCaption
            };
        });
    }

    get visibleAccordionSections() {
        if (!this.showTableShell) {
            return [];
        }

        if (this.invoicingConfigLoaded) {
            const configuredSections = this.invoicingTabConfig?.sections || [];
            if (
                configuredSections.length > 0 &&
                !this.invoicingSectionsByKey[INVOICING_SECTION_KEY]
            ) {
                console.warn(
                    'Skipping unsupported Invoicing section config. Falling back to current runtime sections.'
                );
            }
        }

        const visibleKeys = new Set(CATEGORY_KEYS);
        return this.accordionSections.filter(section => visibleKeys.has(section.categoryKey));
    }

    get invoiceModalOpportunityId() {
        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                if (row.rowKey && this.selectedRowKeys.has(row.rowKey) && row.opportunityId) {
                    return row.opportunityId;
                }
            }
        }
        const firstEvidence = (this.selectedServiceAppointments || [])[0];
        return firstEvidence?.contextOpportunityId || firstEvidence?.opportunityId || null;
    }

    get completeBillingModalSelections() {
        return this.selectedServiceAppointments.map(row => ({
            serviceAppointmentId: row.serviceAppointmentId,
            serviceAppointmentNumber: row.serviceAppointmentNumber,
            opportunityId: row.opportunityId,
            opportunityName: row.opportunityName,
            accountName: row.accountName,
            workOrderNumber: row.workOrderNumber,
            workOrderId: row.workOrderId,
            ledgerId: row.ledgerId,
            unassigned: row.unassigned === true || !row.opportunityId,
            contextOpportunityId: row.contextOpportunityId,
            completionDateTime: row.completionDateTime,
            technicianName: row.technicianName,
            opportunityAmount: row.opportunityAmount,
            invoiceableOpportunityAmount: row.invoiceableOpportunityAmount,
            invoiceNumber: resolveInvSyncNumber(row)
        }));
    }

    get billableCount() {
        return this.metrics.readyToBill || 0;
    }

    get totalWorkOrderRows() {
        return uniqueWorkOrderRowCount(this.appointmentSections, section => section.rows);
    }

    get searchSummary() {
        if (!this.searchKey.trim()) {
            return `${this.totalWorkOrderRows} Opportunities across lists`;
        }
        const shownCount = uniqueWorkOrderRowCount(
            this.visibleAccordionSections,
            section => section.filteredRows
        );
        return `Showing ${shownCount} matching Opportunities`;
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

    handleInvoiceViewLedger(event) {
        const ledgerId = event.detail?.ledgerId;
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

    handleOpenCompleteBillingModal() {
        if (this.isLoading || this.isRefreshing || this.isInvSyncRunning) {
            return;
        }
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
        this.isCompleteBillingModalOpen = true;
    }

    async handleInvSync() {
        if (this.isLoading || this.isInvSyncRunning) {
            return;
        }

        this.isInvSyncRunning = true;
        try {
            const result = await syncExistingInvoiceNumbers({
                dateFilter: this.dateFilter || null,
                opportunityOwnerId: this.opportunityOwnerId || null
            });
            const createdCount = result?.invoicesCreated || 0;
            const skippedCount = result?.skippedCount || 0;
            const stampedCount = result?.serviceAppointmentsUpdated || 0;
            if (result?.queued) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'INV-Sync started',
                        message: 'Refresh Invoicing and Receivables when the job finishes.',
                        variant: 'success'
                    })
                );
            } else {
                const parts = [`Created ${createdCount} invoice${createdCount === 1 ? '' : 's'}`];
                if (stampedCount > 0) {
                    parts.push(`stamped ${stampedCount} appointment${stampedCount === 1 ? '' : 's'}`);
                }
                if (skippedCount > 0) {
                    parts.push(`skipped ${skippedCount}`);
                }
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'INV-Sync',
                        message: parts.join('. ') + '.',
                        variant: skippedCount > 0 && createdCount === 0 ? 'warning' : 'success'
                    })
                );
            }
            await this.loadData(true);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'INV-Sync failed',
                    message: error?.body?.message || error?.message || 'Unable to sync existing invoice numbers.',
                    variant: 'error'
                })
            );
        } finally {
            this.isInvSyncRunning = false;
        }
    }

    handleCompleteBillingClose() {
        this.isCompleteBillingModalOpen = false;
    }

    async handleCompleteBillingSuccess() {
        this.isCompleteBillingModalOpen = false;
        this.selectedRowKeys = new Set();
        this.selectedServiceAppointments = [];
        await this.loadData(true);
    }

    async handleRefresh() {
        this.selectedRowKeys = new Set();
        this.selectedServiceAppointments = [];
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
        this._dateFilter = resolveDateRange(
            detail.filterKey || DEFAULT_DATE_FILTER.filterKey,
            detail.startDate,
            detail.endDate
        );
        this._dateFilterSignature = JSON.stringify(this._dateFilter);
        this.emitSharedFilterChange();
        if (this._isConnected) {
            this.loadData(true);
        }
    }

    handleOpportunityOwnerChange(event) {
        const nextOwnerId = event.detail?.recordId || null;
        if (nextOwnerId === this.opportunityOwnerId) {
            return;
        }
        this._opportunityOwnerId = nextOwnerId;
        this.emitSharedFilterChange();
        if (this._isConnected) {
            this.loadData();
        }
    }

    emitSharedFilterChange() {
        if (!this.useExternalToolbar) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('sharedfilterchange', {
                detail: {
                    dateFilter: { ...this.dateFilter },
                    opportunityOwnerId: this.opportunityOwnerId || null
                }
            })
        );
    }

    handleKpiTileClick(event) {
        const detail = event.detail || {};
        const rawKey = detail.developerKey || detail.key;
        this.selectedKpiKey = rawKey;
        const developerKey = normalizeConfigKey(
            KPI_CONFIG.find(
                config =>
                    config.key === rawKey ||
                    normalizeConfigKey(config.developerKey) === normalizeConfigKey(rawKey)
            )?.developerKey || rawKey
        );
        if (!developerKey || !CATEGORY_KEYS.includes(developerKey)) {
            return;
        }

        this.activeAccordionSections = [developerKey];

        Promise.resolve().then(() => {
            const section = this.template.querySelector(
                `lightning-accordion-section[name="${developerKey}"]`
            );
            section?.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    }

    handleTableActionClick(event) {
        if (event.detail?.key === 'invSync') {
            this.handleInvSync();
            return;
        }
        if (event.detail?.key === 'completeBilling') {
            if (this.isCompleteBillingDisabled) {
                return;
            }
            this.handleOpenCompleteBillingModal();
        }
    }

    buildKpiTile(definition, configRecord) {
        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: NUMBER_FORMATTER.format(this.metrics[definition.countKey] || 0),
            countText: definition.amountKey
                ? CURRENCY_FORMATTER.format(this.metrics[definition.amountKey] || 0)
                : ''
        };
    }

    handleHeaderSort(event) {
        const categoryKey = event.currentTarget?.dataset?.bucket;
        const fieldName = event.currentTarget?.dataset?.field;
        if (!categoryKey || !fieldName || fieldName === 'ledgerId' || !this.sortState[categoryKey]) {
            return;
        }

        const currentSort = this.sortState[categoryKey];
        const sortDirection =
            currentSort.sortedBy === fieldName && currentSort.sortDirection === 'asc' ? 'desc' : 'asc';
        this.sortState = {
            ...this.sortState,
            [categoryKey]: { sortedBy: fieldName, sortDirection }
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
        saveColumnWidths(INVOICING_COLUMN_WIDTHS_KEY, this.columnWidths);
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

    handleGroupSelection(event) {
        const categoryKey = event.currentTarget?.dataset?.bucket;
        const rowKey = event.currentTarget?.dataset?.rowKey;
        if (!categoryKey || !rowKey) {
            return;
        }

        const section = (this.appointmentSections || []).find(item => item.categoryKey === categoryKey);
        if (!section) {
            return;
        }

        const nextSelection = new Set(this.selectedRowKeys);
        if (event.target.checked) {
            nextSelection.add(rowKey);
        } else {
            nextSelection.delete(rowKey);
        }

        this.selectedRowKeys = nextSelection;
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
    }

    handleToggleEvidence(event) {
        const rowKey = event.currentTarget?.dataset?.rowKey;
        if (!rowKey) {
            return;
        }
        const nextExpanded = new Set(this.expandedRowKeys);
        if (nextExpanded.has(rowKey)) {
            nextExpanded.delete(rowKey);
        } else {
            nextExpanded.add(rowKey);
        }
        this.expandedRowKeys = nextExpanded;
    }

    handleEvidenceSaChange(event) {
        const serviceAppointmentId = event.target?.dataset?.saId;
        if (!serviceAppointmentId) {
            return;
        }
        const nextSelection = new Set(this.selectedEvidenceSaIds);
        if (event.target.checked) {
            nextSelection.add(serviceAppointmentId);
        } else {
            nextSelection.delete(serviceAppointmentId);
        }
        this.selectedEvidenceSaIds = nextSelection;
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
    }

    async handleFlagForReview(event) {
        const serviceAppointmentId = event.currentTarget?.dataset?.saId;
        if (!serviceAppointmentId) {
            return;
        }
        try {
            await flagAppointmentForReview({ serviceAppointmentId });
            const nextFlagged = new Set(this.flaggedEvidenceSaIds);
            nextFlagged.add(serviceAppointmentId);
            this.flaggedEvidenceSaIds = nextFlagged;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Flagged for review',
                    message: 'An accounting note was written on the Work Order Ledger.',
                    variant: 'success'
                })
            );
            await this.loadData(true);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    async loadData(forceRefresh = false) {
        if ((this.appointmentSections || []).length > 0) {
            this.isRefreshing = true;
        } else {
            this.isLoading = true;
        }
        this.errorMessage = undefined;
        const cacheKey = buildRuntimeCacheKey(this.dateFilter, this.opportunityOwnerId);
        const refreshToken = forceRefresh ? Date.now() : null;
        this._loadSequence = (this._loadSequence || 0) + 1;
        const loadSequence = this._loadSequence;

        try {
            if (forceRefresh) {
                invoicingRuntimeCache.delete(cacheKey);
            } else if (invoicingRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(invoicingRuntimeCache.get(cacheKey)));
                return;
            }

            const runtimeData = await getTabRuntime({
                refreshToken,
                filterKey: this.dateFilter?.filterKey || DEFAULT_DATE_FILTER.filterKey,
                startDate: this.dateFilter?.startDate || null,
                endDate: this.dateFilter?.endDate || null,
                opportunityOwnerId: this.opportunityOwnerId || null
            });
            invoicingRuntimeCache.set(cacheKey, cloneRuntimeData(runtimeData));
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.applyRuntimeData(runtimeData);
        } catch (error) {
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.providerWarnings = [];
            this.metrics = {};
            this.appointmentSections = [];
            this.selectedRowKeys = new Set();
            this.selectedServiceAppointments = [];
            this.sortState = defaultSortState();
            this.errorMessage = this.reduceError(error);
        } finally {
            if (loadSequence === this._loadSequence) {
                this.isLoading = false;
                this.isRefreshing = false;
            }
        }
    }

    applyRuntimeData(runtimeData) {
        this.providerWarnings = runtimeData?.warnings || [];
        (runtimeData?.warnings || []).forEach(warning => console.warn(warning));
        const metrics = runtimeData?.metrics;
        const groups = runtimeData?.groups;

        this.metrics = { ...(metrics || {}) };
        this.appointmentSections = this.normalizeSections(groups || []);
        this.sortState = {
            ...defaultSortState(),
            ...Object.fromEntries(
                (this.appointmentSections || [])
                    .filter(section => section.categoryKey)
                    .map(section => [
                        section.categoryKey,
                        this.sortState[section.categoryKey] || {
                            sortedBy: DEFAULT_SORT_FIELD,
                            sortDirection: 'asc'
                        }
                    ])
            )
        };
        this.pruneSelectedRows();
        this.selectedServiceAppointments = this.buildSelectedServiceAppointments();
    }

    async loadInvoicingConfig() {
        try {
            this.configWarnings = [];
            const config = await getTabConfig({ developerKey: 'INVOICING' });
            if (!config) {
                const warning = 'Invoicing KPI configuration missing for this tab. KPI cards hidden.';
                console.warn(warning);
                this.configWarnings = [warning];
                return;
            }

            this.invoicingTabConfig = config;
            this.invoicingConfigLoaded = true;
            this.invoicingKpisByKey = buildConfigMap(config.kpis);
            this.invoicingSectionsByKey = buildConfigMap(config.sections);
            this.invoicingActionsByKey = buildConfigMap(config.actions);
            this.workOrderColumns = WORK_ORDER_COLUMNS;
            this.invoicingDatasetConfig = (config.datasets || []).find(
                dataset => normalizeConfigKey(dataset?.developerKey) === INVOICING_DATASET_KEY
            );
            this.invoicingDatasetIsActive = Boolean(this.invoicingDatasetConfig);

            if (!this.invoicingDatasetIsActive) {
                console.warn(
                    'Invoicing dataset config INVOICING_SERVICE_APPOINTMENTS is missing or inactive. Rendering safe empty state for config-driven Invoicing UI.'
                );
            }

            if ((config.kpis || []).length === 0) {
                this.configWarnings = ['Invoicing KPI configuration missing for this tab. KPI cards hidden.'];
            }
        } catch (error) {
            console.warn(
                'Failed to load Billing Control Center Invoicing config. KPI cards will remain hidden.',
                error
            );
            this.invoicingTabConfig = undefined;
            this.invoicingConfigLoaded = false;
            this.invoicingDatasetIsActive = true;
            this.invoicingDatasetConfig = undefined;
            this.invoicingKpisByKey = {};
            this.invoicingSectionsByKey = {};
            this.invoicingActionsByKey = {};
            this.workOrderColumns = WORK_ORDER_COLUMNS;
            this.configWarnings = ['Invoicing KPI configuration missing for this tab. KPI cards hidden.'];
        }
    }

    normalizeSections(sections) {
        return (sections || []).map(section => {
            const sourceRows =
                section.opportunityRows && section.opportunityRows.length
                    ? section.opportunityRows
                    : section.rows || [];
            return {
                ...section,
                rows: sourceRows.map((row, index) => {
                    const rowKey =
                        row.rowKey ||
                        (row.opportunityId
                            ? `${section.categoryKey}-OPP-${row.opportunityId}`
                            : `${section.categoryKey}-${index}`);
                    return {
                        ...normalizeAppointmentRows({
                            ...row,
                            rowKey,
                            accountUrl: accountRecordUrl(row.accountId),
                            opportunityUrl: opportunityRecordUrl(row.opportunityId)
                        }),
                        rowKey
                    };
                })
            };
        });
    }

    pruneSelectedRows() {
        const availableRowKeys = new Set();
        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                if (row.rowKey) {
                    availableRowKeys.add(row.rowKey);
                }
            }
        }

        const prunedSelection = Array.from(this.selectedRowKeys).filter(
            rowKey => availableRowKeys.has(rowKey)
        );
        this.selectedRowKeys = new Set(prunedSelection);
    }

    buildSelectedServiceAppointments() {
        const selectedRows = [];
        const seenServiceAppointmentIds = new Set();
        if (this.selectedEvidenceSaIds.size === 0) {
            return selectedRows;
        }

        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                const appointments = this.flattenEvidenceAppointments(row);
                for (const appointment of appointments) {
                    const serviceAppointmentId = appointment.serviceAppointmentId;
                    if (
                        !serviceAppointmentId
                        || appointment.billed
                        || seenServiceAppointmentIds.has(serviceAppointmentId)
                        || !this.selectedEvidenceSaIds.has(serviceAppointmentId)
                    ) {
                        continue;
                    }
                    seenServiceAppointmentIds.add(serviceAppointmentId);
                    selectedRows.push({
                        serviceAppointmentId,
                        serviceAppointmentNumber: appointment.serviceAppointmentNumber,
                        opportunityId: appointment.opportunityId || null,
                        opportunityName: appointment.opportunityName || null,
                        accountName: appointment.accountName || appointment.parentAccountName || row.accountName,
                        workOrderNumber: appointment.workOrderNumber,
                        workOrderId: appointment.workOrderId,
                        ledgerId: appointment.ledgerId,
                        unassigned: !appointment.opportunityId,
                        contextOpportunityId: row.opportunityId,
                        completionDateTime: appointment.completionDateTime || appointment.actualEndTime,
                        technicianName: appointment.technicianName || row.technicianName,
                        opportunityAmount: appointment.opportunityAmount ?? row.opportunityAmount ?? row.amountQuoted,
                        invoiceableOpportunityAmount:
                            appointment.invoiceableOpportunityAmount ?? row.invoiceableOpportunityAmount ?? row.remaining,
                        invoiceNumber: appointment.invoiceNumber || row.invoiceNumber,
                        woInvoiceNumber: appointment.woInvoiceNumber || row.woInvoiceNumber
                    });
                }
            }
        }

        return selectedRows;
    }

    flattenEvidenceAppointments(row) {
        const appointments = [];
        for (const workOrder of row.workOrders || []) {
            for (const appointment of workOrder.appointments || []) {
                appointments.push({
                    ...appointment,
                    workOrderId: workOrder.workOrderId,
                    workOrderNumber: workOrder.workOrderNumber,
                    ledgerId: workOrder.ledgerId
                });
            }
        }
        return appointments.length ? appointments : [row];
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