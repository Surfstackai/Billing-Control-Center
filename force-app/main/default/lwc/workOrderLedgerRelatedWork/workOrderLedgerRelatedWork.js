import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkOrderLedgerDetail from '@salesforce/apex/BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail';
import assignServiceAppointmentOpportunities from '@salesforce/apex/BillingControl_WorkOrderLedger.assignServiceAppointmentOpportunities';

export default class WorkOrderLedgerRelatedWork extends LightningElement {
    isLoading = false;
    isSaving = false;
    errorMessage;
    detail;
    assignmentDrafts = {};
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.assignmentDrafts = {};
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

    get junctionCount() {
        return (this.detail?.opportunities || []).length;
    }

    get eligibleOpportunities() {
        return this.detail?.eligibleOpportunities || [];
    }

    get eligibleCount() {
        return this.eligibleOpportunities.length;
    }

    get hasMultipleEligible() {
        return this.eligibleCount >= 2;
    }

    get opportunityOptions() {
        return this.eligibleOpportunities.map(row => ({
            label: row.name,
            value: row.opportunityId
        }));
    }

    get hasAppointments() {
        return (this.detail?.appointments || []).length > 0;
    }

    get hasTimeline() {
        return (this.detail?.timeline || []).length > 0;
    }

    get reconciliationBadgeClass() {
        const status = this.detail?.reconciliationStatus || '';
        const needsReview =
            this.detail?.attentionRequired === true || /needs\s*review/i.test(status);
        return needsReview ? 'slds-badge slds-theme_warning' : 'slds-badge';
    }

    get opportunityRows() {
        return (this.detail?.opportunities || []).map(row => ({
            ...row,
            url: row.opportunityId ? `/lightning/r/Opportunity/${row.opportunityId}/view` : null
        }));
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

    get unassignedCount() {
        return this.unassignedAppointments.length;
    }

    get showAssignmentAttention() {
        return this.unassignedCount > 0 && this.hasMultipleEligible;
    }

    get showAttentionBanner() {
        return this.showAssignmentAttention
            || (this.detail?.attentionRequired === true && this.junctionCount === 0);
    }

    get attentionBannerMessage() {
        if (this.showAssignmentAttention) {
            const count = this.unassignedCount;
            const noun = count === 1 ? 'service appointment needs' : 'service appointments need';
            return `${count} ${noun} Opportunity assignment. Select the correct Opportunity for each visit below.`;
        }
        if (this.junctionCount === 0) {
            return this.detail?.attentionReason || 'No Opportunity linked to this Work Order.';
        }
        return this.detail?.attentionReason;
    }

    get hasPendingDrafts() {
        return this.unassignedAppointments.some(row => Boolean(this.assignmentDrafts[row.serviceAppointmentId]));
    }

    get saveAssignmentsDisabled() {
        return this.isSaving || !this.hasPendingDrafts;
    }

    get appointmentGroups() {
        const unassignedCount = this.unassignedCount;
        return [
            {
                key: 'assigned',
                heading: 'Assigned to a job',
                rows: this.assignedAppointments,
                hasRows: this.assignedAppointments.length > 0,
                showHint: false,
                hint: '',
                showSaveAssignments: false
            },
            {
                key: 'unassigned',
                heading: 'Not assigned',
                rows: this.unassignedAppointments,
                hasRows: unassignedCount > 0,
                showHint: unassignedCount > 0,
                hint: `${unassignedCount} visit${unassignedCount === 1 ? '' : 's'} need an Opportunity. Assign each visit to the correct job.`,
                showSaveAssignments: unassignedCount > 0 && this.hasMultipleEligible
            }
        ];
    }

    decorateAppointments(rows) {
        return (rows || []).map(row => {
            const draftOpportunityId = this.assignmentDrafts[row.serviceAppointmentId] || '';
            const showOpportunityPicker = !row.opportunityId && this.hasMultipleEligible;
            return {
                ...row,
                url: row.serviceAppointmentId
                    ? `/lightning/r/ServiceAppointment/${row.serviceAppointmentId}/view`
                    : null,
                opportunityUrl: row.opportunityId
                    ? `/lightning/r/Opportunity/${row.opportunityId}/view`
                    : null,
                showOpportunityLink: Boolean(row.opportunityId),
                showOpportunityPicker,
                draftOpportunityId,
                opportunityOptions: this.opportunityOptions,
                pickerClass: showOpportunityPicker && !draftOpportunityId
                    ? 'slds-has-error ledger-opportunity-picker'
                    : 'ledger-opportunity-picker',
                hasSchedStartTime: Boolean(row.schedStartTime),
                hasActualStartTime: Boolean(row.actualStartTime),
                hasActualEndTime: Boolean(row.actualEndTime)
            };
        });
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

    async loadDetail(ledgerId, options = {}) {
        const silent = options.silent === true;
        if (!silent) {
            this.isLoading = true;
            this.errorMessage = undefined;
            this.detail = undefined;
        }
        try {
            this.detail = await getWorkOrderLedgerDetail({ ledgerId });
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load related work.';
            if (!silent) {
                this.detail = undefined;
            }
        } finally {
            if (!silent) {
                this.isLoading = false;
            }
        }
    }

    handleOpportunityDraftChange(event) {
        const serviceAppointmentId = event.target?.dataset?.saId;
        if (!serviceAppointmentId) {
            return;
        }
        this.assignmentDrafts = {
            ...this.assignmentDrafts,
            [serviceAppointmentId]: event.detail?.value || ''
        };
    }

    async handleSaveAssignments() {
        const assignments = this.unassignedAppointments
            .filter(row => this.assignmentDrafts[row.serviceAppointmentId])
            .map(row => ({
                serviceAppointmentId: row.serviceAppointmentId,
                opportunityId: this.assignmentDrafts[row.serviceAppointmentId]
            }));
        if (!assignments.length || !this.detail?.workOrderId) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const result = await assignServiceAppointmentOpportunities({
                workOrderId: this.detail.workOrderId,
                assignments
            });
            const savedIds = result?.savedIds || [];
            const conflicts = result?.conflicts || [];
            const errors = result?.errors || [];
            const nextDrafts = { ...this.assignmentDrafts };
            savedIds.forEach(savedId => {
                delete nextDrafts[savedId];
            });
            this.assignmentDrafts = nextDrafts;
            this.toastAssignmentResult(savedIds.length, conflicts, errors);
            if (this._recordId) {
                await this.loadDetail(this._recordId, { silent: true });
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to save Opportunity assignments.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Assignments not saved',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    toastAssignmentResult(savedCount, conflicts, errors) {
        const conflictCount = (conflicts || []).length;
        const errorCount = (errors || []).length;
        if (savedCount > 0 && conflictCount === 0 && errorCount === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Assignments saved',
                    message: `${savedCount} visit${savedCount === 1 ? '' : 's'} assigned.`,
                    variant: 'success'
                })
            );
            return;
        }
        const parts = [];
        if (savedCount > 0) {
            parts.push(`${savedCount} saved`);
        }
        if (conflictCount > 0) {
            const names = conflicts
                .map(row => row.appointmentNumber)
                .filter(Boolean)
                .join(', ');
            parts.push(
                names
                    ? `${conflictCount} already assigned (${names})`
                    : `${conflictCount} already assigned`
            );
        }
        if (errorCount > 0) {
            parts.push(`${errorCount} could not be saved`);
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: savedCount > 0 ? 'Some assignments saved' : 'Assignments not saved',
                message: parts.join('. ') + '.',
                variant: savedCount > 0 ? 'warning' : 'error'
            })
        );
    }
}
