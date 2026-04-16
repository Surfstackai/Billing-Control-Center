import { LightningElement } from 'lwc';

import getServiceAppointmentBillingMetrics from '@salesforce/apex/BillingControl_Invoicing.getServiceAppointmentBillingMetrics';
import getBillableServiceAppointmentGroups from '@salesforce/apex/BillingControl_Invoicing.getBillableServiceAppointmentGroups';

const KPI_CONFIG = [
    {
        key: 'completedMoreThan2Days',
        title: 'Aged Completed Work (>2 Days)',
        icon: 'utility:clock',
        hint: 'Completed service appointments older than 2 days, unbilled.',
        isCurrency: false
    },
    {
        key: 'readyToBill',
        title: 'Billable Service Appointments',
        icon: 'utility:check',
        hint: 'Completed and unbilled service appointments.',
        isCurrency: false
    },
    {
        key: 'unbilledRevenue',
        title: 'Uninvoiced Revenue',
        icon: 'utility:money',
        hint: 'Derived from service appointment billable amounts.',
        isCurrency: true
    }
];

export default class BillingControlCenterBilling extends LightningElement {
    metrics = {};
    appointmentGroups = [];
    selectedServiceAppointments = [];
    selectedCount = 0;
    isLoading = true;
    isCompleteBillingModalOpen = false;
    errorMessage;

    connectedCallback() {
        this.loadData();
    }

    get kpiTiles() {
        return KPI_CONFIG.map(tile => ({
            ...tile,
            value: this.metrics[tile.key] || 0,
            countText: 'Service Appointments'
        }));
    }

    get isCompleteBillingDisabled() {
        return this.selectedCount === 0;
    }

    get completeBillingModalSelections() {
        return this.selectedServiceAppointments.map(row => ({
            serviceAppointmentId: row.serviceAppointmentId,
            serviceAppointmentNumber: row.serviceAppointmentNumber,
            opportunityId: row.opportunityId,
            opportunityName: row.opportunityName,
            accountName: row.accountName,
            workOrderNumber: row.workOrderNumber,
            completionDateTime: row.completionDateTime,
            technicianName: row.technicianName,
            billableAmount: row.billableAmount
        }));
    }

    get billableCount() {
        return this.appointmentGroups.reduce(
            (sum, group) => sum + (group.serviceAppointmentCount || 0),
            0
        );
    }

    handleSelectionChange(event) {
        this.selectedCount = event.detail.selectedCount || 0;
        this.selectedServiceAppointments = event.detail.selectedRows || [];
    }

    handleOpenCompleteBillingModal() {
        if (this.isCompleteBillingDisabled) {
            return;
        }
        this.isCompleteBillingModalOpen = true;
    }

    handleCompleteBillingClose() {
        this.isCompleteBillingModalOpen = false;
    }

    async handleCompleteBillingSuccess() {
        this.isCompleteBillingModalOpen = false;
        this.selectedCount = 0;
        this.selectedServiceAppointments = [];
        await this.loadData();
    }

    async handleRefresh() {
        await this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const [metrics, groups] = await Promise.all([
                getServiceAppointmentBillingMetrics(),
                getBillableServiceAppointmentGroups()
            ]);

            this.metrics = metrics || {};
            this.appointmentGroups = groups || [];
        } catch (error) {
            this.metrics = {};
            this.appointmentGroups = [];
            this.selectedServiceAppointments = [];
            this.selectedCount = 0;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
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

