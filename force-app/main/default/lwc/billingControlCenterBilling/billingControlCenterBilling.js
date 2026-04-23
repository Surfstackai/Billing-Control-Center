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
    modalServiceAppointmentRows = [];
    selectedCount = 0;
    isLoading = true;
    isCompleteBillingModalOpen = false;
    errorMessage;
    /** @type {Promise<void> | null} */
    _loadInFlight = null;

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

    buildModalSelection(rows) {
        return (rows || []).map(row => ({
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
        this.modalServiceAppointmentRows = this.buildModalSelection(this.selectedServiceAppointments);
        this.isCompleteBillingModalOpen = true;
    }

    handleCompleteBillingClose() {
        this.isCompleteBillingModalOpen = false;
        this.modalServiceAppointmentRows = [];
    }

    handleModalSelectionUpdate(event) {
        const remainingRows = (event.detail && event.detail.serviceAppointments) || [];
        const remainingIds = new Set(
            ((event.detail && event.detail.serviceAppointmentIds) || []).filter(Boolean)
        );

        this.modalServiceAppointmentRows = this.buildModalSelection(remainingRows);
        this.selectedServiceAppointments = this.selectedServiceAppointments.filter(row =>
            remainingIds.has(row.serviceAppointmentId)
        );
        this.selectedCount = this.selectedServiceAppointments.length;

        const table = this.template.querySelector('c-billing-control-center-opportunity-table');
        if (table) {
            table.setSelectedServiceAppointmentIds([...remainingIds]);
        }
    }

    async handleCompleteBillingSuccess() {
        this.isCompleteBillingModalOpen = false;
        this.modalServiceAppointmentRows = [];
        this.selectedCount = 0;
        this.selectedServiceAppointments = [];
        await this.loadData();
    }

    async handleRefresh() {
        await this.loadData();
    }

    loadData() {
        if (this._loadInFlight) {
            return this._loadInFlight;
        }
        this._loadInFlight = this.runLoad();
        return this._loadInFlight;
    }

    async runLoad() {
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
            this._loadInFlight = null;
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