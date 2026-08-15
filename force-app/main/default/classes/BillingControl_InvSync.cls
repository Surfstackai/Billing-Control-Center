/**
 * INV-Sync candidate query and best-effort invoice backfill.
 */
public with sharing class BillingControl_InvSync {
    private static final Integer INV_SYNC_MAX_WARNINGS = 25;
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final List<String> EXCLUDED_INVOICING_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Billing Completed',
        'Cannot Complete – Rescheduled'
    };

    private class InvSyncGroup {
        public Id opportunityId;
        public String invoiceNumber;
        public Date invoiceDate;
        public List<ServiceAppointment> appointments;
    }

    public static BillingControl_Invoicing.InvSyncResultWrapper executeInvSyncNow(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        return processInvSyncAppointments(queryInvSyncCandidateAppointments(dateFilter), opportunityOwnerId);
    }

    public static List<ServiceAppointment> queryInvSyncCandidateAppointments(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter
    ) {
        BillingControl_DataProvider.DateRangeDTO range =
            BillingControl_DataProvider.resolveDateRangeForInvSync(dateFilter);
        if (range == null || range.startDate == null || range.endDate == null) {
            return new List<ServiceAppointment>();
        }
        Datetime rangeStart = Datetime.newInstance(range.startDate, Time.newInstance(0, 0, 0, 0));
        Datetime rangeEndExclusive = Datetime.newInstance(range.endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
        List<ServiceAppointment> candidates = new List<ServiceAppointment>();
        Set<Id> seenAppointmentIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                Invoice_Number__c,
                WO_Inv_Status__c,
                Opportunity__c,
                Opportunity__r.OwnerId,
                ParentRecordId,
                Status,
                ActualEndTime,
                AppointmentNumber
            FROM ServiceAppointment
            WHERE Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND ActualEndTime >= :rangeStart
            AND ActualEndTime < :rangeEndExclusive
            AND ParentRecordId IN (
                SELECT Id
                FROM WorkOrder
                WHERE Status NOT IN :EXCLUDED_INVOICING_WORK_ORDER_STATUSES
            )
            ORDER BY ActualEndTime ASC NULLS LAST, AppointmentNumber ASC NULLS LAST
            LIMIT 500
        ]) {
            if (seenAppointmentIds.add(appointmentRecord.Id)) {
                candidates.add(appointmentRecord);
            }
        }
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                Invoice_Number__c,
                WO_Inv_Status__c,
                Opportunity__c,
                Opportunity__r.OwnerId,
                ParentRecordId,
                Status,
                ActualEndTime,
                AppointmentNumber
            FROM ServiceAppointment
            WHERE Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND ActualEndTime >= :rangeStart
            AND ActualEndTime < :rangeEndExclusive
            AND ParentRecordId IN (
                SELECT Id
                FROM WorkOrderLineItem
                WHERE WorkOrder.Status NOT IN :EXCLUDED_INVOICING_WORK_ORDER_STATUSES
            )
            ORDER BY ActualEndTime ASC NULLS LAST, AppointmentNumber ASC NULLS LAST
            LIMIT 500
        ]) {
            if (seenAppointmentIds.add(appointmentRecord.Id)) {
                candidates.add(appointmentRecord);
            }
        }
        return candidates;
    }

    public static BillingControl_Invoicing.InvSyncResultWrapper processInvSyncAppointments(
        List<ServiceAppointment> appointments,
        String opportunityOwnerId
    ) {
        BillingControl_Invoicing.InvSyncResultWrapper result = new BillingControl_Invoicing.InvSyncResultWrapper();
        result.invoicesCreated = 0;
        result.serviceAppointmentsUpdated = 0;
        result.skippedCount = 0;
        result.queued = false;
        result.warnings = new List<String>();
        if (appointments == null || appointments.isEmpty()) {
            return result;
        }

        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(appointments);
        Map<Id, WorkOrder> workOrderById = BillingControl_Invoicing.queryWorkOrdersById(new Set<Id>(workOrderIdByAppointmentId.values()));
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId =
            BillingControl_Invoicing.queryJunctionsByWorkOrderId(new Set<Id>(workOrderIdByAppointmentId.values()));

        Map<Id, Id> opportunityIdByAppointmentId = new Map<Id, Id>();
        Map<Id, String> invoiceNumberByAppointmentId = new Map<Id, String>();
        List<ServiceAppointment> eligibleAppointments = new List<ServiceAppointment>();
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord == null || appointmentRecord.Status != SERVICE_APPOINTMENT_STATUS_COMPLETED) {
                addInvSyncWarning(result, 'Skipped an appointment that is not completed.');
                continue;
            }
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            WorkOrder workOrderRecord = workOrderId != null ? workOrderById.get(workOrderId) : null;
            if (workOrderRecord != null) {
                if (EXCLUDED_INVOICING_WORK_ORDER_STATUSES.contains(workOrderRecord.Status)) {
                    addInvSyncWarning(
                        result,
                        'Skipped '
                        + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                        + ' because the Work Order status is excluded from invoicing.'
                    );
                    continue;
                }
                if (
                    workOrderRecord.Parent_Account__r != null
                    && BillingControl_Invoicing.containsExcludedInvoicingMarkerForAccount(workOrderRecord.Parent_Account__r.Name)
                ) {
                    addInvSyncWarning(
                        result,
                        'Skipped '
                        + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                        + ' because the parent account is excluded from invoicing.'
                    );
                    continue;
                }
            }
            String invoiceNumber = coalesceInvoiceNumber(appointmentRecord, workOrderRecord);
            if (!BillingControl_Invoicing.containsExcludedInvoicingMarker(invoiceNumber)) {
                continue;
            }
            Id opportunityId = BillingControl_Attribution.resolveAttributedOpportunityId(
                appointmentRecord,
                junctionsByWorkOrderId.get(workOrderId)
            );
            if (opportunityId == null) {
                addInvSyncWarning(
                    result,
                    'Skipped '
                    + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                    + ' because it is not attributed to a single Opportunity.'
                );
                continue;
            }
            invoiceNumberByAppointmentId.put(appointmentRecord.Id, invoiceNumber.trim());
            opportunityIdByAppointmentId.put(appointmentRecord.Id, opportunityId);
            eligibleAppointments.add(appointmentRecord);
        }
        if (eligibleAppointments.isEmpty()) {
            return result;
        }

        Set<Id> opportunityIds = new Set<Id>(opportunityIdByAppointmentId.values());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, AccountId, Amount, Billing_Status__c, OwnerId
            FROM Opportunity
            WHERE Id IN :opportunityIds
            FOR UPDATE
        ]);
        Id ownerFilterId = String.isBlank(opportunityOwnerId) ? null : (Id) opportunityOwnerId;
        List<ServiceAppointment> scopedAppointments = new List<ServiceAppointment>();
        for (ServiceAppointment appointmentRecord : eligibleAppointments) {
            Id opportunityId = opportunityIdByAppointmentId.get(appointmentRecord.Id);
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            if (ownerFilterId != null && (opportunityRecord == null || opportunityRecord.OwnerId != ownerFilterId)) {
                continue;
            }
            scopedAppointments.add(appointmentRecord);
        }
        if (scopedAppointments.isEmpty()) {
            return result;
        }

        Set<Id> scopedAppointmentIds = new Map<Id, ServiceAppointment>(scopedAppointments).keySet();
        Set<Id> alreadyInvoicedAppointmentIds = new Set<Id>();
        for (Invoice_Line__c invoiceLineRecord : [
            SELECT Service_Appointment__c
            FROM Invoice_Line__c
            WHERE Service_Appointment__c IN :scopedAppointmentIds
        ]) {
            if (invoiceLineRecord.Service_Appointment__c != null) {
                alreadyInvoicedAppointmentIds.add(invoiceLineRecord.Service_Appointment__c);
            }
        }

        Map<String, InvSyncGroup> groupByKey = new Map<String, InvSyncGroup>();
        List<String> groupKeys = new List<String>();
        for (ServiceAppointment appointmentRecord : scopedAppointments) {
            if (alreadyInvoicedAppointmentIds.contains(appointmentRecord.Id)) {
                addInvSyncWarning(
                    result,
                    'Skipped '
                    + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                    + ' because it already has an invoice line.'
                );
                continue;
            }
            Id opportunityId = opportunityIdByAppointmentId.get(appointmentRecord.Id);
            String invoiceNumber = invoiceNumberByAppointmentId.get(appointmentRecord.Id);
            String groupKey = String.valueOf(opportunityId) + '|' + invoiceNumber.toLowerCase();
            InvSyncGroup syncGroup = groupByKey.get(groupKey);
            if (syncGroup == null) {
                syncGroup = new InvSyncGroup();
                syncGroup.opportunityId = opportunityId;
                syncGroup.invoiceNumber = invoiceNumber;
                syncGroup.appointments = new List<ServiceAppointment>();
                groupByKey.put(groupKey, syncGroup);
                groupKeys.add(groupKey);
            }
            syncGroup.appointments.add(appointmentRecord);
            Date appointmentDate = appointmentRecord.ActualEndTime != null
                ? appointmentRecord.ActualEndTime.date()
                : null;
            if (appointmentDate != null && (syncGroup.invoiceDate == null || appointmentDate < syncGroup.invoiceDate)) {
                syncGroup.invoiceDate = appointmentDate;
            }
        }
        if (groupKeys.isEmpty()) {
            return result;
        }

        Set<String> requestedInvoiceNumbers = new Set<String>();
        for (String groupKey : groupKeys) {
            requestedInvoiceNumbers.add(groupByKey.get(groupKey).invoiceNumber);
        }
        Set<String> existingInvoiceNumbers = new Set<String>();
        for (Invoice__c existingInvoice : [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Invoice_Number__c IN :requestedInvoiceNumbers
        ]) {
            if (String.isNotBlank(existingInvoice.Invoice_Number__c)) {
                existingInvoiceNumbers.add(existingInvoice.Invoice_Number__c.toLowerCase());
            }
        }

        Map<Id, Decimal> historicalInvoiceTotalByOpportunityId = BillingControl_Invoicing.queryHistoricalInvoiceTotalByOpportunityId(opportunityIds);
        Map<Id, Decimal> remainingAmountByOpportunityId = new Map<Id, Decimal>();
        for (Id opportunityId : opportunityIds) {
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            Decimal opportunityAmount = opportunityRecord != null ? opportunityRecord.Amount : null;
            Decimal historicalTotal = historicalInvoiceTotalByOpportunityId.containsKey(opportunityId)
                ? historicalInvoiceTotalByOpportunityId.get(opportunityId)
                : 0;
            remainingAmountByOpportunityId.put(
                opportunityId,
                (opportunityAmount != null ? opportunityAmount : 0) - historicalTotal
            );
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        List<InvSyncGroup> groupsToInsert = new List<InvSyncGroup>();
        Map<Id, Decimal> invoiceLineAmountByAppointmentId = new Map<Id, Decimal>();
        Set<String> invoiceNumbersInBatch = new Set<String>();
        for (String groupKey : groupKeys) {
            InvSyncGroup syncGroup = groupByKey.get(groupKey);
            if (existingInvoiceNumbers.contains(syncGroup.invoiceNumber.toLowerCase())) {
                addInvSyncWarning(
                    result,
                    'Skipped invoice number '
                    + syncGroup.invoiceNumber
                    + ' because it already exists on Invoice__c.'
                );
                continue;
            }
            if (invoiceNumbersInBatch.contains(syncGroup.invoiceNumber.toLowerCase())) {
                addInvSyncWarning(
                    result,
                    'Skipped duplicate invoice number '
                    + syncGroup.invoiceNumber
                    + ' in this INV-Sync run.'
                );
                continue;
            }
            if (syncGroup.invoiceNumber.length() > 80) {
                addInvSyncWarning(
                    result,
                    'Skipped invoice number '
                    + syncGroup.invoiceNumber
                    + ' because it exceeds 80 characters.'
                );
                continue;
            }
            Opportunity opportunityRecord = opportunityById.get(syncGroup.opportunityId);
            Decimal opportunityAmount = opportunityRecord != null ? opportunityRecord.Amount : null;
            if (opportunityAmount == null || opportunityAmount <= 0) {
                addInvSyncWarning(
                    result,
                    'Skipped Opportunity '
                    + String.valueOf(syncGroup.opportunityId)
                    + ' because Amount must be greater than 0.'
                );
                continue;
            }
            Decimal remainingAmount = remainingAmountByOpportunityId.containsKey(syncGroup.opportunityId)
                ? remainingAmountByOpportunityId.get(syncGroup.opportunityId)
                : 0;
            if (remainingAmount <= 0) {
                addInvSyncWarning(
                    result,
                    'Skipped Opportunity '
                    + String.valueOf(syncGroup.opportunityId)
                    + ' because it is already fully invoiced.'
                );
                continue;
            }

            invoiceNumbersInBatch.add(syncGroup.invoiceNumber.toLowerCase());
            remainingAmountByOpportunityId.put(syncGroup.opportunityId, 0);
            invoiceLineAmountByAppointmentId.putAll(
                BillingControl_Invoicing.allocateInvoiceTotalAcrossAppointments(remainingAmount, syncGroup.appointments)
            );
            Date invoiceDate = syncGroup.invoiceDate != null ? syncGroup.invoiceDate : Date.today();
            Invoice__c invoiceRecord = BillingControl_InvoiceRecordFactory.buildSentInvoiceHeader(
                syncGroup.invoiceNumber,
                syncGroup.opportunityId,
                opportunityRecord.AccountId,
                remainingAmount,
                invoiceDate
            );
            invoicesToInsert.add(invoiceRecord);
            groupsToInsert.add(syncGroup);
        }

        if (invoicesToInsert.isEmpty()) {
            return result;
        }
        insert invoicesToInsert;

        List<Invoice_Line__c> invoiceLinesToInsert = new List<Invoice_Line__c>();
        List<ServiceAppointment> serviceAppointmentsToUpdate = new List<ServiceAppointment>();
        Set<Id> opportunityIdsToUpdate = new Set<Id>();
        for (Integer indexValue = 0; indexValue < groupsToInsert.size(); indexValue++) {
            InvSyncGroup syncGroup = groupsToInsert[indexValue];
            Invoice__c invoiceRecord = invoicesToInsert[indexValue];
            for (ServiceAppointment appointmentRecord : syncGroup.appointments) {
                Decimal invoiceLineAmount = invoiceLineAmountByAppointmentId.get(appointmentRecord.Id);
                invoiceLinesToInsert.add(
                    BillingControl_InvoiceRecordFactory.buildServiceAppointmentInvoiceLine(
                        invoiceRecord.Id,
                        appointmentRecord.Id,
                        syncGroup.opportunityId,
                        workOrderIdByAppointmentId.get(appointmentRecord.Id),
                        invoiceLineAmount
                    )
                );
                Boolean stampInvoiceNumber = String.isBlank(appointmentRecord.Invoice_Number__c);
                Boolean stampOpportunity = appointmentRecord.Opportunity__c == null;
                if (stampInvoiceNumber || stampOpportunity) {
                    if (stampInvoiceNumber) {
                        appointmentRecord.Invoice_Number__c = syncGroup.invoiceNumber;
                    }
                    if (stampOpportunity) {
                        appointmentRecord.Opportunity__c = syncGroup.opportunityId;
                    }
                    serviceAppointmentsToUpdate.add(appointmentRecord);
                }
            }
            opportunityIdsToUpdate.add(syncGroup.opportunityId);
        }

        if (!invoiceLinesToInsert.isEmpty()) {
            insert invoiceLinesToInsert;
        }
        if (!serviceAppointmentsToUpdate.isEmpty()) {
            update serviceAppointmentsToUpdate;
        }

        String billedStatusForUpdate = BillingControl_Invoicing.getOutstandingReceivableStatusForUpdate();
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        for (Id opportunityId : opportunityIdsToUpdate) {
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            if (opportunityRecord == null) {
                continue;
            }
            if (
                opportunityRecord.Billing_Status__c == billedStatusForUpdate
                || opportunityRecord.Billing_Status__c == PAID
                || opportunityRecord.Billing_Status__c == PARTIALLY_PAID
                || BillingControl_Invoicing.isOutstandingReceivableStatus(opportunityRecord.Billing_Status__c)
            ) {
                continue;
            }
            opportunitiesToUpdate.add(new Opportunity(
                Id = opportunityId,
                Billing_Status__c = billedStatusForUpdate
            ));
        }
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }

        result.invoicesCreated = invoicesToInsert.size();
        result.serviceAppointmentsUpdated = serviceAppointmentsToUpdate.size();
        return result;
    }

    public static void addInvSyncWarning(BillingControl_Invoicing.InvSyncResultWrapper result, String message) {
        if (result == null) {
            return;
        }
        result.skippedCount = result.skippedCount == null ? 1 : result.skippedCount + 1;
        if (result.warnings == null) {
            result.warnings = new List<String>();
        }
        if (String.isBlank(message) || result.warnings.size() >= INV_SYNC_MAX_WARNINGS) {
            return;
        }
        result.warnings.add(message);
    }

    private static String coalesceText(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }

    public static String coalesceInvoiceNumber(
        ServiceAppointment appointmentRecord,
        WorkOrder workOrderRecord
    ) {
        if (appointmentRecord != null && String.isNotBlank(appointmentRecord.Invoice_Number__c)) {
            return appointmentRecord.Invoice_Number__c;
        }
        if (workOrderRecord != null && String.isNotBlank(workOrderRecord.Invoice_Number__c)) {
            return workOrderRecord.Invoice_Number__c;
        }
        return appointmentRecord != null ? appointmentRecord.WO_Inv_Status__c : null;
    }

}
