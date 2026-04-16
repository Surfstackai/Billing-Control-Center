import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getCommissionData from '@salesforce/apex/BillingControl_Invoicing.getCommissionData';
import getCommissionMetrics from '@salesforce/apex/BillingControl_Invoicing.getCommissionMetrics';
import updateCommissionPaid from '@salesforce/apex/BillingControl_Invoicing.updateCommissionPaid';

const KPI_CONFIG = [
    {
        key: 'revenueUnderCollection',
        countKey: 'revenueUnderCollectionCount',
        title: 'Accounts Receivable (A/R)',
        icon: 'utility:moneybag',
        hint: 'Opportunity Amount where Billing Status = Billed (Outstanding Receivable)'
    },
    {
        key: 'commissionEarned',
        countKey: 'commissionEarnedCount',
        title: 'Commission Accrued',
        icon: 'utility:approval',
        hint: 'Commission Amount on billed opportunities awaiting collection'
    },
    {
        key: 'commissionPayable',
        countKey: 'commissionPayableCount',
        title: 'Commission Payable',
        icon: 'utility:currency',
        hint: 'Commission Amount on paid opportunities with unpaid balance'
    }
];

const TAB_VALUES = {
    invoices: 'invoices',
    commissions: 'commissions'
};

export default class BillingControlCenterCommission extends NavigationMixin(LightningElement) {
    activeTabValue = TAB_VALUES.invoices;
    metrics = {};
    salespeople = [];
    selectedRowsByTab = {
        invoices: [],
        commissions: []
    };
    expandedRowsByTab = {
        invoices: [],
        commissions: []
    };
    wiredMetricsResult;
    wiredCommissionDataResult;
    isMetricsLoading = true;
    isDataLoading = true;
    isRefreshing = false;
    isActionLoading = false;
    isPostReceiptModalOpen = false;
    selectedOpportunityForReceipt = null;
    errorMessage;

    @wire(getCommissionMetrics)
    wiredMetrics(value) {
        this.wiredMetricsResult = value;
        const { data, error } = value;

        if (data) {
            this.metrics = data;
            this.isMetricsLoading = false;
            this.errorMessage = undefined;
        } else if (error) {
            this.metrics = {};
            this.isMetricsLoading = false;
            this.errorMessage = this.reduceError(error);
        }
    }

    @wire(getCommissionData, { subtabType: '$activeServiceSubtab' })
    wiredCommissionData(value) {
        this.wiredCommissionDataResult = value;
        const { data, error } = value;

        if (data) {
            this.salespeople = this.normalizeSalespeople(data);
            this.isDataLoading = false;
            this.errorMessage = undefined;
            this.reconcileActiveState();
        } else if (error) {
            this.salespeople = [];
            this.isDataLoading = false;
            this.errorMessage = this.reduceError(error);
            this.setSelectedRows([]);
            this.setExpandedRows([]);
        }
    }

    get isLoading() {
        return this.isMetricsLoading || this.isDataLoading || this.isRefreshing || this.isActionLoading;
    }

