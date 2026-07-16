import { LightningElement, api } from 'lwc';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getOrdersRuntimeData from '@salesforce/apex/BillingControl_DataProvider.getOrdersRuntimeData';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const NUMBER_FORMATTER = new Intl.NumberFormat('en-US');

const BUCKET_KEYS = ['UNSCHEDULED', 'SCHEDULED', 'SCHEDULED_TODAY', 'COMPLETED_TODAY'];
const ORDERS_DATASET_KEY = 'ORDERS_WORK_ORDERS';
const ordersRuntimeCache = new Map();

const DEFAULT_SORT_FIELD = 'workOrderUrl';
const DEFAULT_HERO_TITLE = 'Work Orders Pending Scheduling or Completion';
const DEFAULT_HERO_SUBTITLE =
    'Closed Won pipeline: unscheduled work, scheduled work, scheduled for today, and completed today.';
const DEFAULT_TABLE_TITLE = 'Pipeline work orders by bucket';
const DEFAULT_REFRESH_LABEL = 'Refresh';

const KPI_CONFIG = [
    {
        key: 'unscheduled',
        developerKey: 'UNSCHEDULED',
        revenueKey: 'unscheduledRevenue',
        countKey: 'unscheduledCount',
        title: 'Unscheduled Work',
        icon: 'utility:date_input',
        hint: 'Work orders in For Clearance or For Appointment Booking.'
    },
    {
        key: 'scheduled',
        developerKey: 'SCHEDULED',
        revenueKey: 'scheduledRevenue',
        countKey: 'scheduledCount',
        title: 'Scheduled Work',
        icon: 'utility:clock',
        hint: 'Work orders with at least one Scheduled or In Progress service appointment.'
    },
    {
        key: 'scheduledToday',
        developerKey: 'SCHEDULED_TODAY',
        revenueKey: 'scheduledTodayRevenue',
        countKey: 'scheduledTodayCount',
        title: 'Scheduled for Today',
        icon: 'utility:sync',
        hint: 'Service appointments scheduled or in progress today.'
    },
    {
        key: 'completedToday',
        developerKey: 'COMPLETED_TODAY',
        revenueKey: 'completedTodayRevenue',
        countKey: 'completedTodayCount',
        title: 'Completed Today',
        icon: 'utility:check',
        hint: 'Service appointments completed today.'
    }
];

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
        label: 'Owner',
        fieldName: 'ownerName',
        type: 'text',
        sortable: true
    }
];

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
                `Skipping unsupported Orders column config: ${configColumn?.developerKey || configColumn?.fieldApiName || 'unknown'}`
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
    for (const key of BUCKET_KEYS) {
        next[key] = { sortedBy: DEFAULT_SORT_FIELD, sortDirection: 'asc' };
    }
    return next;
}

function cloneRuntimeData(value) {
    return value ? JSON.parse(JSON.stringify(value)) : value;
}

function buildRuntimeCacheKey(dateFilter) {
    return JSON.stringify(dateFilter || { filterKey: 'Today' });
}

export default class BillingControlCenterOrders extends LightningElement {
    _dateFilter;
    _dateFilterSignature = '';
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
        this.loadOrdersConfig();
        this.loadData();
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

    get externalDateFilterKey() {
        return this.dateFilter?.filterKey || 'Today';
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

    get kpiTiles() {
        if (!this.ordersConfigLoaded) {
            return KPI_CONFIG.map(tile => this.buildKpiTile(tile, undefined));
        }

        if (!this.ordersDatasetIsActive) {
            return [];
        }

        const tiles = [];
        for (const configRecord of this.ordersTabConfig?.kpis || []) {
            const normalizedKey = normalizeConfigKey(configRecord?.developerKey);
            const definition = KPI_CONFIG.find(tile => normalizeConfigKey(tile.developerKey) === normalizedKey);
            if (!definition) {
                console.warn(`Skipping unsupported Orders KPI config: ${configRecord?.developerKey || 'unknown'}`);
                continue;
            }
            tiles.push(this.buildKpiTile(definition, configRecord));
        }
        return tiles;
    }

    get accordionSections() {
        const q = this.searchKey.trim().toLowerCase();
        const sectionsByKey = new Map(
            (this.sections || []).map(section => [normalizeConfigKey(section.bucketKey), section])
        );

        if (!this.ordersConfigLoaded) {
            return (this.sections || []).map((section, index) =>
                this.buildAccordionSection(section, section.sectionLabel, q, 1000 + index)
            );
        }

        if (!this.ordersDatasetIsActive) {
            return [];
        }

        const configuredSections = [];
        for (const configRecord of this.ordersTabConfig?.sections || []) {
            const developerKey = normalizeConfigKey(configRecord?.developerKey);
            if (!BUCKET_KEYS.includes(developerKey)) {
                console.warn(`Skipping unsupported Orders section config: ${configRecord?.developerKey || 'unknown'}`);
                continue;
            }
            const runtimeSection = sectionsByKey.get(developerKey) || {
                bucketKey: developerKey,
                sectionLabel: configRecord?.label || developerKey,
                rows: []
            };
            configuredSections.push(
                this.buildAccordionSection(
                    runtimeSection,
                    configRecord?.label || runtimeSection.sectionLabel,
                    q,
                    Number(configRecord?.displayOrder || 0)
                )
            );
        }

        return configuredSections;
    }

    get totalWorkOrderRows() {
        return this.accordionSections.reduce((sum, section) => sum + section.filteredRows.length, 0);
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
                    .some(value => String(value).toLowerCase().includes(searchKey))
            );
        }

        const bucketSort = this.sortState[section.bucketKey] || {
            sortedBy: DEFAULT_SORT_FIELD,
            sortDirection: 'asc'
        };
        rows = sortWorkOrderRows(rows, bucketSort.sortedBy, bucketSort.sortDirection);

        return {
            bucketKey: section.bucketKey,
            sectionLabel: label,
            titleWithCount: `${label} (${rows.length})`,
            filteredRows: rows,
            isEmpty: rows.length === 0,
            sortedBy: bucketSort.sortedBy,
            sortDirection: bucketSort.sortDirection,
            sectionOrder
        };
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
                dateFilter: this.dateFilter
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
                    'Orders config includes IN_PROGRESS, but the current runtime still renders SCHEDULED_TODAY and COMPLETED_TODAY buckets. Using default labels for unmatched buckets.'
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