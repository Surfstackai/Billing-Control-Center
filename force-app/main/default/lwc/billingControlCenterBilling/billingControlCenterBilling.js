import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getInvoicingRuntimeData from '@salesforce/apex/BillingControl_DataProvider.getInvoicingRuntimeData';
import syncExistingInvoiceNumbers from '@salesforce/apex/BillingControl_Invoicing.syncExistingInvoiceNumbers';
import {
    MIN_COLUMN_WIDTH,
    INVOICING_COLUMN_WIDTHS_KEY,
    columnWidthStyle,
    loadColumnWidths,
    saveColumnWidths
} from 'c/billingControlCenterColumnResize';
import { decorateAccountGroups, sortRowsWithAccountGroup } from 'c/billingControlCenterAccountGroup';

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');
const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2
});

const KPI_CONFIG = [
    {
        key: 'completedToday',
        developerKey: 'COMPLETED_TODAY',
        title: 'Completed Today',
        icon: 'utility:event',
        hint: 'Ready-to-bill completions today.',
        countKey: 'completedTodayCount',
        amountKey: 'completedTodayAmount'
    },
    {
        key: 'completedThisWeek',
        developerKey: 'COMPLETED_THIS_WEEK',
        title: 'Completed This Week',
        icon: 'utility:weeklyview',
        hint: 'Ready-to-bill completions in the current calendar week, including today.',
        countKey: 'completedThisWeekCount',
        amountKey: 'completedThisWeekAmount'
    },
    {
        key: 'completedLater',
        developerKey: 'COMPLETED_LATER',
        title: 'Completed Later',
        icon: 'utility:check',
        hint: 'All ready-to-bill completions in the current date range, including today.',
        countKey: 'completedLaterCount',
        amountKey: 'completedLaterAmount'
    }
];

const CATEGORY_KEYS = ['AGED_COMPLETED', 'READY_TO_BILL', 'UNBILLED_REVENUE'];
const INVOICING_DATASET_KEY = 'INVOICING_SERVICE_APPOINTMENTS';
const INVOICING_SECTION_KEY = 'READY_TO_INVOICE';
const invoicingRuntimeCache = new Map();
const DEFAULT_SORT_FIELD = 'accountUrl';
const DEFAULT_HERO_TITLE = 'Ready to Bill';
const DEFAULT_HERO_SUBTITLE =
    'Review completed Service Appointments and create invoice batches.';
