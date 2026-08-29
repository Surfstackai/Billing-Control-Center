import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import createInvoice from '@salesforce/apex/BillingControl_InvoiceService.createInvoice';
import getInvoiceDefaults from '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults';
import listCandidateOpportunities from '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities';

export default class BccRecordDepositAction extends LightningElement {
    @api recordId;
    @api objectApiName;

    invoiceType = 'Deposit';
    selectedOpportunityId;
    invoiceAmount;
    invoiceNumber = '';
    acceptFullRemaining = false;
    acceptVariance = false;
    updateOperationalAttribution = false;
    isSaving = false;
    errorMessage;
    candidates = [];
    loaded = false;

    get cardTitle() {
        return 'Record Deposit Invoice';
    }

    get createLabel() {
        return 'Create Deposit Invoice';
    }

    get showOpportunityPicker() {
        return this.candidates.length > 0;
    }

    get requiresOpportunityChoice() {
        return this.candidates.length > 1;
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
            this.candidates = await listCandidateOpportunities({
                objectApiName: this.objectApiName,
                recordId: this.recordId
            }) || [];
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
            await createInvoice({
                request: {
                    opportunityId: this.selectedOpportunityId,
                    invoiceType: 'Deposit',
                    invoiceAmount: Number(this.invoiceAmount),
                    invoiceNumber: (this.invoiceNumber || '').trim(),
                    serviceAppointmentIds: [],
                    acceptFullRemaining: this.acceptFullRemaining,
                    acceptVariance: this.acceptVariance,
                    amountPendingExternal: false,
                    updateOperationalAttribution: false,
                    amountSource: 'Entered'
                }
            });
            this.dispatchEvent(new ShowToastEvent({
                title: this.cardTitle,
                message: 'Deposit invoice created.',
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
