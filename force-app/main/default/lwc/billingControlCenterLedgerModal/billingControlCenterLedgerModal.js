import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getWorkOrderLedgerDetailForRange from '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetailForRange';

export default class BillingControlCenterLedgerModal extends NavigationMixin(LightningElement) {
    @api embedded = false;
    isLoading = false;
    errorMessage;
    detail;
    _ledgerId;
    _dateFilter;
    _isConnected = false;
    _loadSequence = 0;

    @api
    get dateFilter() {
        return this._dateFilter;
    }

    set dateFilter(value) {
        this._dateFilter = value;
        this.loadIfReady();
    }

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
        this.loadIfReady();
    }

    connectedCallback() {
        this._isConnected = true;
        this.loadIfReady();
    }

    loadIfReady() {
        if (!this._isConnected || !this._ledgerId) {
            return;
        }
        this.loadDetail(this._ledgerId);
    }

    get hasDetail() {
        return Boolean(this.detail?.ledgerId) && !this.isLoading;
    }

    get isOpenDisabled() {
        return !this.detail?.ledgerId;
    }

    get accountUrl() {
        return this.detail?.accountId ? `/lightning/r/Account/${this.detail.accountId}/view` : null;
    }

    get workOrderUrl() {
        return this.detail?.workOrderId ? `/lightning/r/WorkOrder/${this.detail.workOrderId}/view` : null;
    }

    get hasOpportunities() {
        return (this.detail?.opportunities || []).length > 0;
    }

    get hasAppointments() {
        return (this.detail?.appointments || []).length > 0;
    }

    get hasTimeline() {
        return (this.detail?.timeline || []).length > 0;
    }

    get opportunityRows() {
        return (this.detail?.opportunities || []).map(row => ({
            ...row,
            url: row.opportunityId ? `/lightning/r/Opportunity/${row.opportunityId}/view` : null
        }));
    }

    get appointmentRows() {
        return (this.detail?.appointments || []).map(row => ({
            ...row,
            url: row.serviceAppointmentId
                ? `/lightning/r/ServiceAppointment/${row.serviceAppointmentId}/view`
                : null,
            hasSchedStartTime: Boolean(row.schedStartTime),
            hasActualStartTime: Boolean(row.actualStartTime),
            hasActualEndTime: Boolean(row.actualEndTime)
        }));
    }

    get timelineRows() {
        return (this.detail?.timeline || []).map((entry, index) => {
            const description = entry.description || '';
            return {
                ...entry,
                entryKey: `${entry.eventDatetime || 'na'}-${entry.eventType || 'event'}-${index}`,
                descriptionText: description,
                hasEventDatetime: Boolean(entry.eventDatetime)
            };
        });
    }

    async loadDetail(ledgerId) {
        this._loadSequence += 1;
        const loadSequence = this._loadSequence;
        this.isLoading = true;
        this.errorMessage = undefined;
        this.detail = undefined;
        try {
            const runtimeDetail = await getWorkOrderLedgerDetailForRange({
                ledgerId,
                dateFilter: this._dateFilter
                    ? {
                          filterKey: this._dateFilter.filterKey || null,
                          startDate: this._dateFilter.startDate || null,
                          endDate: this._dateFilter.endDate || null
                      }
                    : null
            });
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.detail = runtimeDetail;
        } catch (error) {
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load ledger detail.';
        } finally {
            if (loadSequence === this._loadSequence) {
                this.isLoading = false;
            }
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOpenFullLedger() {
        if (!this.detail?.ledgerId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.detail.ledgerId,
                objectApiName: 'Work_Order_Ledger__c',
                actionName: 'view'
            }
        });
    }
}
