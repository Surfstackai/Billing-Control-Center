import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import createInvoice from '@salesforce/apex/BillingControl_InvoiceService.createInvoice';
import getInvoiceDefaults from '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults';
import listCandidateOpportunities from '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities';

export default class BillingControlCenterInvoiceModal extends LightningElement {
    localServiceAppointments = [];
    candidates = [];
    invoiceType = 'Balance';
    selectedOpportunityId;
    invoiceAmount;
    invoiceNumber = '';
    acceptFullRemaining = false;
    acceptVariance = false;
    updateOperationalAttribution = false;
    isSaving = false;
    isLoadingCandidates = false;
    errorMessage;
    loadToken = 0;
    _contextOpportunityId;

    invoiceTypeOptions = [
        { label: 'Deposit', value: 'Deposit' },
        { label: 'Balance', value: 'Balance' },
        { label: 'Progress', value: 'Progress' },
        { label: 'Adjustment', value: 'Adjustment' }
    ];

    @api
    get contextOpportunityId() {
        return this._contextOpportunityId;
    }

    set contextOpportunityId(value) {
        const next = value || null;
        if (next === this._contextOpportunityId) {
            return;
        }
        this._contextOpportunityId = next;
        if (this._contextOpportunityId && !this.selectedOpportunityId) {
            this.selectedOpportunityId = this._contextOpportunityId;
        }
        this.loadCandidates();
    }

    @api
    set serviceAppointments(value) {
        this.localServiceAppointments = (value || []).map(row => ({ ...row }));
        this.isSaving = false;
        this.acceptFullRemaining = false;
        this.acceptVariance = false;
        this.updateOperationalAttribution = false;
        this.errorMessage = undefined;
        this.invoiceNumber = '';
        this.invoiceType = 'Balance';
        this.preselectFromAppointments();
        this.loadCandidates();
    }

    get serviceAppointments() {
        return this.localServiceAppointments;
    }

    get selectedCount() {
        return this.evidenceAppointments.length;
    }

    get skippedForeignCount() {
        if (!this.selectedOpportunityId) {
            return 0;
        }
        return this.localServiceAppointments.filter(
            row => row.opportunityId && row.opportunityId !== this.selectedOpportunityId
        ).length;
    }

    get evidenceAppointments() {
        return this.localServiceAppointments.filter(row => {
            if (!row.serviceAppointmentId) {
                return false;
            }
            if (!this.selectedOpportunityId) {
                return true;
            }
            return !row.opportunityId || row.opportunityId === this.selectedOpportunityId;
        });
    }

    get opportunityOptions() {
        return this.candidates.map(candidate => ({
            label: `${candidate.quoteNumber ? candidate.quoteNumber + ' · ' : ''}${candidate.name}`,
            value: candidate.opportunityId
        }));
    }

    get showCandidateCombobox() {
        return this.candidates.length > 0;
    }

    get requiresOpportunityChoice() {
        return this.candidates.length > 1;
    }

    get showOpportunityLookup() {
        return this.candidates.length === 0;
    }

    get hasEvidenceAppointments() {
        return this.evidenceAppointments.length > 0;
    }

    get assignedAppointments() {
        return this.evidenceAppointments
            .filter(row => row.opportunityId)
            .map(row => this.decorateVisitRow(row));
    }

    get unassignedAppointments() {
        return this.evidenceAppointments
            .filter(row => !row.opportunityId)
            .map(row => this.decorateVisitRow(row));
    }

    get hasAssignedAppointments() {
        return this.assignedAppointments.length > 0;
    }

    get hasUnassignedAppointments() {
        return this.unassignedAppointments.length > 0;
    }

    get hasSkippedForeignAppointments() {
        return this.skippedForeignCount > 0;
    }

    decorateVisitRow(row) {
        return {
            ...row,
            hasLedger: Boolean(row.ledgerId)
        };
    }

    get isCreateDisabled() {
        return this.isSaving
            || !this.selectedOpportunityId
            || this.invoiceAmount == null
            || Number(this.invoiceAmount) <= 0;
    }

    preselectFromAppointments() {
        const attributedIds = [
            ...new Set(this.localServiceAppointments.map(row => row.opportunityId).filter(Boolean))
        ];
        if (attributedIds.length === 1) {
            this.selectedOpportunityId = attributedIds[0];
            const sample = this.localServiceAppointments.find(
                row => row.opportunityId === this.selectedOpportunityId
            );
            this.invoiceAmount = sample?.invoiceableOpportunityAmount;
            return;
        }
        this.selectedOpportunityId = undefined;
        this.invoiceAmount = undefined;
        if (this._contextOpportunityId) {
            this.selectedOpportunityId = this._contextOpportunityId;
        }
    }

