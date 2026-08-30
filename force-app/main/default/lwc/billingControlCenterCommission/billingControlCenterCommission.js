import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import getTabRuntime from '@salesforce/apex/BillingControl_ReceivablesWorklist.getTabRuntime';
import setInvoiceAmount from '@salesforce/apex/BillingControl_ReceivablesWorklist.setInvoiceAmount';
import {
    MIN_COLUMN_WIDTH,
    RECEIVABLES_COLUMN_WIDTHS_KEY,
    loadColumnWidths,
    saveColumnWidths
} from 'c/billingControlCenterColumnResize';
import { compareAccountGroup, decorateAccountGroups } from 'c/billingControlCenterAccountGroup';
import { resolveDateRange } from 'c/billingControlCenterDateFilter';

const DEFAULT_RECEIVABLE_COLUMN_WIDTHS = {
    select: 64,
    invoice: 118,
    salesperson: 156,
    account: 340,
    type: 110,
    invoiceDate: 120,
    dueDate: 120,
    days: 76,
    amount: 128,
    paid: 120,
    balance: 128,
    status: 96
};

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const KPI_CONFIG = [
    {
        key: 'outstandingAr',
        developerKey: 'OUTSTANDING_AR',
        countKey: 'outstandingArCount',
        amountKey: 'outstandingAr',
        title: 'Outstanding AR',
        icon: 'utility:moneybag',
        hint: 'Open invoice balances, regardless of invoice date.'
    },
    {
        key: 'overdue',
        developerKey: 'OVERDUE',
        countKey: 'overdueCount',
        amountKey: 'overdue',
        title: 'Overdue',
        icon: 'utility:clock',
        hint: 'Open invoices past due date.'
    },
    {
        key: 'partiallyPaid',
        developerKey: 'PARTIALLY_PAID',
        countKey: 'partiallyPaidCount',
        amountKey: 'partiallyPaid',
        title: 'Partially Paid',
        icon: 'utility:pay_by_check',
        hint: 'Invoices with a remaining balance after a receipt.'
    },
    {
        key: 'needsAmount',
        developerKey: 'NEEDS_AMOUNT',
        countKey: 'needsAmountCount',
        title: 'Needs Amount',
        icon: 'utility:warning',
        hint: 'Invoice headers waiting for an amount before they can collect.'
    },
    {
        key: 'depositsOutstanding',
        developerKey: 'DEPOSITS_OUTSTANDING',
        countKey: 'depositsOutstandingCount',
        amountKey: 'depositsOutstanding',
        title: 'Deposits Outstanding',
        icon: 'utility:money',
        hint: 'Open deposit invoices.'
    },
    {
        key: 'allReceivables',
        developerKey: 'ALL_RECEIVABLES',
        countKey: 'allReceivablesCount',
        amountKey: 'allReceivables',
        title: 'All Receivables',
        icon: 'utility:list',
        hint: 'Every invoice in the worklist. Matches the rows in both views when this filter is selected.'
    }
];

const CATEGORY_KEYS = {
    OUTSTANDING_AR: 'OUTSTANDING_AR',
    OVERDUE: 'OVERDUE',
    PARTIALLY_PAID: 'PARTIALLY_PAID',
    NEEDS_AMOUNT: 'NEEDS_AMOUNT',
    DEPOSITS_OUTSTANDING: 'DEPOSITS_OUTSTANDING',
    COMMISSION_EARNED: 'COMMISSION_EARNED',
    COMMISSION_PAYABLE: 'COMMISSION_PAYABLE',
    ALL_RECEIVABLES: 'ALL_RECEIVABLES'
};

const VIEW_SALESPERSON = 'salesperson';
const VIEW_INVOICE = 'invoice';
const DEFAULT_HERO_TITLE = 'Receivables';
const DEFAULT_HERO_SUBTITLE =
    'Outstanding invoices to collect. Paid-in-full jobs move to Accrued commissions. This tab has no commission payouts.';