const DEFAULT_TABLE_TITLE = 'Ready-to-bill Service Appointments';
const DEFAULT_REFRESH_LABEL = 'Refresh';
const DEFAULT_COMPLETE_BILLING_LABEL = 'Complete Billing';
const DEFAULT_INV_SYNC_LABEL = 'INV-Sync';
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
        developerKey: 'INVOICE_NUMBER',
        configFieldApiName: 'invoiceNumber',
        label: 'Invoice Number',
        fieldName: 'invoiceNumber',
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
        label: 'Service Appointment',
        fieldName: 'serviceAppointmentDisplay',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        developerKey: 'CREATED_DATE',
        configFieldApiName: 'completionDateTime',
        label: 'Actual Completion Date',
        fieldName: 'completionDateTime',
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
        developerKey: 'WORK_ORDER_STATUS',
        configFieldApiName: 'status',
        label: 'Work Order Status',
        fieldName: 'status',
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
        label: 'Account Owner',
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
    INVOICE_NUMBER: 'invoice-number',
    WORK_ORDER: 'work-order',
    SERVICE_APPOINTMENTS: 'service-appointment',
    CREATED_DATE: 'created-date',
    SUBJECT: 'subject',
    WORK_ORDER_STATUS: 'status',
    OPPORTUNITY_AMOUNT: 'opportunity-amount',
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
    return injectViewLedgerColumn(injectInvoiceNumberColumn(matchedColumns));
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
            isInvoiceNumber: developerKey === 'INVOICE_NUMBER',
            isWorkOrder: developerKey === 'WORK_ORDER',
            isServiceAppointment: developerKey === 'SERVICE_APPOINTMENTS',
            isCreatedDate: developerKey === 'CREATED_DATE',
            isSubject: developerKey === 'SUBJECT',
            isStatus: developerKey === 'WORK_ORDER_STATUS',
            isOpportunityAmount,
            isOwner: developerKey === 'OWNER',
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
            createdDateValue: appointment.completionDateTime || appointment.createdDate
        };
    });

    const appointmentSearchTerms = relatedServiceAppointments.reduce((terms, appointment) => {
        terms.push(
            appointment.serviceAppointmentDisplay,
            appointment.serviceAppointmentNumber,
            appointment.subject,
            appointment.status,
            appointment.invoiceNumber,
            appointment.ownerName
        );
        return terms;
    }, []);

    const searchIndex = [
        row.accountName,
        row.opportunityName,
        row.workOrderNumber,
        ...appointmentSearchTerms
    ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

    return {
        ...row,
        relatedServiceAppointments,
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

    metrics = {};
    appointmentSections = [];
    selectedRowKeys = new Set();
    selectedServiceAppointments = [];
    isInvSyncRunning = false;
    sortState = defaultSortState();
    searchKey = '';
    isLoading = true;
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
                label: this.refreshLabel,
                iconName: 'utility:refresh',
                variant: 'brand',
                disabled: this.isLoading,
                title: this.refreshLabel
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
                rows = rows.filter(row => rowMatchesSearch(row, q));
            }

            const categorySort = this.sortState[section.categoryKey] || {
                sortedBy: DEFAULT_SORT_FIELD,
                sortDirection: 'asc'
            };
            rows = sortWorkOrderRows(rows, categorySort.sortedBy, categorySort.sortDirection);
            rows = decorateAccountGroups(
                rows.map(row => ({
                    ...row,
                    isSelected: row.rowKey ? this.selectedRowKeys.has(row.rowKey) : false,
                    isLedgerActionDisabled: !row.ledgerId
                }))
            );
            const visibleAppointmentCount = countAppointments(rows);

            return {
                categoryKey: section.categoryKey,
                categoryLabel: section.categoryLabel,
                titleWithCount: `${section.categoryLabel} (${visibleAppointmentCount})`,
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
                visibleAppointmentCount
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

        return this.accordionSections.filter(
            section => section.categoryKey !== 'AGED_COMPLETED' && section.categoryKey !== 'UNBILLED_REVENUE'
        );
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
            opportunityAmount: row.opportunityAmount,
            invoiceableOpportunityAmount: row.invoiceableOpportunityAmount,
            invoiceNumber: resolveInvSyncNumber(row)
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
            return `${this.totalWorkOrderRows} work order rows across buckets`;
        }
        const shownCount = this.visibleAccordionSections.reduce((sum, section) => sum + section.filteredRows.length, 0);
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
        const filterKey = detail.filterKey || DEFAULT_DATE_FILTER.filterKey;
        this.dateFilter = {
            filterKey,
            startDate: filterKey === 'Custom' ? detail.startDate || null : null,
            endDate: filterKey === 'Custom' ? detail.endDate || null : null
        };
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

    handleTableActionClick(event) {
        if (event.detail?.key === 'invSync') {
            this.handleInvSync();
            return;
        }
        if (event.detail?.key === 'completeBilling') {
            this.handleOpenCompleteBillingModal();
        }
    }

    buildKpiTile(definition, configRecord) {
        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: NUMBER_FORMATTER.format(this.metrics[definition.countKey] || 0),
            countText: CURRENCY_FORMATTER.format(this.metrics[definition.amountKey] || 0)
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

    async loadData(forceRefresh = false) {
        this.isLoading = true;
        this.errorMessage = undefined;
        const cacheKey = buildRuntimeCacheKey(this.dateFilter, this.opportunityOwnerId);
        const refreshToken = forceRefresh ? Date.now() : null;

        try {
            if (forceRefresh) {
                invoicingRuntimeCache.delete(cacheKey);
            } else if (invoicingRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(invoicingRuntimeCache.get(cacheKey)));
                return;
            }

            const runtimeData = await getInvoicingRuntimeData({
                refreshToken,
                dateFilter: this.dateFilter || null,
                opportunityOwnerId: this.opportunityOwnerId || null
            });
            invoicingRuntimeCache.set(cacheKey, cloneRuntimeData(runtimeData));
            this.applyRuntimeData(runtimeData);
        } catch (error) {
            this.providerWarnings = [];
            this.metrics = {};
            this.appointmentSections = [];
            this.selectedRowKeys = new Set();
            this.selectedServiceAppointments = [];
            this.sortState = defaultSortState();
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyRuntimeData(runtimeData) {
        this.providerWarnings = runtimeData?.warnings || [];
        (runtimeData?.warnings || []).forEach(warning => console.warn(warning));
        const metrics = runtimeData?.metrics;
        const groups = runtimeData?.groups;

        this.metrics = { ...(metrics || {}) };
        this.appointmentSections = this.normalizeSections(groups || []);
        this.sortState = defaultSortState();
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
            this.workOrderColumns = buildConfiguredColumns(config.columns);
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
        return (sections || []).map(section => ({
            ...section,
            rows: (section.rows || []).map((row, index) => {
                const rowKey =
                    row.rowKey ||
                    row.serviceAppointmentId ||
                    (row.orderId ? `ORDER-${row.orderId}` : row.workOrderId ? `WO-${row.workOrderId}-${index}` : `${section.categoryKey}-${index}`);
                return {
                    ...normalizeAppointmentRows({
                        ...row,
                        rowKey,
                        accountUrl: accountRecordUrl(row.accountId),
                        opportunityUrl: opportunityRecordUrl(row.opportunityId),
                        workOrderUrl: workOrderRecordUrl(row.workOrderId),
                        serviceAppointmentDisplay:
                            row.serviceAppointmentDisplay || row.serviceAppointmentNumber || row.serviceAppointmentId,
                        relatedServiceAppointments: (row.relatedServiceAppointments || []).map(appointment => ({
                            ...appointment,
                            accountName: appointment.accountName || row.accountName,
                            opportunityId: appointment.opportunityId || row.opportunityId,
                            opportunityName: appointment.opportunityName || row.opportunityName,
                            workOrderNumber: appointment.workOrderNumber || row.workOrderNumber
                        }))
                    }),
                    rowKey
                };
            }),
            opportunityGroups: (section.opportunityGroups || []).map(group => ({
                ...group,
                rows: (group.rows || []).map(row => ({ ...row }))
            }))
        }));
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
        if (!this.selectedRowKeys.size) {
            return [];
        }

        const selectedRows = [];
        const seenServiceAppointmentIds = new Set();

        for (const section of this.appointmentSections || []) {
            for (const row of section.rows || []) {
                if (!row.rowKey || !this.selectedRowKeys.has(row.rowKey)) {
                    continue;
                }

                const appointments =
                    row.relatedServiceAppointments && row.relatedServiceAppointments.length
                        ? row.relatedServiceAppointments
                        : [row];

                for (const appointment of appointments) {
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
                        technicianName: appointment.technicianName || row.technicianName,
                        opportunityAmount: appointment.opportunityAmount ?? row.opportunityAmount,
                        invoiceableOpportunityAmount:
                            appointment.invoiceableOpportunityAmount ?? row.invoiceableOpportunityAmount,
                        invoiceNumber: appointment.invoiceNumber || row.invoiceNumber,
                        woInvoiceNumber: appointment.woInvoiceNumber || row.woInvoiceNumber
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