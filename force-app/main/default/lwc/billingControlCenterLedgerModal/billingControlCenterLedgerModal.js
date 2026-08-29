import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class BillingControlCenterLedgerModal extends NavigationMixin(LightningElement) {
    @api embedded = false;
    _ledgerId;

    get dialogClass() {
        return this.embedded ? 'ledger-embedded' : 'slds-modal slds-fade-in-open';
    }

    get containerClass() {
        return this.embedded ? 'ledger-embedded__body' : 'slds-modal__container ledger-modal';
    }

    get showOpenFullLedger() {
        return !this.embedded;
    }

    @api
    get ledgerId() {
        return this._ledgerId;
    }

    set ledgerId(value) {
        this._ledgerId = value;
    }

    get isOpenDisabled() {
        return !this._ledgerId;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOpenFullLedger() {
        if (!this._ledgerId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this._ledgerId,
                objectApiName: 'Work_Order_Ledger__c',
                actionName: 'view'
            }
        });
    }
}
