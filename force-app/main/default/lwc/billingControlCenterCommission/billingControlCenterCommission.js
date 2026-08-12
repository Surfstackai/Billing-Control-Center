import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getReceivablesRuntimeData from '@salesforce/apex/BillingControl_DataProvider.getReceivablesRuntimeData';
import updateCommissionPaid from '@salesforce/apex/BillingControl_Invoicing.updateCommissionPaid';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const KPI_CONFIG = [
    {
        key: 'revenueUnderCollection',
        developerKey: 'ACCOUNTS_RECEIVABLE',
        countKey: 'revenueUnderCollectionCount',
        title: 'Accounts Receivable (A/R)',
        icon: 'utility:moneybag',
        hint: 'Opportunity Amount where Billing Status = Billed (Outstanding Receivable)'
    },
    {
        key: 'commissionEarned',
        developerKey: 'COMMISSION_ACCRUED',
        countKey: 'commissionEarnedCount',
        title: 'Commission Accrued',
        icon: 'utility:approval',
        hint: 'Commission Amount on billed opportunities awaiting collection'
    },
    {
        key: 'commissionPayable',
        developerKey: 'COMMISSION_PAYABLE',
        countKey: 'commissionPayableCount',
        title: 'Commission Payable',
        icon: 'utility:currency',
        hint: 'Commission Amount on paid opportunities with unpaid balance'
    }
];

const CATEGORY_KEYS = {
    REVENUE_UNDER_COLLECTION: 'REVENUE_UNDER_COLLECTION',
    COMMISSION_EARNED: 'COMMISSION_EARNED',
    COMMISSION_PAYABLE: 'COMMISSION_PAYABLE'
};

const DEFAULT_HERO_TITLE = 'Receivables';
const DEFAULT_HERO_SUBTITLE = 'Track open invoices, posted receipts, and commission payouts.';
const DEFAULT_TABLE_TITLE = 'Outstanding Opportunities and Payment Status';
const DEFAULT_REFRESH_LABEL = 'Refresh';
const DEFAULT_POST_RECEIPT_LABEL = 'Post Receipt';
const DEFAULT_PAY_COMMISSION_LABEL = 'Pay Commission';
const RECEIVABLES_DATASET_KEYS = {
    INVOICES: 'RECEIVABLES_INVOICES',
    COMMISSIONS: 'RECEIVABLES_COMMISSIONS'
};
const receivablesRuntimeCache = new Map();
const RECEIVABLES_SECTION_KEY_BY_CATEGORY = {
    [CATEGORY_KEYS.REVENUE_UNDER_COLLECTION]: 'INVOICES',
    [CATEGORY_KEYS.COMMISSION_EARNED]: 'COMMISSIONS',
    [CATEGORY_KEYS.COMMISSION_PAYABLE]: 'COMMISSIONS'
};
const RECEIVABLES_KPI_DEFINITIONS = {
    ACCOUNTS_RECEIVABLE: KPI_CONFIG[0],
    OUTSTANDING_RECEIVABLES: KPI_CONFIG[0],
    COMMISSION_ACCRUED: KPI_CONFIG[1],
    OUTSTANDING_COMMISSION: KPI_CONFIG[1],
    COMMISSION_PAYABLE: KPI_CONFIG[2]
};

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

function cloneRuntimeData(value) {
    return value ? JSON.parse(JSON.stringify(value)) : value;
}

function buildRuntimeCacheKey(dateFilter) {
    return JSON.stringify(dateFilter || null);
}

export default class BillingControlCenterCommission extends NavigationMixin(LightningElement) {
    _dateFilter;
    _dateFilterSignature = '';
    _isConnected = false;

    @api useExternalToolbar = false;