    get activeServiceSubtab() {
        return this.activeTabValue === TAB_VALUES.invoices ? 'earned' : 'payable';
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            value: this.metrics[tile.key] || 0,
            countText: this.buildKpiCountText(tile.countKey)
        }));
    }

    get displayedSalespeople() {
        const expandedKeys = new Set(this.expandedRows);
        const selectedKeys = new Set(this.selectedRows);

        return this.salespeople.map(salesperson => ({
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
        }));
    }

    get hasRows() {
        return this.displayedSalespeople.length > 0;
    }

    get selectedRows() {
        return this.selectedRowsByTab[this.activeTabValue] || [];
    }

    get expandedRows() {
        return this.expandedRowsByTab[this.activeTabValue] || [];
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    get selectedCommissionIds() {
        const selectedKeys = new Set(this.selectedRows);
        const commissionIds = new Set();

        this.salespeople.forEach(salesperson => {
            if (selectedKeys.has(salesperson.key)) {
                salesperson.opportunities.forEach(opportunity => {
                    if (opportunity.commissionId) {
                        commissionIds.add(opportunity.commissionId);
                    }
                });
            }

            salesperson.opportunities.forEach(opportunity => {
                if (selectedKeys.has(opportunity.key) && opportunity.commissionId) {
                    commissionIds.add(opportunity.commissionId);
                }
            });
        });

        return Array.from(commissionIds);
    }

    get opportunityCount() {
        return this.salespeople.reduce((total, salesperson) => total + salesperson.opportunities.length, 0);
    }

    get activePanelTitle() {
        return this.activeTabValue === TAB_VALUES.invoices
            ? 'Accounts Receivable by Salesperson'
            : 'Commissions by Salesperson';
    }

    get emptyMessage() {
        return this.activeTabValue === TAB_VALUES.invoices
            ? 'No invoices currently require receivables action.'
            : 'No commissions currently require payout action.';
    }

    get isPayCommissionDisabled() {
        return this.selectedCommissionIds.length === 0 || this.isActionLoading;
    }

    get selectedInvoiceOpportunities() {
        const selectedKeys = new Set(this.selectedRows);
        const opportunitiesById = new Map();
        this.salespeople.forEach(salesperson => {
            salesperson.opportunities.forEach(opportunity => {
                if (selectedKeys.has(salesperson.key) || selectedKeys.has(opportunity.key)) {
                    if (!opportunitiesById.has(opportunity.opportunityId)) {
                        opportunitiesById.set(opportunity.opportunityId, {
                            opportunityId: opportunity.opportunityId,
                            opportunityName: opportunity.opportunityName || opportunity.name,
                            accountName: opportunity.accountName,
                            amount: opportunity.amount || 0,
                            amountPaid: opportunity.amountPaid || 0,
                            balanceDue: opportunity.balanceDue || 0,
                            ownerName: salesperson.salespersonName
                        });
                    }
                }
            });
        });
        return Array.from(opportunitiesById.values());
    }

    get isPostReceiptDisabled() {
        return this.selectedInvoiceOpportunities.length !== 1 || this.isActionLoading;
    }

    handleTabActivated(event) {
        const nextValue = event.target.value;
        if (!nextValue || nextValue === this.activeTabValue) {
            return;
        }

        this.activeTabValue = nextValue;
        this.isDataLoading = true;
        this.errorMessage = undefined;
    }

    handleParentSelection(event) {
        const rowKey = event.target.dataset.key;
        if (!rowKey) {
            return;
        }

        const nextSelection = new Set(this.selectedRows);
        const salesperson = this.salespeople.find(item => item.key === rowKey);
        const childRows = salesperson ? salesperson.opportunities : [];
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
            await Promise.all(this.getRefreshPromises());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRefreshing = false;
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
            this.selectedRowsByTab = {
                ...this.selectedRowsByTab,
                commissions: []
            };

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Commission Updated',
                    message: 'Selected commissions were marked as fully paid.',
                    variant: 'success'
                })
            );

            this.isRefreshing = true;
            await Promise.all(this.getRefreshPromises());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRefreshing = false;
            this.isActionLoading = false;
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
        this.isRefreshing = true;
        try {
            await Promise.all(this.getRefreshPromises());
        } finally {
            this.isRefreshing = false;
        }
    }

    normalizeSalespeople(data) {
        return (data || []).map((salesperson, index) => {
            const salespersonKey = `salesperson-${salesperson.salespersonId || 'unassigned'}-${index}`;
            const opportunities = (salesperson.opportunities || []).map((opportunity, childIndex) => {
                const commissionAmount = opportunity.commissionAmount || 0;
                const commissionPaid = opportunity.commissionPaid || 0;

                return {
                    ...opportunity,
                    key: `commission-${opportunity.commissionId || childIndex}`,
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
                salespersonName: salesperson.salespersonName || 'Unassigned',
                totalAmount: salesperson.totalAmount || 0,
                totalCommission,
                totalPaid,
                outstandingCommission: totalCommission - totalPaid,
                opportunityCount: opportunities.length,
                opportunities
            };
        });
    }

    reconcileActiveState() {
        const validParentKeys = new Set(this.salespeople.map(salesperson => salesperson.key));
        const validKeys = new Set();

        this.salespeople.forEach(salesperson => {
            validKeys.add(salesperson.key);
            salesperson.opportunities.forEach(opportunity => validKeys.add(opportunity.key));
        });

        this.setExpandedRows(this.expandedRows.filter(key => validParentKeys.has(key)));
        this.setSelectedRows(this.selectedRows.filter(key => validKeys.has(key)));
    }

    setSelectedRows(nextRows) {
        this.selectedRowsByTab = {
            ...this.selectedRowsByTab,
            [this.activeTabValue]: nextRows
        };
    }

    setExpandedRows(nextRows) {
        this.expandedRowsByTab = {
            ...this.expandedRowsByTab,
            [this.activeTabValue]: nextRows
        };
    }

    getRefreshPromises() {
        const refreshes = [];

        if (this.wiredMetricsResult) {
            refreshes.push(refreshApex(this.wiredMetricsResult));
        }
        if (this.wiredCommissionDataResult) {
            refreshes.push(refreshApex(this.wiredCommissionDataResult));
        }

        return refreshes;
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
        return `${normalizedCount} ${countKey === 'commissionEarnedCount' || countKey === 'commissionPayableCount' ? 'Commission' : 'Opportunity'}${normalizedCount === 1 ? '' : 's'}`;
    }
}