import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class WorkOrderLedgerQuickView extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
