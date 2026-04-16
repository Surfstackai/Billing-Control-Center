import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import postReceipt from '@salesforce/apex/BillingControl_Invoicing.postReceipt';
import INVOICE_PAYMENT_OBJECT from '@salesforce/schema/Invoice_Payment__c';
import PAYMENT_METHOD_FIELD from '@salesforce/schema/Invoice_Payment__c.Payment_Method__c';

export default class BillingControlCenterPostReceiptModal extends LightningElement {
    localOpportunity;
    paymentAmount;
    paymentDate;
    paymentMethod = '';
    paymentMethodOptions = [];
    referenceNumber = '';
    isSaving = false;
    hasSubmitted = false;
    errorMessage;

    @wire(getObjectInfo, { objectApiName: INVOICE_PAYMENT_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$defaultRecordTypeId',
        fieldApiName: PAYMENT_METHOD_FIELD
    })
    wiredPaymentMethodValues({ data }) {
        this.paymentMethodOptions = (data?.values || []).map(option => ({
            label: option.label,
            value: option.value
        }));
    }

    @api
    set opportunity(value) {
        this.localOpportunity = value
            ? {
                id: value.id || value.opportunityId,
                name: value.name || value.opportunityName,
                accountName: value.accountName,
                ownerName: value.ownerName,
                amount: Number(value.amount || 0),
                amountPaid: Number(value.amountPaid || 0),
                balanceDue: Number(value.balanceDue || 0)
            }
            : null;
        this.paymentAmount = null;
        this.paymentDate = null;
        this.paymentMethod = '';
        this.referenceNumber = '';
        this.isSaving = false;
        this.hasSubmitted = false;
        this.errorMessage = undefined;
    }

    get opportunity() {
        return this.localOpportunity;
    }

    get defaultRecordTypeId() {
        return this.objectInfo?.data?.defaultRecordTypeId;
    }

    get invoiceAmount() {
        return this.localOpportunity ? this.localOpportunity.amount : 0;
    }

    get previouslyPaid() {
        return this.localOpportunity ? this.localOpportunity.amountPaid : 0;
    }

    get balanceDue() {
        if (!this.localOpportunity) {
            return 0;
        }

        return this.localOpportunity.balanceDue;
    }

    get paymentAmountNumber() {
        const parsedValue = Number(this.paymentAmount);
        return Number.isFinite(parsedValue) ? parsedValue : 0;
    }

    get validationMessage() {
        if (!this.localOpportunity) {
            return 'No opportunity was provided for receipt posting.';
        }
        if (this.paymentAmount === null || this.paymentAmount === '' || Number.isNaN(Number(this.paymentAmount))) {
            return 'Enter a payment amount received.';
        }
        if (this.paymentAmountNumber <= 0) {
            return 'Payment amount received must be greater than 0.';
        }
        if (this.paymentAmountNumber > this.balanceDue) {
            return 'Payment amount received cannot exceed the balance due.';
        }
        if (!this.paymentDate || !this.paymentMethod.trim() || !this.referenceNumber.trim()) {
            return 'Complete all required fields before posting the receipt.';
        }
        return '';
    }

    get showValidationMessage() {
        return Boolean(this.validationMessage) && (
            this.hasSubmitted ||
            this.paymentAmount !== null ||
            this.paymentDate ||
            this.paymentMethod ||
            this.referenceNumber
        );
    }

    get isPostDisabled() {
        return this.isSaving || Boolean(this.validationMessage);
    }

    handleInputChange(event) {
        const fieldName = event.target.dataset.field;
        if (!fieldName) {
            return;
        }

        this[fieldName] = event.target.value;
        this.errorMessage = undefined;

        if (this.hasSubmitted) {
            this.reportFieldValidity();
        }
    }

    handleCancel() {
        if (this.isSaving) {
            return;
        }

        this.dispatchEvent(new CustomEvent('close'));
    }

    async handlePostReceipt() {
        this.hasSubmitted = true;
        this.errorMessage = undefined;

        const areFieldsValid = this.reportFieldValidity();
        if (!areFieldsValid || this.validationMessage) {
            return;
        }

        this.isSaving = true;

        try {
            await postReceipt({
                input: {
                    opportunityId: this.localOpportunity.id,
                    amountReceived: this.paymentAmountNumber,
                    paymentDate: this.paymentDate,
                    paymentMethod: this.paymentMethod.trim(),
                    referenceNumber: this.referenceNumber.trim()
                }
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Receipt Posted',
                message: 'Payment was recorded successfully.',
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('close'));
            this.dispatchEvent(new CustomEvent('refresh'));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    reportFieldValidity() {
        return [
            ...this.template.querySelectorAll('lightning-input'),
            ...this.template.querySelectorAll('lightning-combobox')
        ].reduce((isValid, input) => input.reportValidity() && isValid, true);
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