    metrics = {};
    commissionSections = [];
    selectedRows = [];
    expandedRows = [];
    isMetricsLoading = true;
    isDataLoading = true;
    isRefreshing = false;
    isActionLoading = false;
    isPostReceiptModalOpen = false;
    selectedOpportunityForReceipt = null;
    errorMessage;
    providerWarnings = [];
    receivablesTabConfig;
    receivablesConfigLoaded = false;
    receivablesDatasetsByKey = {};
    receivablesKpisByKey = {};
    receivablesSectionsByKey = {};
    receivablesActionsByKey = {};

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
        this.loadReceivablesConfig();
        this.loadData();
    }

    get isLoading() {
        return this.isMetricsLoading || this.isDataLoading || this.isRefreshing || this.isActionLoading;
    }

    get showDiagnostics() {
        return hasBillingControlCenterAdminAccess && this.providerWarnings.length > 0;
    }

    get kpiTiles() {
        if (!this.receivablesConfigLoaded) {
            return KPI_CONFIG.map(tile => this.buildKpiTile(tile));
        }

        const configuredKpis = this.receivablesTabConfig?.kpis || [];
        if (configuredKpis.length === 0) {
            return [];
        }

        const tiles = [];
        configuredKpis.forEach(configRecord => {
            const developerKey = normalizeConfigKey(configRecord?.developerKey);
            const definition = RECEIVABLES_KPI_DEFINITIONS[developerKey];

            if (!definition) {
                console.warn(
                    `Skipping unsupported Receivables KPI config: ${configRecord?.developerKey || 'unknown'}`
                );
                return;
            }

            if (definition.datasetKey && !this.receivablesDatasetsByKey[definition.datasetKey]) {
                return;
            }

            tiles.push(this.buildKpiTile(definition, configRecord));
        });

        return tiles;
    }

    get heroTitle() {
        return this.receivablesTabConfig?.label || DEFAULT_HERO_TITLE;
    }

    get heroSubtitle() {
        return DEFAULT_HERO_SUBTITLE;
    }

    get tableTitle() {
        const invoicesLabel = this.receivablesSectionsByKey.INVOICES?.label;
        const commissionsLabel = this.receivablesSectionsByKey.COMMISSIONS?.label;
        if (invoicesLabel && commissionsLabel) {
            return `${invoicesLabel} and ${commissionsLabel}`;
        }
        if (invoicesLabel) {
            return invoicesLabel;
        }
        if (commissionsLabel) {
            return commissionsLabel;
        }
        return DEFAULT_TABLE_TITLE;
    }

    get refreshLabel() {
        return this.receivablesActionsByKey.REFRESH?.label || DEFAULT_REFRESH_LABEL;
    }

    get heroActions() {
        if (this.useExternalToolbar) {
            return [];
        }

        if (this.receivablesConfigLoaded && !this.receivablesActionsByKey.REFRESH) {
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

    get postReceiptLabel() {
        return this.receivablesActionsByKey.POST_RECEIPT?.label || DEFAULT_POST_RECEIPT_LABEL;
    }

    get payCommissionLabel() {
        return this.receivablesActionsByKey.PAY_COMMISSION?.label || DEFAULT_PAY_COMMISSION_LABEL;
    }

    get tableActions() {
        if (!this.showTableShell) {
            return [];
        }

        if (!this.receivablesConfigLoaded) {
            return this.buildDefaultTableActions();
        }

        const actions = [];
        if (this.receivablesActionsByKey.POST_RECEIPT) {
            actions.push({
                key: 'postReceipt',
                label: this.postReceiptLabel,
                variant: 'brand',
                disabled: this.isPostReceiptDisabled,
                title: this.postReceiptLabel
            });
        }
        if (this.receivablesActionsByKey.PAY_COMMISSION) {
            actions.push({
                key: 'payCommission',
                label: this.payCommissionLabel,
                variant: 'neutral',
                disabled: this.isPayCommissionDisabled,
                title: this.payCommissionLabel
            });
        }
        return actions;
    }

    get showTableShell() {
        if (!this.receivablesConfigLoaded) {
            return true;
        }
        return this.getRenderableCommissionSections().length > 0;
    }

    get accordionSections() {
        const expandedKeys = new Set(this.expandedRows);
        const selectedKeys = new Set(this.selectedRows);

        return this.getRenderableCommissionSections().map(section => ({
            ...section,
            titleWithCount: `${section.categoryLabel} (${section.opportunityCount || 0})`,
            isEmpty: (section.opportunityCount || 0) === 0,
            salespersonCount: (section.salespeople || []).length,
            sectionTotalAmount: section.totalAmount || 0,
            sectionTotalCommission: section.totalCommission || 0,
            sectionTotalPaid: section.totalPaid || 0,
            salespeople: section.salespeople.map(salesperson => ({
                ...salesperson,
                isExpanded: expandedKeys.has(salesperson.key),
                isSelected: selectedKeys.has(salesperson.key),
                expandIcon: expandedKeys.has(salesperson.key) ? 'utility:chevrondown' : 'utility:chevronright',
                expandAltText: expandedKeys.has(salesperson.key)
                    ? 'Collapse opportunities'
                    : 'Expand opportunities',
                opportunities: salesperson.opportunities.map(opportunity => ({
                    ...opportunity,
                    isSelected: selectedKeys.has(opportunity.key) || selectedKeys.has(salesperson.key)
                }))
            }))
        }));
    }

    get selectedOpportunities() {
        const selectedKeys = new Set(this.selectedRows);
        const opportunitiesById = new Map();

        this.getRenderableCommissionSections().forEach(section => {
            section.salespeople.forEach(salesperson => {
                const parentSelected = selectedKeys.has(salesperson.key);
                salesperson.opportunities.forEach(opportunity => {
                    if (!parentSelected && !selectedKeys.has(opportunity.key)) {
                        return;
                    }

                    const opportunityKey = opportunity.opportunityId
                        ? String(opportunity.opportunityId)
                        : opportunity.key;
                    if (!opportunitiesById.has(opportunityKey)) {
                        opportunitiesById.set(opportunityKey, {
                            ...opportunity,
                            ownerName: salesperson.salespersonName,
                            categoryKey: section.categoryKey
                        });
                    }
                });
            });
        });

        return Array.from(opportunitiesById.values());
    }

    get selectedInvoiceOpportunities() {
        return this.selectedOpportunities
            .filter(
                opportunity =>
                    opportunity.categoryKey === CATEGORY_KEYS.REVENUE_UNDER_COLLECTION &&
                    opportunity.billingStatus !== 'Paid'
            )
            .map(opportunity => ({
                opportunityId: opportunity.opportunityId,
                opportunityName: opportunity.opportunityName || opportunity.name,
                accountName: opportunity.accountName,
                amount: opportunity.amount || 0,
                amountPaid: opportunity.amountPaid || 0,
                balanceDue: opportunity.balanceDue || 0,
                ownerName: opportunity.ownerName
            }));
    }

    get selectedCommissionIds() {
        const selectedKeys = new Set(this.selectedRows);
        const commissionIds = new Set();

        this.getRenderableCommissionSections().forEach(section => {
            if (section.categoryKey !== CATEGORY_KEYS.COMMISSION_PAYABLE) {
                return;
            }

            section.salespeople.forEach(salesperson => {
                const parentSelected = selectedKeys.has(salesperson.key);
                salesperson.opportunities.forEach(opportunity => {
                    if (!opportunity.commissionId) {
                        return;
                    }
                    if (parentSelected || selectedKeys.has(opportunity.key)) {
                        commissionIds.add(opportunity.commissionId);
                    }
                });
            });
        });

        return Array.from(commissionIds);
    }

    get selectedCount() {
        return this.selectedOpportunities.length;
    }

    get opportunityCount() {
        return this.getRenderableCommissionSections().reduce(
            (total, section) => total + (section.opportunityCount || 0),
            0
        );
    }

    get salespersonCount() {
        return this.getRenderableCommissionSections().reduce(
            (total, section) => total + (section.salespeople ? section.salespeople.length : 0),
            0
        );
    }

    get isPayCommissionDisabled() {
        return this.selectedCommissionIds.length === 0 || this.isActionLoading;
    }

    get isPostReceiptDisabled() {
        return this.selectedInvoiceOpportunities.length !== 1 || this.isActionLoading;
    }

    handleParentSelection(event) {
        const rowKey = event.target.dataset.key;
        if (!rowKey) {
            return;
        }

        const salesperson = this.findSalespersonByKey(rowKey);
        const childRows = salesperson ? salesperson.opportunities : [];
        const nextSelection = new Set(this.selectedRows);

        if (event.target.checked) {
            nextSelection.add(rowKey);
            childRows.forEach(opportunity => nextSelection.add(opportunity.key));
        } else {
            nextSelection.delete(rowKey);
            childRows.forEach(opportunity => nextSelection.delete(opportunity.key));
        }

        this.setSelectedRows(Array.from(nextSelection));
    }

    handleChildSelection(event) {
        const rowKey = event.target.dataset.key;
        if (!rowKey) {
            return;
        }

        const nextSelection = new Set(this.selectedRows);
        if (event.target.checked) {
            nextSelection.add(rowKey);
        } else {
            nextSelection.delete(rowKey);
        }

        this.setSelectedRows(Array.from(nextSelection));
    }

    handleToggleRow(event) {
        const rowKey = event.currentTarget.dataset.key;
        if (!rowKey) {
            return;
        }

        const nextExpanded = new Set(this.expandedRows);
        if (nextExpanded.has(rowKey)) {
            nextExpanded.delete(rowKey);
        } else {
            nextExpanded.add(rowKey);
        }

        this.setExpandedRows(Array.from(nextExpanded));
    }

    async handleOpenOpportunity(event) {
        const opportunityId = event.currentTarget.dataset.id;
        if (!opportunityId) {
            return;
        }

        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: opportunityId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });

        window.open(url, '_blank');
    }

    async handleRefresh() {
        if (this.isRefreshing) {
            return;
        }

        this.errorMessage = undefined;
        this.isRefreshing = true;

        try {
            await this.loadData(true);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRefreshing = false;
        }
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

    async handlePayCommission() {
        if (this.isPayCommissionDisabled) {
            return;
        }

        this.isActionLoading = true;
        this.errorMessage = undefined;

        try {
            await updateCommissionPaid({ commissionIds: this.selectedCommissionIds });
            this.setSelectedRows([]);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Commission Updated',
                    message: 'Selected commissions were marked as fully paid.',
                    variant: 'success'
                })
            );

            this.isRefreshing = true;
            await this.loadData(true);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRefreshing = false;
            this.isActionLoading = false;
        }
    }

    handleTableActionClick(event) {
        if (event.detail?.key === 'postReceipt') {
            this.handleOpenPostReceipt();
        } else if (event.detail?.key === 'payCommission') {
            this.handlePayCommission();
        }
    }

    handleOpenPostReceipt() {
        if (this.isPostReceiptDisabled) {
            return;
        }

        const selectedOpportunity = this.selectedInvoiceOpportunities[0];
        this.selectedOpportunityForReceipt = selectedOpportunity
            ? {
                id: selectedOpportunity.opportunityId,
                name: selectedOpportunity.opportunityName,
                accountName: selectedOpportunity.accountName,
                amount: selectedOpportunity.amount,
                amountPaid: selectedOpportunity.amountPaid,
                balanceDue: selectedOpportunity.balanceDue,
                ownerName: selectedOpportunity.ownerName
            }
            : null;
        this.isPostReceiptModalOpen = this.selectedOpportunityForReceipt !== null;
    }

    handlePostReceiptClose() {
        this.isPostReceiptModalOpen = false;
        this.selectedOpportunityForReceipt = null;
    }

    async handlePostReceiptRefresh() {
        this.isPostReceiptModalOpen = false;
        this.selectedOpportunityForReceipt = null;
        this.setSelectedRows([]);
        this.isRefreshing = true;
        try {
            await this.loadData(true);
        } finally {
            this.isRefreshing = false;
        }
    }

    buildDefaultTableActions() {
        return [
            {
                key: 'postReceipt',
                label: this.postReceiptLabel,
                variant: 'brand',
                disabled: this.isPostReceiptDisabled,
                title: this.postReceiptLabel
            },
            {
                key: 'payCommission',
                label: this.payCommissionLabel,
                variant: 'neutral',
                disabled: this.isPayCommissionDisabled,
                title: this.payCommissionLabel
            }
        ];
    }

    buildKpiTile(definition, configRecord) {
        return {
            ...definition,
            title: configRecord?.label || definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: CURRENCY_FORMATTER.format(this.metrics[definition.key] || 0),
            countText: this.buildKpiCountText(definition.countKey)
        };
    }

    getRenderableCommissionSections() {
        if (!this.receivablesConfigLoaded) {
            return this.commissionSections;
        }

        const configuredSections = this.receivablesTabConfig?.sections || [];
        if (configuredSections.length === 0) {
            return [];
        }

        const supportedSectionKeys = new Set();
        configuredSections.forEach(configRecord => {
            const developerKey = normalizeConfigKey(configRecord?.developerKey);
            if (developerKey === 'INVOICES' || developerKey === 'COMMISSIONS') {
                supportedSectionKeys.add(developerKey);
                return;
            }

            console.warn(
                `Skipping unsupported Receivables section config: ${configRecord?.developerKey || 'unknown'}`
            );
        });

        if (supportedSectionKeys.size === 0) {
            return this.commissionSections;
        }

        return this.commissionSections
            .filter(section => {
                const sectionKey = RECEIVABLES_SECTION_KEY_BY_CATEGORY[section.categoryKey];
                if (!sectionKey || !supportedSectionKeys.has(sectionKey)) {
                    return false;
                }

                const datasetKey = RECEIVABLES_DATASET_KEYS[sectionKey];
                return Boolean(this.receivablesDatasetsByKey[datasetKey]);
            })
            .map(section => ({
                ...section,
                categoryLabel:
                    this.receivablesSectionsByKey[RECEIVABLES_SECTION_KEY_BY_CATEGORY[section.categoryKey]]?.label ||
                    section.categoryLabel
            }));
    }

    normalizeSections(data) {
        return (data || []).map((section, sectionIndex) => {
            const categoryKey = section.categoryKey || `CATEGORY_${sectionIndex}`;
            const salespeople = (section.salespersonGroups || []).map((salesperson, salespersonIndex) => {
                const salespersonKey =
                    `${categoryKey}-salesperson-${salesperson.salespersonId || 'unassigned'}-${salespersonIndex}`;
                const opportunities = (salesperson.opportunities || []).map((opportunity, opportunityIndex) => {
                    const commissionAmount = opportunity.commissionAmount || 0;
                    const commissionPaid = opportunity.commissionPaid || 0;
                    return {
                        ...opportunity,
                        key:
                            `${categoryKey}-opportunity-${opportunity.opportunityId || 'missing'}-` +
                            `${opportunity.commissionId || opportunityIndex}`,
                        opportunityName: opportunity.opportunityName || opportunity.name,
                        commissionAmount,
                        commissionPaid,
                        outstandingCommission: commissionAmount - commissionPaid
                    };
                });

                const totalCommission = salesperson.totalCommission || 0;
                const totalPaid = salesperson.totalPaid || 0;

                return {
                    ...salesperson,
                    key: salespersonKey,
                    categoryKey,
                    salespersonName: salesperson.salespersonName || 'Unassigned',
                    totalAmount: salesperson.totalAmount || 0,
                    totalCommission,
                    totalPaid,
                    outstandingCommission: totalCommission - totalPaid,
                    opportunityCount: opportunities.length,
                    opportunities
                };
            });

            return {
                ...section,
                categoryKey,
                categoryLabel: section.categoryLabel || `Category ${sectionIndex + 1}`,
                opportunityCount:
                    section.opportunityCount != null
                        ? section.opportunityCount
                        : salespeople.reduce((count, salesperson) => count + salesperson.opportunities.length, 0),
                totalAmount: section.totalAmount || 0,
                totalCommission: section.totalCommission || 0,
                totalPaid: section.totalPaid || 0,
                salespeople
            };
        });
    }

    findSalespersonByKey(rowKey) {
        for (const section of this.getRenderableCommissionSections()) {
            for (const salesperson of section.salespeople || []) {
                if (salesperson.key === rowKey) {
                    return salesperson;
                }
            }
        }
        return null;
    }

    reconcileActiveState() {
        const validParentKeys = new Set();
        const validKeys = new Set();

        this.getRenderableCommissionSections().forEach(section => {
            (section.salespeople || []).forEach(salesperson => {
                validParentKeys.add(salesperson.key);
                validKeys.add(salesperson.key);
                (salesperson.opportunities || []).forEach(opportunity => validKeys.add(opportunity.key));
            });
        });

        this.setExpandedRows(this.expandedRows.filter(key => validParentKeys.has(key)));
        this.setSelectedRows(this.selectedRows.filter(key => validKeys.has(key)));
    }

    setSelectedRows(nextRows) {
        this.selectedRows = nextRows;
    }

    setExpandedRows(nextRows) {
        this.expandedRows = nextRows;
    }

    async loadData(forceRefresh = false) {
        this.isMetricsLoading = true;
        this.isDataLoading = true;
        this.errorMessage = undefined;
        const cacheKey = buildRuntimeCacheKey(this.dateFilter);

        try {
            if (forceRefresh) {
                receivablesRuntimeCache.delete(cacheKey);
            } else if (receivablesRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(receivablesRuntimeCache.get(cacheKey)));
                return;
            }

            const refreshToken = forceRefresh ? Date.now() : null;
            const data = await getReceivablesRuntimeData({
                refreshToken,
                dateFilter: this.dateFilter || null
            });
            receivablesRuntimeCache.set(cacheKey, cloneRuntimeData(data));
            this.applyRuntimeData(data);
        } catch (error) {
            this.providerWarnings = [];
            this.metrics = {};
            this.commissionSections = [];
            this.errorMessage = this.reduceError(error);
            this.setSelectedRows([]);
            this.setExpandedRows([]);
        } finally {
            this.isMetricsLoading = false;
            this.isDataLoading = false;
        }
    }

    applyRuntimeData(data) {
        this.providerWarnings = data?.warnings || [];
        (data?.warnings || []).forEach(warning => console.warn(warning));
        this.metrics = data?.metrics || {};
        this.commissionSections = this.normalizeSections(data?.sections || []);
        this.reconcileActiveState();
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

    buildKpiCountText(countKey) {
        const countValue = Number(this.metrics[countKey] || 0);
        const normalizedCount = Number.isFinite(countValue) ? countValue : 0;
        const noun = countKey === 'commissionEarnedCount' || countKey === 'commissionPayableCount'
            ? 'Commission'
            : 'Opportunity';
        return `${normalizedCount} ${noun}${normalizedCount === 1 ? '' : 's'}`;
    }

    async loadReceivablesConfig() {
        try {
            const config = await getTabConfig({ developerKey: 'RECEIVABLES' });
            if (!config) {
                console.warn('Billing Control Center Receivables config not found. Using default presentation.');
                return;
            }

            this.receivablesTabConfig = config;
            this.receivablesConfigLoaded = true;
            this.receivablesDatasetsByKey = buildConfigMap(config.datasets);
            this.receivablesKpisByKey = buildConfigMap(config.kpis);
            this.receivablesSectionsByKey = buildConfigMap(config.sections);
            this.receivablesActionsByKey = buildConfigMap(config.actions);
            this.reconcileActiveState();
        } catch (error) {
            console.warn(
                'Failed to load Billing Control Center Receivables config. Using default presentation.',
                error
            );
            this.receivablesTabConfig = undefined;
            this.receivablesConfigLoaded = false;
            this.receivablesDatasetsByKey = {};
            this.receivablesKpisByKey = {};
            this.receivablesSectionsByKey = {};
            this.receivablesActionsByKey = {};
        }
    }
}