    async loadCandidates() {
        const token = ++this.loadToken;
        this.isLoadingCandidates = true;
        const workOrderIds = [
            ...new Set(this.localServiceAppointments.map(row => row.workOrderId).filter(Boolean))
        ];
        const opportunityIds = [
            ...new Set(this.localServiceAppointments.map(row => row.opportunityId).filter(Boolean))
        ];
        if (this._contextOpportunityId) {
            opportunityIds.push(this._contextOpportunityId);
        }
        try {
            const candidateLists = await Promise.all([
                ...workOrderIds.map(workOrderId =>
                    listCandidateOpportunities({ objectApiName: 'WorkOrder', recordId: workOrderId })
                ),
                ...opportunityIds.map(opportunityId =>
                    listCandidateOpportunities({ objectApiName: 'Opportunity', recordId: opportunityId })
                )
            ]);
            if (token !== this.loadToken) {
                return;
            }
            const byId = new Map();
            for (const list of candidateLists) {
                for (const candidate of list || []) {
                    byId.set(candidate.opportunityId, candidate);
                }
            }
            this.candidates = Array.from(byId.values());
            if (!this.selectedOpportunityId && this.candidates.length === 1) {
                this.selectedOpportunityId = this.candidates[0].opportunityId;
            }
            if (this.selectedOpportunityId) {
                await this.loadDefaults();
            }
        } catch (error) {
            if (token === this.loadToken) {
                this.errorMessage = this.reduceError(error);
            }
        } finally {
            if (token === this.loadToken) {
                this.isLoadingCandidates = false;
            }
        }
    }

    async loadDefaults() {
        if (!this.selectedOpportunityId) {
            return;
        }
        try {
            const defaults = await getInvoiceDefaults({
                opportunityId: this.selectedOpportunityId,
                invoiceType: this.invoiceType
            });
            if (defaults?.suggestedAmount != null) {
                this.invoiceAmount = defaults.suggestedAmount;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    async handleOpportunityChange(event) {
        this.selectedOpportunityId = event.detail.value;
        await this.loadDefaults();
    }

    async handleOpportunityLookup(event) {
        this.selectedOpportunityId = event.detail.recordId;
        await this.loadDefaults();
    }

    async handleInvoiceTypeChange(event) {
        this.invoiceType = event.detail.value;
        await this.loadDefaults();
    }

    handleAmountChange(event) {
        this.invoiceAmount = event.detail.value;
    }

    handleInvoiceNumberChange(event) {
        this.invoiceNumber = event.detail.value;
    }

    handleAcceptFullRemainingChange(event) {
        this.acceptFullRemaining = event.target.checked;
    }

    handleAcceptVarianceChange(event) {
        this.acceptVariance = event.target.checked;
    }

    handleAttributionChange(event) {
        this.updateOperationalAttribution = event.target.checked;
    }

    handleViewLedger(event) {
        const host =
            event.currentTarget?.closest?.('[data-ledger-id]') ||
            event.target?.closest?.('[data-ledger-id]');
        const ledgerId = host?.dataset?.ledgerId;
        if (!ledgerId) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('viewledger', {
                detail: { ledgerId }
            })
        );
    }

    handleCancel() {
        if (this.isSaving) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleCreateInvoice() {
        if (this.isCreateDisabled) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const result = await createInvoice({
                request: {
                    opportunityId: this.selectedOpportunityId,
                    invoiceType: this.invoiceType,
                    invoiceAmount: Number(this.invoiceAmount),
                    invoiceNumber: (this.invoiceNumber || '').trim(),
                    serviceAppointmentIds: this.evidenceAppointments
                        .map(row => row.serviceAppointmentId)
                        .filter(Boolean),
                    acceptFullRemaining: this.acceptFullRemaining,
                    acceptVariance: this.acceptVariance,
                    amountPendingExternal: false,
                    updateOperationalAttribution: this.updateOperationalAttribution,
                    amountSource: 'Entered'
                }
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invoice created',
                message: result?.invoiceNumber
                    ? `Invoice ${result.invoiceNumber} recorded.`
                    : 'Invoice recorded.',
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('success', { detail: { invoicesCreated: 1 } }));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invoice not created',
                message: this.errorMessage,
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isSaving = false;
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
