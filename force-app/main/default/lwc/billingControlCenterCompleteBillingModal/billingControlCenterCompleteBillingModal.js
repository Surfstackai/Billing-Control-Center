import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import completeServiceAppointmentBilling from '@salesforce/apex/BillingControl_Invoicing.completeServiceAppointmentBilling';

export default class BillingControlCenterCompleteBillingModal extends LightningElement {
    localServiceAppointments = [];
    opportunityGroups = [];
    isSaving = false;
    hasReviewedGroupedBilling = false;
    errorMessage;

    @api
    set serviceAppointments(value) {
        this.localServiceAppointments = (value || []).map(row => ({ ...row }));
        this.isSaving = false;
        this.hasReviewedGroupedBilling = false;
        this.errorMessage = undefined;
        this.rebuildOpportunityGroups();
    }

    get serviceAppointments() {
        return this.localServiceAppointments;
    }

    rebuildOpportunityGroups() {
        const mapByOpportunity = new Map();
        for (const row of this.localServiceAppointments) {
            const key = row.opportunityId || 'NO_OPP';
            if (!mapByOpportunity.has(key)) {
                mapByOpportunity.set(key, {
                    rowKey: key,
                    opportunityId: row.opportunityId,
                    opportunityName: row.opportunityName,
                    accountName: row.accountName,
                    count: 0,
                    totalBillableAmount: 0,
                    appointments: [],
                    invoiceNumber: ''
                });
            }
            const group = mapByOpportunity.get(key);
            group.count += 1;
            group.totalBillableAmount += row.billableAmount || 0;
            group.appointments.push(row);
        }

        this.opportunityGroups = Array.from(mapByOpportunity.values())
            .map(group => ({
                ...group,
                hasMultipleAppointments: group.count > 1,
                invoiceSummary: group.count > 1
                    ? `${group.count} service appointments will be consolidated into one invoice.`
                    : '1 service appointment will create one invoice.'
            }))
            .sort((left, right) =>
                String(left.opportunityName || '').localeCompare(String(right.opportunityName || ''))
            );
    }

    get selectedCount() {
        return this.localServiceAppointments.length;
    }

    get totalBillableAmount() {
        return this.localServiceAppointments.reduce(
            (sum, row) => sum + (row.billableAmount || 0),
            0
        );
    }

    get selectedOpportunityCount() {
        return this.opportunityGroups.length;
    }

    get invoiceGroupCount() {
        return this.opportunityGroups.length;
    }

    get multiAppointmentGroupCount() {
        return this.opportunityGroups.filter(group => group.hasMultipleAppointments).length;
    }

    get hasMultiAppointmentGroups() {
        return this.multiAppointmentGroupCount > 0;
    }

    get hasAllInvoiceNumbers() {
        const billableGroups = this.opportunityGroups.filter(
            group => group.opportunityId && group.opportunityId !== 'NO_OPP'
        );
        if (billableGroups.length === 0) {
            return false;
        }
        return billableGroups.every(
            group => (group.invoiceNumber || '').trim().length > 0
        );
    }

    get isCompleteDisabled() {
        return this.isSaving
            || this.selectedCount === 0
            || (this.hasMultiAppointmentGroups && !this.hasReviewedGroupedBilling)
            || !this.hasAllInvoiceNumbers;
    }

    handleGroupedBillingReviewChange(event) {
        this.hasReviewedGroupedBilling = event.target.checked;
    }

    handleInvoiceNumberChange(event) {
        const opportunityId = event.target.dataset.opportunityId;
        const value = event.target.value;
        this.opportunityGroups = this.opportunityGroups.map(group => {
            if (group.opportunityId === opportunityId) {
                return { ...group, invoiceNumber: value };
            }
            return group;
        });
    }

    handleCancel() {
        if (this.isSaving) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleCompleteBilling() {
        if (this.isCompleteDisabled) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = undefined;

        try {
            const serviceAppointmentIds = this.localServiceAppointments
                .map(row => row.serviceAppointmentId)
                .filter(Boolean);

            const invoiceNumberByOpportunityId = {};
            for (const group of this.opportunityGroups) {
                if (group.opportunityId && group.opportunityId !== 'NO_OPP') {
                    invoiceNumberByOpportunityId[group.opportunityId] = (group.invoiceNumber || '').trim();
                }
            }

            const result = await completeServiceAppointmentBilling({
                serviceAppointmentIds,
                invoiceNumberByOpportunityId
            });
            const invoicesCreated = result?.invoicesCreated || 0;
            const serviceAppointmentsUpdated = result?.serviceAppointmentsUpdated || 0;

            this.dispatchEvent(new ShowToastEvent({
                title: 'Billing completed',
                message: `${serviceAppointmentsUpdated} service appointment(s) billed across ${invoicesCreated} invoice group(s).`,
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('success', { detail: result }));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Billing not completed',
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