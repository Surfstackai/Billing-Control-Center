import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTabRuntime from '@salesforce/apex/BillingControl_CommissionLifecycle.getTabRuntime';
import paySelectedCommissions from '@salesforce/apex/BillingControl_CommissionLifecycle.paySelectedCommissions';
import setManualRate from '@salesforce/apex/BillingControl_CommissionLifecycle.setManualRate';
import { resolveDateRange } from 'c/billingControlCenterDateFilter';

const KPI_CONFIG = [
    { key: 'accrued', developerKey: 'ACCRUED', countKey: 'accruedCount', amountKey: 'accrued', title: 'Accrued', icon: 'utility:clock', hint: 'Customer paid in full. Commission is due to the salesperson by month end.' },
    { key: 'payable', developerKey: 'PAYABLE', countKey: 'payableCount', amountKey: 'payable', title: 'Payable', icon: 'utility:pay_by_check', hint: 'Ready for Pay Commission. Same jobs as Accrued once the customer has paid in full.' },
    { key: 'paidThisPeriod', developerKey: 'PAID', countKey: 'paidThisPeriodCount', amountKey: 'paidThisPeriod', title: 'Paid this period', icon: 'utility:success', hint: 'Salesperson was paid with Pay Commission.' }
];

const DEFAULT_DATE_FILTER = resolveDateRange('This Month');

export default class BillingControlCenterCommissions extends NavigationMixin(LightningElement) {
    @api useExternalToolbar = false;
    isLoading = false;
    errorMessage;
    warnings = [];
    metrics = {};
    sections = [];
    selectedCommissionIds = [];
    selectedKpiKey = 'accrued';
    expandedSalespersonKeys = [];
    rateDraft;
    paidDateValue = new Date().toISOString().slice(0, 10);
    localDateFilter = { ...DEFAULT_DATE_FILTER };
    localOpportunityOwnerId;

    _dateFilter;
    _opportunityOwnerId;

    @api
    set dateFilter(value) {
        this._dateFilter = value ? { ...value } : { ...DEFAULT_DATE_FILTER };
        this.localDateFilter = { ...this._dateFilter };
        this.loadData();
    }
    get dateFilter() {
        return this._dateFilter || this.localDateFilter;
    }

    @api
    set opportunityOwnerId(value) {
        this._opportunityOwnerId = value || null;
        this.localOpportunityOwnerId = this._opportunityOwnerId;
        this.loadData();
    }
    get opportunityOwnerId() {
        return this._opportunityOwnerId || this.localOpportunityOwnerId;
    }

    get dateFilterKey() {
        return this.dateFilter?.filterKey;
    }
    get dateFilterStart() {
        return this.dateFilter?.startDate;
    }
    get dateFilterEnd() {
        return this.dateFilter?.endDate;
    }

    get kpiTiles() {
        return KPI_CONFIG.map(definition => ({
            ...definition,
            count: this.metrics[definition.countKey] || 0,
            amount: this.metrics[definition.amountKey] || 0
        }));
    }

    get visibleSections() {
        const selectedKey = KPI_CONFIG.find(definition => definition.key === this.selectedKpiKey)?.developerKey;
        const expandedKeys = new Set(this.expandedSalespersonKeys);
        return (this.sections || [])
            .filter(section => !selectedKey || section.categoryKey === selectedKey)
            .map(section => {
                const groups = this.groupRowsBySalesperson(section);
                return {
                    ...section,
                    titleWithCount: `${section.categoryLabel} (${section.recordCount || 0})`,
                    isEmpty: !section.rows || section.rows.length === 0,
                    salespersonGroups: groups.map(group => {
                        const isExpanded = expandedKeys.has(group.key);
                        return {
                            ...group,
                            isExpanded,
                            ariaExpanded: isExpanded ? 'true' : 'false',
                            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                            expandAltText: isExpanded
                                ? `Collapse ${group.salespersonName}`
                                : `Expand ${group.salespersonName}`,
                            cardClass: isExpanded
                                ? 'salesperson-card salesperson-card_expanded'
                                : 'salesperson-card',
                            rows: group.rows.map(row => ({
                                ...row,
                                isSelected: this.selectedCommissionIds.includes(row.commissionId),
                                customerStatusLabel: row.customerPaidInFull
                                    ? 'Customer paid in full'
                                    : 'Customer still owes'
                            }))
                        };
                    })
                };
            });
    }

    groupRowsBySalesperson(section) {
        const byOwner = new Map();
        (section.rows || []).forEach(row => {
            const ownerKey = row.salespersonId || row.salespersonName || 'unassigned';
            if (!byOwner.has(ownerKey)) {
                byOwner.set(ownerKey, {
                    key: `${section.categoryKey}-${ownerKey}`,
                    salespersonName: row.salespersonName || 'Unassigned',
                    rows: [],
                    commissionTotal: 0,
                    jobCount: 0
                });
            }
            const group = byOwner.get(ownerKey);
            group.rows.push(row);
            group.jobCount += 1;
            group.commissionTotal += Number(row.commissionAmount || 0);
        });
        return Array.from(byOwner.values());
    }

