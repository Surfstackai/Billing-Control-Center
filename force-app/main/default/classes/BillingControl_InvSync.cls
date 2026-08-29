/**
 * INV-Sync candidate query and best-effort invoice backfill.
 */
public with sharing class BillingControl_InvSync {
    private static final Integer INV_SYNC_MAX_WARNINGS = 25;
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final List<String> EXCLUDED_INVOICING_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Cannot Complete – Rescheduled'
    };

    private class InvSyncGroup {
        public Id opportunityId;
        public String invoiceNumber;
        public String invoiceType;
        public String digitKey;
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
        Map<Id, List<BillingControl_InvoiceNumberParser.ParsedToken>> tokensByAppointmentId =
            new Map<Id, List<BillingControl_InvoiceNumberParser.ParsedToken>>();
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
            List<BillingControl_InvoiceNumberParser.ParsedToken> parsedTokens =
                resolveInvSyncTokens(appointmentRecord, workOrderRecord);
            if (parsedTokens.isEmpty()) {
                String rawNumber = coalesceInvoiceNumber(appointmentRecord, workOrderRecord);
                if (String.isNotBlank(rawNumber)) {
                    addInvSyncWarning(
                        result,
                        'Skipped '
                        + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                        + ' because "'
                        + rawNumber
                        + '" is not a recognized invoice number.'
                    );
                } else {
                    addInvSyncWarning(
                        result,
                        'Skipped '
                        + coalesceText(appointmentRecord.AppointmentNumber, String.valueOf(appointmentRecord.Id))
                        + ' because no invoice number was found.'
                    );
                }
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
                    + ' because it is not attributed; record the invoice from BCC and choose the Opportunity.'
                );
                continue;
            }
            tokensByAppointmentId.put(appointmentRecord.Id, parsedTokens);
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
        Map<Id, String> stampNumberByAppointmentId = new Map<Id, String>();
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
            List<BillingControl_InvoiceNumberParser.ParsedToken> parsedTokens =
                tokensByAppointmentId.get(appointmentRecord.Id);
            List<String> stampParts = new List<String>();
            for (BillingControl_InvoiceNumberParser.ParsedToken parsedToken : parsedTokens) {
                String canonicalNumber = BillingControl_InvoiceNumberParser.canonicalNumber(parsedToken);
                stampParts.add(canonicalNumber);
                String digitKey = parsedToken.invoiceNumber;
                String groupKey = String.valueOf(opportunityId) + '|' + digitKey;
                InvSyncGroup syncGroup = groupByKey.get(groupKey);
                if (syncGroup == null) {
                    syncGroup = new InvSyncGroup();
                    syncGroup.opportunityId = opportunityId;
                    syncGroup.invoiceNumber = canonicalNumber;
                    syncGroup.invoiceType = parsedToken.type;
                    syncGroup.digitKey = digitKey;
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
            if (!stampParts.isEmpty()) {
                stampNumberByAppointmentId.put(appointmentRecord.Id, String.join(stampParts, ', '));
            }
        }
        if (groupKeys.isEmpty()) {
            return result;
        }

        Set<Id> scopedOpportunityIds = new Set<Id>();
        for (String groupKey : groupKeys) {
            scopedOpportunityIds.add(groupByKey.get(groupKey).opportunityId);
        }
        Set<String> existingInvoiceNumbers = new Set<String>();
        Set<String> existingDigitKeys = new Set<String>();
        for (Invoice__c existingInvoice : [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Opportunity__c IN :scopedOpportunityIds
            AND Status__c != 'Void'
        ]) {
            if (String.isBlank(existingInvoice.Invoice_Number__c)) {
                continue;
            }
            existingInvoiceNumbers.add(existingInvoice.Invoice_Number__c.toLowerCase());
            for (BillingControl_InvoiceNumberParser.ParsedToken parsedToken :
                BillingControl_InvoiceNumberParser.parse(existingInvoice.Invoice_Number__c)
            ) {
                if (parsedToken != null && String.isNotBlank(parsedToken.invoiceNumber)) {
                    existingDigitKeys.add(parsedToken.invoiceNumber);
                }
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        List<InvSyncGroup> groupsToInsert = new List<InvSyncGroup>();
        Set<String> invoiceNumbersInBatch = new Set<String>();
        for (String groupKey : groupKeys) {
            InvSyncGroup syncGroup = groupByKey.get(groupKey);
            if (
                existingInvoiceNumbers.contains(syncGroup.invoiceNumber.toLowerCase())
                || existingDigitKeys.contains(syncGroup.digitKey)
            ) {
                addInvSyncWarning(
                    result,
                    'Skipped invoice number '
                    + syncGroup.invoiceNumber
                    + ' because it already exists on Invoice__c.'
                );
                continue;
            }
            if (invoiceNumbersInBatch.contains(syncGroup.digitKey)) {
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
            invoiceNumbersInBatch.add(syncGroup.digitKey);
            Date invoiceDate = syncGroup.invoiceDate != null ? syncGroup.invoiceDate : Date.today();
            Invoice__c invoiceRecord = BillingControl_InvoiceRecordFactory.buildTypedInvoiceHeader(
                syncGroup.invoiceNumber,
                syncGroup.opportunityId,
                opportunityRecord != null ? opportunityRecord.AccountId : null,
                null,
                invoiceDate,
                null,
                syncGroup.invoiceType,
                'Pending External'
            );
            invoicesToInsert.add(invoiceRecord);
            groupsToInsert.add(syncGroup);
        }

        if (invoicesToInsert.isEmpty()) {
            return result;
        }
        insert invoicesToInsert;
        Set<Id> createdInvoiceIds = new Map<Id, Invoice__c>(invoicesToInsert).keySet();
        BillingControl_InvoiceMath.recalculate(createdInvoiceIds);

        List<Invoice_Line__c> invoiceLinesToInsert = new List<Invoice_Line__c>();
        List<ServiceAppointment> serviceAppointmentsToUpdate = new List<ServiceAppointment>();
        Set<Id> stampedAppointmentIds = new Set<Id>();
        Set<Id> opportunityIdsToUpdate = new Set<Id>();
        for (Integer indexValue = 0; indexValue < groupsToInsert.size(); indexValue++) {
            InvSyncGroup syncGroup = groupsToInsert[indexValue];
            Invoice__c invoiceRecord = invoicesToInsert[indexValue];
            for (ServiceAppointment appointmentRecord : syncGroup.appointments) {
                invoiceLinesToInsert.add(
                    BillingControl_InvoiceRecordFactory.buildServiceAppointmentInvoiceLine(
                        invoiceRecord.Id,
                        appointmentRecord.Id,
                        syncGroup.opportunityId,
                        workOrderIdByAppointmentId.get(appointmentRecord.Id),
                        null
                    )
                );
                if (
                    String.isBlank(appointmentRecord.Invoice_Number__c)
                    && !stampedAppointmentIds.contains(appointmentRecord.Id)
                ) {
                    String stampValue = stampNumberByAppointmentId.get(appointmentRecord.Id);
                    appointmentRecord.Invoice_Number__c = String.isNotBlank(stampValue)
                        ? stampValue
                        : syncGroup.invoiceNumber;
                    serviceAppointmentsToUpdate.add(appointmentRecord);
                    stampedAppointmentIds.add(appointmentRecord.Id);
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

        for (Id opportunityId : opportunityIdsToUpdate) {
            BillingControl_CommissionLifecycle.ensureAccrued(opportunityById.get(opportunityId));
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

    private static List<BillingControl_InvoiceNumberParser.ParsedToken> resolveInvSyncTokens(
        ServiceAppointment appointmentRecord,
        WorkOrder workOrderRecord
    ) {
        if (appointmentRecord != null && String.isNotBlank(appointmentRecord.Invoice_Number__c)) {
            List<BillingControl_InvoiceNumberParser.ParsedToken> appointmentTokens =
                BillingControl_InvoiceNumberParser.parse(appointmentRecord.Invoice_Number__c);
            if (!appointmentTokens.isEmpty()) {
                return appointmentTokens;
            }
        }
        if (workOrderRecord != null && String.isNotBlank(workOrderRecord.Invoice_Number__c)) {
            return BillingControl_InvoiceNumberParser.parse(workOrderRecord.Invoice_Number__c);
        }
        return new List<BillingControl_InvoiceNumberParser.ParsedToken>();
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