const DEFAULT_TABLE_TITLE = 'Outstanding AR';
const DEFAULT_REFRESH_LABEL = 'Refresh';
const DEFAULT_POST_RECEIPT_LABEL = 'Post Receipt';
const DEFAULT_PAY_COMMISSION_LABEL = 'Pay Commission';
const STATUS_CHIP_LABELS = {
    OUTSTANDING_AR: 'Outstanding',
    OVERDUE: 'Overdue',
    PARTIALLY_PAID: 'Partially Paid',
    NEEDS_AMOUNT: 'Needs Amount',
    DEPOSITS_OUTSTANDING: 'Deposits',
    ALL_RECEIVABLES: 'All Receivables'
};
const DEFAULT_DATE_FILTER = resolveDateRange('This Month');
const KPI_CATEGORY_BY_KEY = {
    outstandingAr: CATEGORY_KEYS.OUTSTANDING_AR,
    OUTSTANDING_AR: CATEGORY_KEYS.OUTSTANDING_AR,
    ACCOUNTS_RECEIVABLE: CATEGORY_KEYS.OUTSTANDING_AR,
    OUTSTANDING_RECEIVABLES: CATEGORY_KEYS.OUTSTANDING_AR,
    overdue: CATEGORY_KEYS.OVERDUE,
    OVERDUE: CATEGORY_KEYS.OVERDUE,
    partiallyPaid: CATEGORY_KEYS.PARTIALLY_PAID,
    PARTIALLY_PAID: CATEGORY_KEYS.PARTIALLY_PAID,
    needsAmount: CATEGORY_KEYS.NEEDS_AMOUNT,
    NEEDS_AMOUNT: CATEGORY_KEYS.NEEDS_AMOUNT,
    depositsOutstanding: CATEGORY_KEYS.DEPOSITS_OUTSTANDING,
    DEPOSITS_OUTSTANDING: CATEGORY_KEYS.DEPOSITS_OUTSTANDING,
    allReceivables: CATEGORY_KEYS.ALL_RECEIVABLES,
    ALL_RECEIVABLES: CATEGORY_KEYS.ALL_RECEIVABLES
};
const SECTION_DISPLAY_ORDER = [
    CATEGORY_KEYS.OUTSTANDING_AR,
    CATEGORY_KEYS.OVERDUE,
    CATEGORY_KEYS.PARTIALLY_PAID,
    CATEGORY_KEYS.NEEDS_AMOUNT,
    CATEGORY_KEYS.DEPOSITS_OUTSTANDING,
    CATEGORY_KEYS.ALL_RECEIVABLES
];
const receivablesRuntimeCache = new Map();

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

function buildRuntimeCacheKey(dateFilter, opportunityOwnerId) {
    return JSON.stringify({
        dateFilter: dateFilter || null,
        opportunityOwnerId: opportunityOwnerId || null
    });
}

