import { LightningElement, api } from 'lwc';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getInvoicingRuntimeData from '@salesforce/apex/BillingControl_DataProvider.getInvoicingRuntimeData';

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');
const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2
});

const KPI_CONFIG = [
    {
        key: 'completedMoreThan2Days',
        developerKey: 'AGED_COMPLETED_WORK',
        title: 'Aged Ready to Bill (>2 Days)',
        icon: 'utility:clock',
        hint: 'Ready-to-bill diary records older than 2 days.',
        isCurrency: false
    },
    {
        key: 'readyToBill',
        developerKey: 'BILLABLE_SERVICE_APPOINTMENTS',
        title: 'Ready to Bill',
        icon: 'utility:check',
        hint: 'Diary records ready for invoice batch creation.',
        isCurrency: false
    },
    {
        key: 'unbilledRevenue',
        developerKey: 'UNINVOICED_REVENUE',
        title: 'Uninvoiced Amount',
        icon: 'utility:money',
        hint: 'Derived from order diary billable amounts.',
        isCurrency: true
    }
];

const CATEGORY_KEYS = ['AGED_COMPLETED', 'READY_TO_BILL', 'UNBILLED_REVENUE'];
const INVOICING_DATASET_KEY = 'INVOICING_SERVICE_APPOINTMENTS';
const INVOICING_SECTION_KEY = 'READY_TO_INVOICE';
const invoicingRuntimeCache = new Map();
const DEFAULT_SORT_FIELD = 'workOrderUrl';
const DEFAULT_HERO_TITLE = 'Ready-to-Bill Order Diary';
const DEFAULT_HERO_SUBTITLE =
    'Review ready-to-bill diary records and create invoice batches.';
const DEFAULT_TABLE_TITLE = 'Ready-to-bill diary records';
const DEFAULT_REFRESH_LABEL = 'Refresh';
const DEFAULT_COMPLETE_BILLING_LABEL = 'Complete Billing';

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
        label: 'Service Appointment',
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
        developerKey: 'WORK_ORDER_STATUS',
        configFieldApiName: 'status',
        label: 'Diary Status',
        fieldName: 'status',
        type: 'text',
        sortable: true
    },
    {
        developerKey: 'OPPORTUNITY_AMOUNT',
        configFieldApiName: 'opportunityAmount',
        label: 'Billable Amount',
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
    }
];

function normalizeConfigKey(value) {
    return value ? String(value).trim().toUpperCase() : '';
}

function cloneRuntimeData(value) {
    return value ? JSON.parse(JSON.stringify(value)) : value;
}

function buildRuntimeCacheKey(dateFilter) {
    return JSON.stringify(dateFilter || { filterKey: 'Today' });
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

        matchedColumns.push({
            ...matchedColumn,
            label: configColumn.label || matchedColumn.label
        });
    });

    if (matchedColumns.length === 0) {
        return WORK_ORDER_COLUMNS;
    }
    return matchedColumns;
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
    _dateFilter;
    _dateFilterSignature = '';
    _isConnected = false;

    @api useExternalToolbar = false;

    metrics = {};
    appointmentSections = [];
    selectedRowKeys = new Set();
    selectedServiceAppointments = [];
    sortState = defaultSortState();
    searchKey = '';
    isLoading = true;
    isCompleteBillingModalOpen = false;
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

    connectedCallback() {
        this._isConnected = true;
        this.loadInvoicingConfig();
        this.loadData();
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

    get externalDateFilterKey() {
        return this.dateFilter?.filterKey || 'Today';
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
        if (configuredKpis.length === 0) {
            return [];
        }

        const tiles = [];
        configuredKpis.forEach(configRecord => {
            const definition = KPI_CONFIG.find(
                tile => normalizeConfigKey(tile.developerKey) === normalizeConfigKey(configRecord?.developerKey)
            );

            if (!definition) {
                console.warn(
                    `Skipping unsupported Invoicing KPI config: ${configRecord?.developerKey || 'unknown'}`
                );
                return;
            }

            tiles.push(this.buildKpiTile(definition, configRecord));
        });

        return tiles;
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
                .filter(row => row.rowKey && this.selectedRowKeys.has(row.rowKey))
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

    handleExternalDateFilterChange(event) {
        this.dispatchEvent(
            new CustomEvent('datefilterchange', {
                detail: event.detail
            })
        );
    }

    handleHeroActionClick(event) {
        if (event.detail?.key === 'refresh') {
            this.handleRefresh();
        }
    }

    handleTableActionClick(event) {
        if (event.detail?.key === 'completeBilling') {
            this.handleOpenCompleteBillingModal();
        }
    }

    buildKpiTile(definition, configRecord) {
        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: definition.isCurrency
                ? CURRENCY_FORMATTER.format(this.metrics[definition.key] || 0)
                : NUMBER_FORMATTER.format(this.metrics[definition.key] || 0),
            countText: 'Diary Records'
        };
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

        const nextSelection = new Set(this.selectedRowKeys);

        for (const row of section.rows || []) {
            if (row.rowKey) {
                nextSelection.delete(row.rowKey);
            }
        }

        for (const row of event.detail.selectedRows || []) {
            if (row && row.rowKey) {
                nextSelection.add(row.rowKey);
            }
        }

        this.selectedRowKeys = nextSelection;
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
        const cacheKey = buildRuntimeCacheKey(this.dateFilter);
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
                dateFilter: this.dateFilter
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
                    serviceAppointmentDisplay:
                        row.serviceAppointmentDisplay || row.serviceAppointmentNumber || row.serviceAppointmentId,
                    relatedServiceAppointments
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

                const serviceAppointmentId = row.serviceAppointmentId;
                if (!serviceAppointmentId || seenServiceAppointmentIds.has(serviceAppointmentId)) {
                    continue;
                }

                seenServiceAppointmentIds.add(serviceAppointmentId);
                selectedRows.push({
                    serviceAppointmentId,
                    serviceAppointmentNumber: row.serviceAppointmentNumber,
                    opportunityId: row.opportunityId,
                    opportunityName: row.opportunityName,
                    accountName: row.accountName,
                    workOrderNumber: row.workOrderNumber,
                    completionDateTime: row.completionDateTime,
                    technicianName: row.technicianName,
                    billableAmount: row.billableAmount
                });
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