import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';

export default class ServiceAppointmentNewRedirect extends NavigationMixin(LightningElement) {
    @api workOrderId;
    @api opportunityId;
    @api availableActions = [];

    hasNavigated = false;

    renderedCallback() {
        if (this.hasNavigated || !this.workOrderId) {
            return;
        }

        this.hasNavigated = true;

        const defaults = {
            ParentRecordId: this.workOrderId
        };

        if (this.opportunityId) {
            defaults.Opportunity__c = this.opportunityId;
        }

        const defaultFieldValues = encodeDefaultFieldValues(defaults);

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'ServiceAppointment',
                actionName: 'new'
            },
            state: {
                defaultFieldValues,
                nooverride: '1',
                useRecordTypeCheck: '1'
            }
        });

        if (this.availableActions.includes('FINISH')) {
            window.setTimeout(() => {
                this.dispatchEvent(new FlowNavigationFinishEvent());
            }, 0);
        }
    }
}