export default class BillingControlCenterCommission extends NavigationMixin(LightningElement) {
    _dateFilter = { ...DEFAULT_DATE_FILTER };
    _dateFilterSignature = JSON.stringify(DEFAULT_DATE_FILTER);
    _isConnected = false;
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
    worklistInvoices = [];
    invoiceSections = [];
    commissionSections = [];
    selectedRows = [];
    expandedRows = [];
    searchKey = '';
    viewMode = VIEW_SALESPERSON;
    statusFilter = CATEGORY_KEYS.OUTSTANDING_AR;
    selectedKpiKey = 'outstandingAr';
    activeAccordionSections = [];
    isMetricsLoading = true;
    isDataLoading = true;
    isRefreshing = false;
    isActionLoading = false;
    isPostReceiptModalOpen = false;
    selectedOpportunityForReceipt = null;
    isSetAmountModalOpen = false;
    selectedInvoiceForAmount = null;
    setAmountValue;
    selectedLedgerId;
    showLedgerModal = false;
    errorMessage;
    providerWarnings = [];
    receivablesTabConfig;
    receivablesConfigLoaded = false;
    receivablesDatasetsByKey = {};
    receivablesKpisByKey = {};
    receivablesSectionsByKey = {};
    receivablesActionsByKey = {};
    columnWidths = {};
    _resizeState;
    _boundResizeMove;
    _boundResizeEnd;

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
        this.columnWidths = loadColumnWidths(RECEIVABLES_COLUMN_WIDTHS_KEY);
        this.loadReceivablesConfig();
        this.loadData();
    }

    disconnectedCallback() {
        this.teardownColumnResize();
    }

    get receivableColumnStyles() {
        const styles = {};
        Object.keys(DEFAULT_RECEIVABLE_COLUMN_WIDTHS).forEach(key => {
            const width = Number(this.columnWidths[key]) || DEFAULT_RECEIVABLE_COLUMN_WIDTHS[key];
            styles[key] = `width:${width}px;min-width:${width}px;`;
        });
        return styles;
    }

    get isLoading() {
        return this.isMetricsLoading || this.isDataLoading || this.isRefreshing || this.isActionLoading;
    }

    get heroClass() {
        return this.useExternalToolbar ? 'hero hero_toolbar-only' : 'hero';
    }

    get showHeroIntro() {
        return !this.useExternalToolbar;
    }

    get showFullPageSpinner() {
        return (this.isMetricsLoading || this.isDataLoading) && !(this.invoiceSections || []).length;
    }

    get toolbarRefreshLabel() {
        return this.isRefreshing ? 'Refreshing…' : this.refreshLabel;
    }

    get activeSectionNames() {
        return this.activeAccordionSections;
    }

    get searchSummary() {
        const trimmed = (this.searchKey || '').trim();
        if (trimmed) {
            return `Filtered by "${trimmed}"`;
        }
        return 'All matching invoices';
    }

    get isSalespersonView() {
        return this.viewMode !== VIEW_INVOICE;
    }

    get isInvoiceView() {
        return this.viewMode === VIEW_INVOICE;
    }

    get salespersonViewButtonClass() {
        return `view-by__option${this.isSalespersonView ? ' view-by__option_selected' : ''}`;
    }

    get invoiceViewButtonClass() {
        return `view-by__option${this.isInvoiceView ? ' view-by__option_selected' : ''}`;
    }

    get viewSwitchKnobClass() {
        return `view-by__knob${this.isSalespersonView ? ' view-by__knob_left' : ' view-by__knob_right'}`;
    }

    get statusFilterLabel() {
        return STATUS_CHIP_LABELS[this.statusFilter] || 'Outstanding';
    }

    get searchQuery() {
        return (this.searchKey || '').trim().toLowerCase();
    }

    get showDiagnostics() {
        return hasBillingControlCenterAdminAccess && this.providerWarnings.length > 0;
    }

    get statusStripItems() {
        return KPI_CONFIG.map(definition => {
            const tile = this.buildKpiTile(
                definition,
                this.receivablesKpisByKey[definition.developerKey]
            );
            const isSelected = this.statusFilter === definition.developerKey;
            return {
                key: definition.key,
                developerKey: definition.developerKey,
                title:
                    definition.developerKey === CATEGORY_KEYS.DEPOSITS_OUTSTANDING
                        ? 'Deposits'
                        : definition.developerKey === CATEGORY_KEYS.ALL_RECEIVABLES
                          ? 'All'
                          : definition.title,
                metricText: tile.metricText,
                countText: tile.countText,
                className: isSelected
                    ? 'ar-summary-strip__item ar-summary-strip__item_selected'
                    : 'ar-summary-strip__item',
                ariaSelected: isSelected ? 'true' : 'false'
            };
        });
    }

    get heroTitle() {
        return this.receivablesTabConfig?.label || DEFAULT_HERO_TITLE;
    }

    get heroSubtitle() {
        return DEFAULT_HERO_SUBTITLE;
    }

    get tableTitle() {
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
                label: this.toolbarRefreshLabel,
                iconName: 'utility:refresh',
                variant: 'neutral',
                disabled: this.isLoading,
                title: this.toolbarRefreshLabel
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
        return this.buildDefaultTableActions();
    }

    get showTableShell() {
        return true;
    }

    get filteredStatusInvoices() {
        return this.invoicesForCategory(this.statusFilter).map(invoice => this.decorateInvoice(invoice));
    }

    get visibleInvoiceCount() {
        if (this.isInvoiceView) {
            return this.filteredStatusInvoices.length;
        }
        return this.salespersonGroups.reduce(
            (total, group) => total + (group.invoices || []).length,
            0
        );
    }

    get invoiceViewEmpty() {
        return this.filteredStatusInvoices.length === 0;
    }

    get salespersonGroups() {
        const outstandingIds = this.invoiceIdsForCategory(CATEGORY_KEYS.OUTSTANDING_AR);
        const overdueIds = this.invoiceIdsForCategory(CATEGORY_KEYS.OVERDUE);
        const partialIds = this.invoiceIdsForCategory(CATEGORY_KEYS.PARTIALLY_PAID);
        const expandedKeys = new Set(this.expandedRows);
        const selectedKeys = new Set(this.selectedRows);
        const byOwner = new Map();

        this.uniqueSearchInvoices.forEach(invoice => {
            const ownerKey = invoice.ownerId || 'unassigned';
            if (!byOwner.has(ownerKey)) {
                byOwner.set(ownerKey, {
                    key: 'sp-' + ownerKey,
                    ownerId: invoice.ownerId || null,
                    ownerName: invoice.ownerName || 'Unassigned',
                    invoices: []
                });
            }
            byOwner.get(ownerKey).invoices.push(invoice);
        });

        return Array.from(byOwner.values())
            .map(group => {
                const ownerMatch = invoice =>
                    (invoice.ownerId || 'unassigned') === (group.ownerId || 'unassigned');
                const all = group.invoices;
                const decorated = this.invoicesForCategory(this.statusFilter)
                    .filter(ownerMatch)
                    .map(invoice => this.decorateInvoice(invoice));
                const childKeys = decorated.map(invoice => invoice.key);
                const isExpanded = expandedKeys.has(group.key);
                const isSelected =
                    childKeys.length > 0 && childKeys.every(key => selectedKeys.has(key));
                return {
                    ...group,
                    outstandingAr: this.sumBalances(all, outstandingIds),
                    overdue: this.sumBalances(all, overdueIds),
                    invoiceCount: decorated.length,
                    partiallyPaid: this.sumBalances(all, partialIds),
                    partiallyPaidCount: all.filter(invoice => partialIds.has(invoice.invoiceId)).length,
                    isExpanded,
                    ariaExpanded: isExpanded ? 'true' : 'false',
                    isSelected,
                    selectLabel: 'Select invoices for ' + group.ownerName,
                    expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    expandAltText: isExpanded ? 'Collapse invoices' : 'Expand invoices',
                    cardClass: isExpanded
                        ? 'salesperson-card salesperson-card_expanded'
                        : 'salesperson-card',
                    tableLabel: 'Invoices for ' + group.ownerName,
                    invoices: decorated,
                    invoiceCountInStatus: decorated.length,
                    hasInvoicesInStripStatus: this.invoicesForCategory(this.statusFilter).some(
                        ownerMatch
                    ),
                    isEmpty: decorated.length === 0
                };
            })
            .sort((left, right) => (right.outstandingAr || 0) - (left.outstandingAr || 0))
            .filter(group => group.hasInvoicesInStripStatus);
    }

    get salespersonGroupsEmpty() {
        return this.salespersonGroups.length === 0;
    }

    get uniqueSearchInvoices() {
        return (this.worklistInvoices || []).filter(invoice => this.invoiceMatchesSearch(invoice));
    }

    get allCanonicalInvoices() {
        return (this.worklistInvoices || []).map(invoice => ({
            ...invoice,
            key: 'inv-' + invoice.invoiceId
        }));
    }

    get selectedInvoiceOpportunities() {
        const selectedKeys = new Set(this.selectedRows);
        return this.allCanonicalInvoices
            .filter(invoice => selectedKeys.has(invoice.key) && invoice.canPostReceipt)
            .map(invoice => ({
                id: invoice.opportunityId,
                opportunityId: invoice.opportunityId,
                invoiceId: invoice.invoiceId,
                invoiceNumber: invoice.invoiceNumber,
                name: invoice.opportunityName,
                opportunityName: invoice.opportunityName,
                accountName: invoice.accountName,
                amount: invoice.totalAmount || 0,
                amountPaid: invoice.amountPaid || 0,
                balanceDue: invoice.balanceDue || 0,
                ownerName: invoice.ownerName
            }));
    }

    get selectedCount() {
        const selectedKeys = new Set(this.selectedRows);
        return this.allCanonicalInvoices.filter(invoice => selectedKeys.has(invoice.key)).length;
    }

    get isPostReceiptDisabled() {
        return this.selectedInvoiceOpportunities.length !== 1 || this.isActionLoading;
    }

    get selectedNeedsAmountInvoices() {
        const selectedKeys = new Set(this.selectedRows);
        return this.allCanonicalInvoices.filter(
            invoice => selectedKeys.has(invoice.key) && invoice.needsAmount
        );
    }

    get isSetAmountDisabled() {
        return this.selectedNeedsAmountInvoices.length !== 1 || this.isActionLoading;
    }

    handleParentSelection(event) {
        const rowKey = event.target.dataset.key;
        if (!rowKey) {
            return;
        }

        const group = this.salespersonGroups.find(item => item.key === rowKey);
        const childKeys = (group?.invoices || []).map(invoice => invoice.key);
        const nextSelection = new Set(this.selectedRows);

        if (event.target.checked) {
            nextSelection.add(rowKey);
            childKeys.forEach(key => nextSelection.add(key));
        } else {
            nextSelection.delete(rowKey);
            childKeys.forEach(key => nextSelection.delete(key));
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

    async handleOpenAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }
        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
        window.open(url, '_blank');
    }

    async handleOpenInvoice(event) {
        const invoiceId = event.currentTarget.dataset.id;
        if (!invoiceId) {
            return;
        }
        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: invoiceId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });
        window.open(url, '_blank');
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

    handleDateFilterChange(event) {
        const detail = event.detail || {};
        this.dateFilter = resolveDateRange(
            detail.filterKey || DEFAULT_DATE_FILTER.filterKey,
            detail.startDate,
            detail.endDate
        );
        this.emitSharedFilterChange();
    }

    handleOpportunityOwnerChange(event) {
        const nextOwnerId = event.detail?.recordId || null;
        if (nextOwnerId === this.opportunityOwnerId) {
            return;
        }
        this.opportunityOwnerId = nextOwnerId;
        this.emitSharedFilterChange();
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

    handleViewChange(event) {
        const view = event.currentTarget?.dataset?.view;
        if (view === VIEW_INVOICE || view === VIEW_SALESPERSON) {
            this.viewMode = view;
        }
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
    }

    applyStatusFilter(statusKey) {
        const normalized =
            KPI_CATEGORY_BY_KEY[statusKey] ||
            KPI_CATEGORY_BY_KEY[normalizeConfigKey(statusKey)] ||
            normalizeConfigKey(statusKey);
        if (!normalized || !SECTION_DISPLAY_ORDER.includes(normalized)) {
            return;
        }
        this.statusFilter = normalized;
        const kpi = KPI_CONFIG.find(definition => definition.developerKey === normalized);
        this.selectedKpiKey = kpi?.key || normalized;
    }

    handleStatusStripClick(event) {
        this.applyStatusFilter(event.currentTarget?.dataset?.status);
    }

    handleTableActionClick(event) {
        if (event.detail?.key === 'postReceipt') {
            this.handleOpenPostReceipt();
        } else if (event.detail?.key === 'setInvoiceAmount') {
            this.handleOpenSetAmount();
        }
    }

    handleOpenPostReceipt() {
        if (this.isPostReceiptDisabled) {
            return;
        }

        const selectedInvoice = this.selectedInvoiceOpportunities[0];
        this.selectedOpportunityForReceipt = selectedInvoice
            ? {
                id: selectedInvoice.opportunityId,
                invoiceId: selectedInvoice.invoiceId,
                invoiceNumber: selectedInvoice.invoiceNumber,
                name: selectedInvoice.opportunityName,
                accountName: selectedInvoice.accountName,
                amount: selectedInvoice.amount,
                amountPaid: selectedInvoice.amountPaid,
                balanceDue: selectedInvoice.balanceDue,
                ownerName: selectedInvoice.ownerName
            }
            : null;
        this.isPostReceiptModalOpen = this.selectedOpportunityForReceipt !== null;
    }

    handleOpenSetAmount() {
        if (this.isSetAmountDisabled) {
            return;
        }
        this.selectedInvoiceForAmount = this.selectedNeedsAmountInvoices[0];
        this.setAmountValue = null;
        this.isSetAmountModalOpen = true;
    }

    handleSetAmountClose() {
        this.isSetAmountModalOpen = false;
        this.selectedInvoiceForAmount = null;
        this.setAmountValue = null;
    }

    handleSetAmountChange(event) {
        this.setAmountValue = event.target.value;
    }

    async handleSetAmountSave() {
        const amount = Number(this.setAmountValue);
        if (!this.selectedInvoiceForAmount?.invoiceId || !Number.isFinite(amount) || amount <= 0) {
            this.errorMessage = 'Enter an invoice amount greater than 0.';
            return;
        }
        this.isActionLoading = true;
        this.errorMessage = undefined;
        try {
            await setInvoiceAmount({
                invoiceId: this.selectedInvoiceForAmount.invoiceId,
                totalAmount: amount
            });
            this.handleSetAmountClose();
            this.setSelectedRows([]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invoice Amount Set',
                    message: 'The invoice amount was saved.',
                    variant: 'success'
                })
            );
            await this.loadData(true);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isActionLoading = false;
        }
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
                key: 'setInvoiceAmount',
                label: 'Set Invoice Amount',
                variant: 'neutral',
                disabled: this.isSetAmountDisabled,
                title: 'Set Invoice Amount'
            }
        ];
    }

    buildKpiTile(definition, configRecord) {
        const countValue = this.metrics[definition.countKey] || 0;
        return {
            ...definition,
            title: definition.title,
            icon: configRecord?.iconName || definition.icon,
            metricText: definition.amountKey
                ? CURRENCY_FORMATTER.format(this.metrics[definition.amountKey] || 0)
                : String(countValue),
            countText: this.buildKpiCountText(definition.countKey)
        };
    }

    getRenderableCommissionSections() {
        const sections = [...(this.invoiceSections || []), ...(this.commissionSections || [])];
        return sections.sort((left, right) => {
            const leftIndex = SECTION_DISPLAY_ORDER.indexOf(left.categoryKey);
            const rightIndex = SECTION_DISPLAY_ORDER.indexOf(right.categoryKey);
            return (leftIndex === -1 ? SECTION_DISPLAY_ORDER.length : leftIndex)
                - (rightIndex === -1 ? SECTION_DISPLAY_ORDER.length : rightIndex);
        });
    }

    normalizeSections(data) {
        return (data || []).map((section, sectionIndex) => {
            const categoryKey = section.categoryKey || `CATEGORY_${sectionIndex}`;
            const salespeople = (section.salespersonGroups || []).map((salesperson, salespersonIndex) => {
                const salespersonKey =
                    `${categoryKey}-salesperson-${salesperson.salespersonId || 'unassigned'}-${salespersonIndex}`;
                const opportunities = decorateAccountGroups(
                    [...(salesperson.opportunities || [])]
                        .sort((left, right) => compareAccountGroup(left, right, 1))
                        .map((opportunity, opportunityIndex) => {
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
                                outstandingCommission: commissionAmount - commissionPaid,
                                isLedgerActionDisabled: !opportunity.ledgerId
                            };
                        }),
                    'slds-theme_shade grouped-diary-table__row'
                );

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
                isInvoiceSection: false,
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

    normalizeWorklistInvoices(data) {
        const sourceRows = data?.invoices || [];
        if (sourceRows.length) {
            return this.mapInvoiceRows(sourceRows);
        }
        const byId = new Map();
        this.normalizeInvoiceSections(data?.invoiceSections || []).forEach(section => {
            (section.invoices || []).forEach(invoice => {
                if (invoice.invoiceId && !byId.has(invoice.invoiceId)) {
                    byId.set(invoice.invoiceId, invoice);
                }
            });
        });
        return Array.from(byId.values());
    }

    mapInvoiceRows(rows) {
        return (rows || [])
            .filter(invoice => invoice?.invoiceId)
            .map((invoice, invoiceIndex) => ({
                ...invoice,
                key: 'inv-' + (invoice.invoiceId || invoiceIndex),
                payments: invoice.payments || []
            }));
    }

    normalizeInvoiceSections(sections) {
        return (sections || []).map((section, sectionIndex) => {
            const categoryKey = section.categoryKey || `INVOICE_CATEGORY_${sectionIndex}`;
            const invoices = this.mapInvoiceRows(section.rows || []);
            return {
                ...section,
                categoryKey,
                categoryLabel: section.categoryLabel || `Category ${sectionIndex + 1}`,
                isInvoiceSection: true,
                invoices,
                invoiceCount: invoices.length,
                totalAmount: section.totalAmount || 0,
                salespeople: []
            };
        });
    }

    invoicesForCategory(categoryKey) {
        const uniqueInvoices = this.uniqueSearchInvoices;
        if (categoryKey === CATEGORY_KEYS.ALL_RECEIVABLES) {
            return uniqueInvoices;
        }
        const idSet = this.invoiceIdsForCategory(categoryKey);
        return uniqueInvoices.filter(invoice => idSet.has(invoice.invoiceId));
    }

    invoiceIdsForCategory(categoryKey) {
        const section = (this.invoiceSections || []).find(item => item.categoryKey === categoryKey);
        return new Set((section?.invoices || []).map(invoice => invoice.invoiceId).filter(Boolean));
    }

    sumBalances(invoices, idSet) {
        return (invoices || []).reduce((total, invoice) => {
            if (!idSet.has(invoice.invoiceId)) {
                return total;
            }
            return total + Number(invoice.balanceDue || 0);
        }, 0);
    }

    invoiceMatchesSearch(invoice) {
        const searchQuery = this.searchQuery;
        if (!searchQuery) {
            return true;
        }
        const haystack = [
            invoice.invoiceNumber,
            invoice.quoteNumber,
            invoice.opportunityName,
            invoice.accountName,
            invoice.ownerName,
            invoice.status,
            invoice.invoiceType
        ]
            .join(' ')
            .toLowerCase();
        return haystack.includes(searchQuery);
    }

    decorateInvoice(invoice) {
        const key = 'inv-' + invoice.invoiceId;
        const isExpanded = this.expandedRows.includes(key);
        const attributed = invoice.attributedOpportunityNarratives || [];
        const additionalNarratives = attributed.filter(
            narrative => narrative.opportunityId && narrative.opportunityId !== invoice.opportunityId
        );
        const hasAdditionalNarratives = additionalNarratives.length > 0;
        const governingDescription = (invoice.opportunityDescription || '').trim();
        const narrativeBlocks = hasAdditionalNarratives
            ? attributed.map(narrative => {
                  const description = (narrative.description || '').trim();
                  return {
                      key: key + '-narr-' + narrative.opportunityId,
                      opportunityName: narrative.opportunityName || 'Opportunity',
                      description,
                      showEmpty: !description
                  };
              })
            : [];
        return {
            ...invoice,
            key,
            isExpanded,
            isSelected: this.selectedRows.includes(key),
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            expandAltText: isExpanded ? 'Collapse invoice context' : 'Expand invoice context',
            hasPayments: (invoice.payments || []).length > 0,
            paymentRowKey: key + '-detail',
            hasAdditionalNarratives,
            narrativeBlocks,
            showGoverningDescription: !hasAdditionalNarratives && Boolean(governingDescription),
            showGoverningEmpty: !hasAdditionalNarratives && !governingDescription,
            governingDescription,
            ownerDisplayName: invoice.ownerName || 'Unassigned',
            quoteDisplay: invoice.quoteNumber || '',
            identityQuoteLine: [invoice.opportunityName, invoice.quoteNumber].filter(Boolean).join(' · ')
        };
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

        this.allCanonicalInvoices.forEach(invoice => {
            validParentKeys.add(invoice.key);
            validKeys.add(invoice.key);
        });
        const ownerKeys = new Set(
            this.allCanonicalInvoices.map(invoice => 'sp-' + (invoice.ownerId || 'unassigned'))
        );
        ownerKeys.forEach(key => {
            validParentKeys.add(key);
            validKeys.add(key);
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
        const hasExistingSections = (this.invoiceSections || []).length > 0 || (this.worklistInvoices || []).length > 0;
        if (hasExistingSections) {
            this.isRefreshing = true;
            this.isMetricsLoading = false;
            this.isDataLoading = false;
        } else {
            this.isMetricsLoading = true;
            this.isDataLoading = true;
        }
        this.errorMessage = undefined;
        const cacheKey = buildRuntimeCacheKey(this.dateFilter, this.opportunityOwnerId);

        try {
            if (forceRefresh) {
                receivablesRuntimeCache.delete(cacheKey);
            } else if (receivablesRuntimeCache.has(cacheKey)) {
                this.applyRuntimeData(cloneRuntimeData(receivablesRuntimeCache.get(cacheKey)));
                return;
            }

            const refreshToken = forceRefresh ? Date.now() : null;
            const data = await getTabRuntime({
                refreshToken,
                filterKey: this.dateFilter?.filterKey || DEFAULT_DATE_FILTER.filterKey,
                startDate: this.dateFilter?.startDate || null,
                endDate: this.dateFilter?.endDate || null,
                opportunityOwnerId: this.opportunityOwnerId || null
            });
            receivablesRuntimeCache.set(cacheKey, cloneRuntimeData(data));
            this.applyRuntimeData(data);
        } catch (error) {
            this.providerWarnings = [];
            this.metrics = {};
            this.worklistInvoices = [];
            this.invoiceSections = [];
            this.commissionSections = [];
            this.errorMessage = this.reduceError(error);
            this.setSelectedRows([]);
            this.setExpandedRows([]);
        } finally {
            this.isMetricsLoading = false;
            this.isDataLoading = false;
            this.isRefreshing = false;
        }
    }

    applyRuntimeData(data) {
        this.providerWarnings = data?.warnings || [];
        (data?.warnings || []).forEach(warning => console.warn(warning));
        this.metrics = data?.metrics || {};
        this.worklistInvoices = this.normalizeWorklistInvoices(data);
        this.invoiceSections = this.normalizeInvoiceSections(data?.invoiceSections || []);
        this.commissionSections = [];
        this.reconcileActiveState();
        const hasExpandedOwner = this.expandedRows.some(key => String(key).startsWith('sp-'));
        const firstOwner = this.salespersonGroups[0];
        if (!hasExpandedOwner && firstOwner) {
            this.setExpandedRows([...this.expandedRows, firstOwner.key]);
        }
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
        saveColumnWidths(RECEIVABLES_COLUMN_WIDTHS_KEY, this.columnWidths);
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
        if (countKey === 'commissionEarnedCount' || countKey === 'commissionPayableCount') {
            return `${normalizedCount} ${normalizedCount === 1 ? 'Commission' : 'Commissions'}`;
        }
        if (countKey === 'needsAmountCount') {
            return `${normalizedCount} ${normalizedCount === 1 ? 'Invoice' : 'Invoices'}`;
        }
        return `${normalizedCount} ${normalizedCount === 1 ? 'Invoice' : 'Invoices'}`;
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