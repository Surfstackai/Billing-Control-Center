import { LightningElement, api } from 'lwc';
import getWorkOrderLedgerDetail from '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetail';

export default class WorkOrderLedgerRelatedWork extends LightningElement {
    isLoading = false;
    errorMessage;
    detail;
    showGuidedFlow = false;
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadDetail(value);
        }
    }

    get hasDetail() {
        return Boolean(this.detail?.ledgerId) && !this.isLoading;
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

    get assignOpportunityVariant() {
        return this.detail?.attentionRequired ? 'brand' : 'neutral';
    }

    get guidedFlowInputVariables() {
        const workOrderId = this.detail?.workOrderId;
        if (!workOrderId) {
            return [];
        }
        return [
            {
                name: 'recordId',
                type: 'String',
                value: workOrderId
            }
        ];
    }

    get opportunityRows() {
        return (this.detail?.opportunities || []).map(row => ({
            ...row,
            url: row.opportunityId ? `/lightning/r/Opportunity/${row.opportunityId}/view` : null
        }));
    }

    get appointmentRows() {
        return this.decorateAppointments(this.detail?.appointments || []);
    }

    get assignedAppointments() {
        return this.decorateAppointments(
            (this.detail?.appointments || []).filter(row => row.opportunityId)
        );
    }

    get unassignedAppointments() {
        return this.decorateAppointments(
            (this.detail?.appointments || []).filter(row => !row.opportunityId)
        );
    }

    get appointmentGroups() {
        return [
            {
                key: 'assigned',
                heading: 'Assigned to a job',
                rows: this.assignedAppointments,
                hasRows: this.assignedAppointments.length > 0,
                showHint: false,
                hint: ''
            },
            {
                key: 'unassigned',
                heading: 'Not assigned',
                rows: this.unassignedAppointments,
                hasRows: this.unassignedAppointments.length > 0,
                showHint: this.unassignedAppointments.length > 0,
                hint: 'These visits have no Opportunity on the appointment.'
            }
        ];
    }

    decorateAppointments(rows) {
        return (rows || []).map(row => ({
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
        this.isLoading = true;
        this.errorMessage = undefined;
        this.detail = undefined;
        try {
            this.detail = await getWorkOrderLedgerDetail({ ledgerId });
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load related work.';
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenGuidedFlow() {
        if (!this.detail?.workOrderId) {
            return;
        }
        this.showGuidedFlow = true;
    }

    handleCloseGuidedFlow() {
        this.showGuidedFlow = false;
    }

    async handleGuidedFlowStatus(event) {
        const status = event.detail?.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN' || status === 'ERROR') {
            this.showGuidedFlow = false;
            if (status !== 'ERROR' && this._recordId) {
                await this.loadDetail(this._recordId);
            }
        }
    }
}
