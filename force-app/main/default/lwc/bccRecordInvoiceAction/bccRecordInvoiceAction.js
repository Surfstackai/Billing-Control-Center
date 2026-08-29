import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

import createInvoice from '@salesforce/apex/BillingControl_InvoiceService.createInvoice';
import getInvoiceDefaults from '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults';
import listCandidateOpportunities from '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities';
import getVisitInvoiceContext from '@salesforce/apex/BillingControl_InvoiceService.getVisitInvoiceContext';

export default class BccRecordInvoiceAction extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    invoiceType = 'Balance';
    selectedOpportunityId;
    invoiceAmount;
    invoiceNumber = '';
    acceptFullRemaining = false;
    acceptVariance = false;
    updateOperationalAttribution = false;
    isSaving = false;
    errorMessage;
    candidates = [];
    visitContext;
    loaded = false;

    get cardTitle() {
        return this.invoiceType === 'Deposit' ? 'Record Deposit Invoice' : 'Record Invoice';
    }

    get createLabel() {
        return this.invoiceType === 'Deposit' ? 'Create Deposit Invoice' : 'Create Invoice';
    }

    get amountRequired() {
        return true;
    }

    get isServiceAppointment() {
        return this.objectApiName === 'ServiceAppointment';
    }

    get showOpportunityPicker() {
        return this.candidates.length > 0;
    }

    get requiresOpportunityChoice() {
        return this.candidates.length > 1;
    }

    get showAttributionOptIn() {
        return this.isServiceAppointment && this.visitIsUnassigned;
    }

    get visitIsUnassigned() {
        return this.visitContext?.unassigned === true;
    }

    get visitIsAssigned() {
        return this.isServiceAppointment && this.visitContext && this.visitContext.unassigned !== true;
    }

    get hasLedger() {
        return Boolean(this.visitContext?.ledgerId);
    }

    get visitLabel() {
        if (!this.visitContext) {
            return '';
        }
        const numberLabel = this.visitContext.serviceAppointmentNumber || 'This visit';
        const workOrderLabel = this.visitContext.workOrderNumber
            ? ' · ' + this.visitContext.workOrderNumber
            : '';
        const jobLabel = this.visitContext.opportunityName
            ? ' · ' + this.visitContext.opportunityName
            : '';
        return numberLabel + workOrderLabel + jobLabel;
    }

    get opportunityOptions() {
        return this.candidates.map(candidate => ({
            label: `${candidate.quoteNumber ? candidate.quoteNumber + ' · ' : ''}${candidate.name}`,
            value: candidate.opportunityId
        }));
    }

    get isCreateDisabled() {
        return this.isSaving
            || !this.selectedOpportunityId
            || this.invoiceAmount == null
            || Number(this.invoiceAmount) <= 0;
    }

    async renderedCallback() {
        if (this.loaded || !this.recordId || !this.objectApiName) {
            return;
        }
        this.loaded = true;
        await this.loadCandidates();
    }

    async loadCandidates() {
        try {
            const loads = [
                listCandidateOpportunities({
                    objectApiName: this.objectApiName,
                    recordId: this.recordId
                })
            ];
            if (this.isServiceAppointment) {
                loads.push(getVisitInvoiceContext({ serviceAppointmentId: this.recordId }));
            }
            const results = await Promise.all(loads);
            this.candidates = results[0] || [];
            this.visitContext = this.isServiceAppointment ? results[1] : null;
            if (this.candidates.length === 1) {
                this.selectedOpportunityId = this.candidates[0].opportunityId;
                await this.loadDefaults();
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    async loadDefaults() {
        if (!this.selectedOpportunityId) {
            return;
        }
        const defaults = await getInvoiceDefaults({
            opportunityId: this.selectedOpportunityId,
            invoiceType: this.invoiceType
        });
        this.invoiceAmount = defaults?.suggestedAmount;
    }

    async handleOpportunityChange(event) {
        this.selectedOpportunityId = event.detail.value;
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

    handleViewLedger() {
        if (!this.visitContext?.ledgerId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.visitContext.ledgerId,
                objectApiName: 'Work_Order_Ledger__c',
                actionName: 'view'
            }
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleCreate() {
        if (this.isCreateDisabled) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const serviceAppointmentIds = this.isServiceAppointment ? [this.recordId] : [];
            await createInvoice({
                request: {
                    opportunityId: this.selectedOpportunityId,
                    invoiceType: this.invoiceType,
                    invoiceAmount: Number(this.invoiceAmount),
                    invoiceNumber: (this.invoiceNumber || '').trim(),
                    serviceAppointmentIds,
                    acceptFullRemaining: this.acceptFullRemaining,
                    acceptVariance: this.acceptVariance,
                    amountPendingExternal: false,
                    updateOperationalAttribution: this.updateOperationalAttribution,
                    amountSource: 'Entered'
                }
            });
            this.dispatchEvent(new ShowToastEvent({
                title: this.cardTitle,
                message: 'Invoice created.',
                variant: 'success'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
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
