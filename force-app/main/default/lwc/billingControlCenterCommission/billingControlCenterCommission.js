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

const CATEGORY_KEYS = {
    REVENUE_UNDER_COLLECTION: 'REVENUE_UNDER_COLLECTION',
    COMMISSION_EARNED: 'COMMISSION_EARNED',
    COMMISSION_PAYABLE: 'COMMISSION_PAYABLE'
};

export default class BillingControlCenterCommission extends NavigationMixin(LightningElement) {
    metrics = {};
    commissionSections = [];
    selectedRows = [];
    expandedRows = [];
    wiredMetricsResult;
    wiredCommissionDataResult;
    isMetricsLoading = true;
    isDataLoading = true;
    isRefreshing = false;
    isActionLoading = false;
    isPostReceiptModalOpen = false;
    selectedOpportunityForReceipt = null;
    errorMessage;

    get commissionDataContext() {
        return 'kpi';
    }

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

    @wire(getCommissionData, { subtabType: '$commissionDataContext' })
    wiredCommissionData(value) {
        this.wiredCommissionDataResult = value;
        const { data, error } = value;

        if (data) {
            this.commissionSections = this.normalizeSections(data);
            this.isDataLoading = false;
            this.errorMessage = undefined;
            this.reconcileActiveState();
        } else if (error) {
            this.commissionSections = [];
            this.isDataLoading = false;
            this.errorMessage = this.reduceError(error);
            this.setSelectedRows([]);
            this.setExpandedRows([]);
        }
    }

    get isLoading() {
        return this.isMetricsLoading || this.isDataLoading || this.isRefreshing || this.isActionLoading;
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            value: this.metrics[tile.key] || 0,
            countText: this.buildKpiCountText(tile.countKey)
        }));
    }

    get accordionSections() {
        const expandedKeys = new Set(this.expandedRows);
        const selectedKeys = new Set(this.selectedRows);

        return this.commissionSections.map(section => ({
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

        this.commissionSections.forEach(section => {
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

        this.commissionSections.forEach(section => {
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
        return this.commissionSections.reduce((total, section) => total + (section.opportunityCount || 0), 0);
    }

    get salespersonCount() {
        return this.commissionSections.reduce(
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
            this.setSelectedRows([]);

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
        this.setSelectedRows([]);
        this.isRefreshing = true;
        try {
            await Promise.all(this.getRefreshPromises());
        } finally {
            this.isRefreshing = false;
        }
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
        for (const section of this.commissionSections) {
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

        this.commissionSections.forEach(section => {
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
        const noun = countKey === 'commissionEarnedCount' || countKey === 'commissionPayableCount'
            ? 'Commission'
            : 'Opportunity';
        return `${normalizedCount} ${noun}${normalizedCount === 1 ? '' : 's'}`;
    }
}