    get isPayDisabled() {
        return this.selectedPayableIds.length === 0 || this.isLoading;
    }

    get selectedPayableIds() {
        const payableIds = new Set();
        (this.sections || []).forEach(section => {
            (section.rows || []).forEach(row => {
                if (row.canPay && this.selectedCommissionIds.includes(row.commissionId)) {
                    payableIds.add(row.commissionId);
                }
            });
        });
        return Array.from(payableIds);
    }

    get selectedRateRow() {
        if (this.selectedCommissionIds.length !== 1) {
            return null;
        }
        const selectedId = this.selectedCommissionIds[0];
        for (const section of this.sections || []) {
            for (const row of section.rows || []) {
                if (row.commissionId === selectedId && row.status !== 'Paid' && row.status !== 'Cancelled') {
                    return row;
                }
            }
        }
        return null;
    }

    get isRateDisabled() {
        return !this.selectedRateRow || this.isLoading;
    }

    connectedCallback() {
        this.loadData();
    }

    handleDateFilterChange(event) {
        this.localDateFilter = { ...event.detail };
        this.dispatchEvent(new CustomEvent('sharedfilterchange', { detail: { dateFilter: this.localDateFilter } }));
        this.loadData();
    }

    handleOpportunityOwnerChange(event) {
        this.localOpportunityOwnerId = event.detail?.recordId || null;
        this.dispatchEvent(
            new CustomEvent('sharedfilterchange', { detail: { opportunityOwnerId: this.localOpportunityOwnerId } })
        );
        this.loadData();
    }

    handleKpiTileClick(event) {
        this.selectedKpiKey = event.detail?.key || this.selectedKpiKey;
    }

    handleToggleSalesperson(event) {
        const rowKey = event.currentTarget.dataset.key;
        if (!rowKey) {
            return;
        }
        const nextExpanded = new Set(this.expandedSalespersonKeys);
        if (nextExpanded.has(rowKey)) {
            nextExpanded.delete(rowKey);
        } else {
            nextExpanded.add(rowKey);
        }
        this.expandedSalespersonKeys = Array.from(nextExpanded);
    }

    handleRowSelect(event) {
        const commissionId = event.target.dataset.id;
        const next = new Set(this.selectedCommissionIds);
        if (event.target.checked) {
            next.add(commissionId);
        } else {
            next.delete(commissionId);
        }
        this.selectedCommissionIds = Array.from(next);
    }

    handleRateChange(event) {
        this.rateDraft = event.target.value;
    }

    handlePaidDateChange(event) {
        this.paidDateValue = event.target.value;
    }

    async handlePay() {
        if (this.isPayDisabled) {
            return;
        }
        const paidDate = this.paidDateValue || new Date().toISOString().slice(0, 10);
        this.isLoading = true;
        try {
            await paySelectedCommissions({
                commissionIds: this.selectedPayableIds,
                paidDate
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Commission paid',
                message: 'Selected payable commissions were marked Paid.',
                variant: 'success'
            }));
            this.selectedCommissionIds = [];
            await this.loadData();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to pay commissions.';
        } finally {
            this.isLoading = false;
        }
    }

    async handleSaveRate() {
        if (this.isRateDisabled) {
            return;
        }
        const rate = Number(this.rateDraft);
        if (!Number.isFinite(rate) || rate < 0) {
            this.errorMessage = 'Enter a commission rate of 0 or greater.';
            return;
        }
        this.isLoading = true;
        try {
            await setManualRate({ commissionId: this.selectedRateRow.commissionId, commissionRate: rate });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Rate saved',
                message: 'Commission rate was updated. Payable amounts use invoiced total.',
                variant: 'success'
            }));
            this.rateDraft = null;
            await this.loadData();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to save rate.';
        } finally {
            this.isLoading = false;
        }
    }

    async handleOpenOpportunity(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }
        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Opportunity', actionName: 'view' }
        });
        window.open(url, '_blank');
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const runtime = await getTabRuntime({
                refreshToken: Date.now(),
                filterKey: this.dateFilterKey,
                startDate: this.dateFilterStart,
                endDate: this.dateFilterEnd,
                opportunityOwnerId: this.opportunityOwnerId
            });
            this.metrics = runtime?.metrics || {};
            this.sections = runtime?.sections || [];
            this.warnings = runtime?.warnings || [];
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load commissions.';
            this.sections = [];
        } finally {
            this.isLoading = false;
        }
    }
}
