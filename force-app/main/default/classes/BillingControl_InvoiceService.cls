/**
 * Opportunity-scoped invoice creation. Financial attribution lives on Invoice__c /
 * Invoice_Line__c. ServiceAppointment.Opportunity__c is written only when opted in.
 */
public with sharing class BillingControl_InvoiceService {
    private static final String TYPE_DEPOSIT = 'Deposit';
    private static final String TYPE_BALANCE = 'Balance';
    private static final String TYPE_ADJUSTMENT = 'Adjustment';
    private static final String TYPE_PROGRESS = 'Progress';
    private static final Set<String> VALID_INVOICE_TYPES = new Set<String>{
        TYPE_DEPOSIT, TYPE_BALANCE, TYPE_ADJUSTMENT, TYPE_PROGRESS
    };
    private static final String SOURCE_ENTERED = 'Entered';
    private static final String SOURCE_DERIVED = 'Derived';
    private static final String SOURCE_PENDING_EXTERNAL = 'Pending External';
    private static final String STATUS_VOID = 'Void';
    private static final String STATUS_PAID = 'Paid';
    private static final String STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String STATUS_COMPLETED = 'Completed';

    public class InvoiceRequest {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String invoiceType;
        @AuraEnabled public Decimal invoiceAmount;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public Date invoiceDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public List<Id> serviceAppointmentIds;
        @AuraEnabled public Boolean acceptFullRemaining;
        @AuraEnabled public Boolean acceptVariance;
        @AuraEnabled public Boolean amountPendingExternal;
        @AuraEnabled public Boolean updateOperationalAttribution;
        @AuraEnabled public String amountSource;
    }

    public class InvoiceResult {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String invoiceType;
        @AuraEnabled public Decimal invoiceAmount;
        @AuraEnabled public String varianceWarning;
        @AuraEnabled public Boolean operationalAttributionUpdated;
    }

    public class OpportunityCandidate {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String name;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal suggestedAmount;
        @AuraEnabled public Decimal remainingAmount;
    }

    public class InvoiceDefaults {
        @AuraEnabled public Decimal suggestedAmount;
        @AuraEnabled public Decimal remainingAmount;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public Decimal invoicedTotal;
        @AuraEnabled public Decimal depositAmountRequired;
        @AuraEnabled public Decimal depositPercent;
    }

    public class VisitInvoiceContext {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Id ledgerId;
        @AuraEnabled public Boolean unassigned;
    }

    @AuraEnabled
    public static InvoiceResult createInvoice(InvoiceRequest request) {
        if (request == null || request.opportunityId == null) {
            throw BillingControl_Invoicing.buildHandledException('An Opportunity is required to create an invoice.');
        }
        String invoiceType = request.invoiceType == null ? null : request.invoiceType.trim();
        if (!VALID_INVOICE_TYPES.contains(invoiceType)) {
            throw BillingControl_Invoicing.buildHandledException(
                'Invoice type must be Deposit, Balance, Adjustment, or Progress.'
            );
        }

        Boolean pendingExternal = request.amountPendingExternal == true;
        Boolean acceptFullRemaining = request.acceptFullRemaining == true;
        Boolean acceptVariance = request.acceptVariance == true;
        Boolean updateOperationalAttribution = request.updateOperationalAttribution == true;

        List<Opportunity> opportunityRows = [
            SELECT Id,
                Name,
                AccountId,
                Amount,
                OwnerId,
                Billing_Status__c,
                Deposit_Amount_Required__c,
                Deposit_Percent__c,
                Deposit_Required__c
            FROM Opportunity
            WHERE Id = :request.opportunityId
            FOR UPDATE
        ];
        if (opportunityRows.isEmpty()) {
            throw BillingControl_Invoicing.buildHandledException('The selected Opportunity was not found or is not accessible.');
        }
        Opportunity opportunityRecord = opportunityRows[0];

        String invoiceNumber = resolveInvoiceNumber(request.invoiceNumber, opportunityRecord.Id);
        Decimal invoiceAmount = pendingExternal ? null : request.invoiceAmount;
        if (!pendingExternal) {
            if (invoiceAmount == null || invoiceAmount <= 0) {
                throw BillingControl_Invoicing.buildHandledException('Invoice amount must be greater than 0.');
            }
            invoiceAmount = invoiceAmount.setScale(2, RoundingMode.HALF_UP);
        }

        BillingControl_OpportunityFinancials.Snapshot financials =
            BillingControl_OpportunityFinancials.load(new Set<Id>{ opportunityRecord.Id }).get(opportunityRecord.Id);
        Decimal invoicedTotal = financials == null ? 0 : financials.invoicedTotal;
        Decimal opportunityAmount = opportunityRecord.Amount;
        Decimal remainingAmount = remainingToInvoice(opportunityAmount, invoicedTotal);

        String varianceWarning;
        if (!pendingExternal && opportunityAmount != null && opportunityAmount > 0) {
            if (invoiceAmount == remainingAmount && remainingAmount > 0 && !acceptFullRemaining) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Confirm that this invoice should bill the full remaining Opportunity amount.'
                );
            }
            if (invoicedTotal + invoiceAmount > opportunityAmount) {
                if (!acceptVariance) {
                    throw BillingControl_Invoicing.buildHandledException(
                        'Invoice amount exceeds the Opportunity amount. Confirm the variance to continue.'
                    );
                }
                varianceWarning =
                    'Invoice amount exceeds Opportunity.Amount ('
                    + String.valueOf(opportunityAmount)
                    + ').';
            }
        }

        List<ServiceAppointment> evidenceAppointments = loadAndValidateAppointments(
            request.serviceAppointmentIds,
            opportunityRecord.Id
        );
        Map<Id, Id> workOrderIdByAppointmentId =
            BillingControl_Attribution.resolveWorkOrderIdsForAppointments(evidenceAppointments);

        String amountSource = pendingExternal
            ? SOURCE_PENDING_EXTERNAL
            : (String.isBlank(request.amountSource) ? SOURCE_ENTERED : request.amountSource.trim());

        Invoice__c invoiceRecord = BillingControl_InvoiceRecordFactory.buildTypedInvoiceHeader(
            invoiceNumber,
            opportunityRecord.Id,
            opportunityRecord.AccountId,
            invoiceAmount,
            request.invoiceDate,
            request.dueDate,
            invoiceType,
            amountSource
        );
        insert invoiceRecord;

        List<Invoice_Line__c> linesToInsert = new List<Invoice_Line__c>();
        if (evidenceAppointments.isEmpty()) {
            linesToInsert.add(
                BillingControl_InvoiceRecordFactory.buildDescriptiveInvoiceLine(
                    invoiceRecord.Id,
                    opportunityRecord.Id,
                    null,
                    descriptiveLineText(invoiceType, opportunityRecord),
                    invoiceAmount
                )
            );
        } else {
            Map<Id, Decimal> amountByAppointmentId = pendingExternal
                ? new Map<Id, Decimal>()
                : BillingControl_Invoicing.allocateInvoiceTotalAcrossAppointments(invoiceAmount, evidenceAppointments);
            for (ServiceAppointment appointmentRecord : evidenceAppointments) {
                linesToInsert.add(
                    BillingControl_InvoiceRecordFactory.buildServiceAppointmentInvoiceLine(
                        invoiceRecord.Id,
                        appointmentRecord.Id,
                        opportunityRecord.Id,
                        workOrderIdByAppointmentId.get(appointmentRecord.Id),
                        pendingExternal ? null : amountByAppointmentId.get(appointmentRecord.Id)
                    )
                );
            }
        }
        insert linesToInsert;

        BillingControl_InvoiceMath.recalculate(new Set<Id>{ invoiceRecord.Id });
        ensureCommissionOnFirstInvoice(opportunityRecord);
        stampBlankInvoiceNumbers(evidenceAppointments, invoiceNumber);
        if (updateOperationalAttribution) {
            stampOperationalAttribution(evidenceAppointments, opportunityRecord.Id);
        }
        if (!evidenceAppointments.isEmpty()) {
            update evidenceAppointments;
        }
        writeLedgerEntries(
            invoiceRecord,
            invoiceType,
            invoiceAmount,
            opportunityRecord.Id,
            new Set<Id>(workOrderIdByAppointmentId.values())
        );
        applyOpportunityBillingStatus(opportunityRecord);

        InvoiceResult result = new InvoiceResult();
        result.invoiceId = invoiceRecord.Id;
        result.invoiceNumber = invoiceNumber;
        result.invoiceType = invoiceType;
        result.invoiceAmount = invoiceAmount;
        result.varianceWarning = varianceWarning;
        result.operationalAttributionUpdated = updateOperationalAttribution;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static InvoiceDefaults getInvoiceDefaults(Id opportunityId, String invoiceType) {
        InvoiceDefaults defaults = new InvoiceDefaults();
        if (opportunityId == null) {
            return defaults;
        }
        List<Opportunity> opportunityRows = [
            SELECT Amount, Deposit_Amount_Required__c, Deposit_Percent__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (opportunityRows.isEmpty()) {
            return defaults;
        }
        Opportunity opportunityRecord = opportunityRows[0];
        BillingControl_OpportunityFinancials.Snapshot financials =
            BillingControl_OpportunityFinancials.load(new Set<Id>{ opportunityId }).get(opportunityId);
        defaults.opportunityAmount = opportunityRecord.Amount;
        defaults.invoicedTotal = financials == null ? 0 : financials.invoicedTotal;
        defaults.remainingAmount = remainingToInvoice(opportunityRecord.Amount, defaults.invoicedTotal);
        defaults.depositAmountRequired = opportunityRecord.Deposit_Amount_Required__c;
        defaults.depositPercent = opportunityRecord.Deposit_Percent__c;
        defaults.suggestedAmount = suggestedAmountForType(invoiceType, opportunityRecord, defaults.remainingAmount);
        return defaults;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityCandidate> listCandidateOpportunities(String objectApiName, Id recordId) {
        List<OpportunityCandidate> candidates = new List<OpportunityCandidate>();
        if (recordId == null) {
            return candidates;
        }
        Set<Id> opportunityIds = new Set<Id>();
        if (objectApiName == 'Opportunity') {
            opportunityIds.add(recordId);
        } else if (objectApiName == 'WorkOrder') {
            opportunityIds.addAll(opportunityIdsForWorkOrder(recordId));
        } else if (objectApiName == 'ServiceAppointment') {
            List<ServiceAppointment> appointmentRows = [
                SELECT Opportunity__c, ParentRecordId
                FROM ServiceAppointment
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!appointmentRows.isEmpty()) {
                if (appointmentRows[0].Opportunity__c != null) {
                    opportunityIds.add(appointmentRows[0].Opportunity__c);
                }
                Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(
                    appointmentRows
                );
                Id workOrderId = workOrderIdByAppointmentId.get(recordId);
                if (workOrderId != null) {
                    opportunityIds.addAll(opportunityIdsForWorkOrder(workOrderId));
                }
            }
        }
        if (opportunityIds.isEmpty()) {
            return candidates;
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> financialsByOpportunityId =
            BillingControl_OpportunityFinancials.load(opportunityIds);
        for (Opportunity opportunityRecord : [
            SELECT Id, Name, Quote_Number__c, Amount, Deposit_Amount_Required__c, Deposit_Percent__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            ORDER BY Name
        ]) {
            OpportunityCandidate candidate = new OpportunityCandidate();
            candidate.opportunityId = opportunityRecord.Id;
            candidate.name = opportunityRecord.Name;
            candidate.quoteNumber = opportunityRecord.Quote_Number__c;
            candidate.amount = opportunityRecord.Amount;
            BillingControl_OpportunityFinancials.Snapshot snapshot = financialsByOpportunityId.get(opportunityRecord.Id);
            Decimal invoicedTotal = snapshot == null ? 0 : snapshot.invoicedTotal;
            candidate.remainingAmount = remainingToInvoice(opportunityRecord.Amount, invoicedTotal);
            candidate.suggestedAmount = candidate.remainingAmount;
            candidates.add(candidate);
        }
        return candidates;
    }

    @AuraEnabled(cacheable=true)
    public static VisitInvoiceContext getVisitInvoiceContext(Id serviceAppointmentId) {
        VisitInvoiceContext context = new VisitInvoiceContext();
        if (serviceAppointmentId == null) {
            return context;
        }
        List<ServiceAppointment> appointmentRows = [
            SELECT Id, AppointmentNumber, Opportunity__c, Opportunity__r.Name, ParentRecordId
            FROM ServiceAppointment
            WHERE Id = :serviceAppointmentId
            LIMIT 1
        ];
        if (appointmentRows.isEmpty()) {
            return context;
        }
        ServiceAppointment appointmentRecord = appointmentRows[0];
        context.serviceAppointmentId = appointmentRecord.Id;
        context.serviceAppointmentNumber = appointmentRecord.AppointmentNumber;
        context.opportunityId = appointmentRecord.Opportunity__c;
        context.opportunityName = appointmentRecord.Opportunity__r == null
            ? null
            : appointmentRecord.Opportunity__r.Name;
        context.unassigned = appointmentRecord.Opportunity__c == null;
        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(
            appointmentRows
        );
        context.workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
        if (context.workOrderId != null) {
            List<WorkOrder> workOrderRows = [
                SELECT WorkOrderNumber
                FROM WorkOrder
                WHERE Id = :context.workOrderId
                LIMIT 1
            ];
            if (!workOrderRows.isEmpty()) {
                context.workOrderNumber = workOrderRows[0].WorkOrderNumber;
            }
            List<Work_Order_Ledger__c> ledgerRows = [
                SELECT Id
                FROM Work_Order_Ledger__c
                WHERE Work_Order__c = :context.workOrderId
                LIMIT 1
            ];
            if (!ledgerRows.isEmpty()) {
                context.ledgerId = ledgerRows[0].Id;
            }
        }
        return context;
    }

    private static String resolveInvoiceNumber(String requestedNumber, Id opportunityId) {
        if (!String.isBlank(requestedNumber)) {
            String trimmed = requestedNumber.trim();
            if (trimmed.length() > 80) {
                throw BillingControl_Invoicing.buildHandledException('Invoice number must be 80 characters or fewer.');
            }
            Integer existingCount = [
                SELECT COUNT()
                FROM Invoice__c
                WHERE Invoice_Number__c = :trimmed
            ];
            if (existingCount > 0) {
                throw BillingControl_Invoicing.buildHandledException(
                    'One or more invoice numbers are already used on another invoice. Enter a different number.'
                );
            }
            return trimmed;
        }
        return BillingControl_CompleteBilling.buildInvoiceNumber(opportunityId, 1);
    }

    private static List<ServiceAppointment> loadAndValidateAppointments(
        List<Id> serviceAppointmentIds,
        Id opportunityId
    ) {
        List<ServiceAppointment> evidenceAppointments = new List<ServiceAppointment>();
        if (serviceAppointmentIds == null || serviceAppointmentIds.isEmpty()) {
            return evidenceAppointments;
        }
        evidenceAppointments = [
            SELECT Id,
                AppointmentNumber,
                Status,
                Opportunity__c,
                Invoice_Number__c,
                ParentRecordId
            FROM ServiceAppointment
            WHERE Id IN :serviceAppointmentIds
            FOR UPDATE
        ];
        if (evidenceAppointments.size() != new Set<Id>(serviceAppointmentIds).size()) {
            throw BillingControl_Invoicing.buildHandledException('One or more Service Appointments were not found.');
        }

        Map<Id, Id> workOrderIdByAppointmentId =
            BillingControl_Attribution.resolveWorkOrderIdsForAppointments(evidenceAppointments);
        Set<Id> workOrderIds = new Set<Id>(workOrderIdByAppointmentId.values());
        Map<Id, Set<Id>> opportunityIdsByWorkOrderId = new Map<Id, Set<Id>>();
        if (!workOrderIds.isEmpty()) {
            Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId =
                BillingControl_Attribution.queryJunctionsByWorkOrderId(workOrderIds);
            for (Id workOrderId : junctionsByWorkOrderId.keySet()) {
                Set<Id> opportunityIds = new Set<Id>();
                for (Opportunity_WorkOrder__c junctionRecord : junctionsByWorkOrderId.get(workOrderId)) {
                    if (junctionRecord.Opportunity__c != null) {
                        opportunityIds.add(junctionRecord.Opportunity__c);
                    }
                }
                if (!opportunityIds.isEmpty()) {
                    opportunityIdsByWorkOrderId.put(workOrderId, opportunityIds);
                }
            }
        }

        Set<Id> billedAppointmentIds = BillingControl_BillingTruth.billedAppointmentIds(
            new Map<Id, ServiceAppointment>(evidenceAppointments).keySet()
        );
        Map<Id, String> billedInvoiceNumberByAppointmentId = new Map<Id, String>();
        if (!billedAppointmentIds.isEmpty()) {
            for (Invoice_Line__c invoiceLineRecord : [
                SELECT Service_Appointment__c, Invoice__r.Invoice_Number__c
                FROM Invoice_Line__c
                WHERE Service_Appointment__c IN :billedAppointmentIds
                AND Invoice__r.Status__c != :STATUS_VOID
            ]) {
                billedInvoiceNumberByAppointmentId.put(
                    invoiceLineRecord.Service_Appointment__c,
                    invoiceLineRecord.Invoice__r.Invoice_Number__c
                );
            }
        }

        for (ServiceAppointment appointmentRecord : evidenceAppointments) {
            String appointmentLabel = String.isBlank(appointmentRecord.AppointmentNumber)
                ? String.valueOf(appointmentRecord.Id)
                : appointmentRecord.AppointmentNumber;
            if (appointmentRecord.Status != STATUS_COMPLETED) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Service Appointment ' + appointmentLabel + ' must be Completed before it can be invoiced.'
                );
            }
            if (billedAppointmentIds.contains(appointmentRecord.Id)) {
                String existingNumber = billedInvoiceNumberByAppointmentId.get(appointmentRecord.Id);
                throw BillingControl_Invoicing.buildHandledException(
                    'Service Appointment '
                    + appointmentLabel
                    + ' is already billed'
                    + (String.isBlank(existingNumber) ? '.' : ' on invoice ' + existingNumber + '.')
                );
            }
            if (appointmentRecord.Opportunity__c != null && appointmentRecord.Opportunity__c != opportunityId) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Service Appointment '
                    + appointmentLabel
                    + ' is attributed to a different Opportunity and cannot be used as evidence for this invoice.'
                );
            }
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            Set<Id> linkedOpportunityIds = opportunityIdsByWorkOrderId.get(workOrderId);
            Boolean linkedToChosenOpportunity = linkedOpportunityIds != null && linkedOpportunityIds.contains(opportunityId);
            Boolean parentedToWorkOrder = workOrderId != null;
            if (!linkedToChosenOpportunity && !(parentedToWorkOrder && appointmentRecord.Opportunity__c == opportunityId)) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Service Appointment '
                    + appointmentLabel
                    + ' does not belong to a Work Order linked to the chosen Opportunity.'
                );
            }
        }
        return evidenceAppointments;
    }

    private static void applyOpportunityBillingStatus(Opportunity opportunityRecord) {
        String preservedStatus = opportunityRecord.Billing_Status__c;
        Boolean preservePaymentStatus =
            preservedStatus == STATUS_PAID || preservedStatus == STATUS_PARTIALLY_PAID;
        String desiredStatus = preservePaymentStatus
            ? preservedStatus
            : BillingControl_Invoicing.getOutstandingReceivableStatusForUpdate();
        Opportunity latestOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        if (latestOpportunity.Billing_Status__c == desiredStatus) {
            return;
        }
        update new Opportunity(Id = opportunityRecord.Id, Billing_Status__c = desiredStatus);
    }

    private static void ensureCommissionOnFirstInvoice(Opportunity opportunityRecord) {
        BillingControl_CommissionLifecycle.ensureAccrued(opportunityRecord);
    }

    private static void stampBlankInvoiceNumbers(List<ServiceAppointment> appointments, String invoiceNumber) {
        for (ServiceAppointment appointmentRecord : appointments) {
            if (String.isBlank(appointmentRecord.Invoice_Number__c)) {
                appointmentRecord.Invoice_Number__c = invoiceNumber;
            }
        }
    }

    private static void stampOperationalAttribution(List<ServiceAppointment> appointments, Id opportunityId) {
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord.Opportunity__c == null) {
                appointmentRecord.Opportunity__c = opportunityId;
            }
        }
    }

    private static void writeLedgerEntries(
        Invoice__c invoiceRecord,
        String invoiceType,
        Decimal invoiceAmount,
        Id opportunityId,
        Set<Id> workOrderIds
    ) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }
        workOrderIds.remove(null);
        if (workOrderIds.isEmpty()) {
            return;
        }

        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId = new Map<Id, Work_Order_Ledger__c>();
        for (Work_Order_Ledger__c ledgerRecord : [
            SELECT Id, Work_Order__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c IN :workOrderIds
        ]) {
            ledgerByWorkOrderId.put(ledgerRecord.Work_Order__c, ledgerRecord);
        }
        List<Work_Order_Ledger__c> ledgersToInsert = new List<Work_Order_Ledger__c>();
        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>([
            SELECT Id, AccountId
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
        for (Id workOrderId : workOrderIds) {
            if (ledgerByWorkOrderId.containsKey(workOrderId)) {
                continue;
            }
            WorkOrder workOrderRecord = workOrderById.get(workOrderId);
            ledgersToInsert.add(new Work_Order_Ledger__c(
                Work_Order__c = workOrderId,
                Work_Order_Key__c = String.valueOf(workOrderId),
                Account__c = workOrderRecord == null ? null : workOrderRecord.AccountId
            ));
        }
        if (!ledgersToInsert.isEmpty()) {
            insert ledgersToInsert;
            for (Work_Order_Ledger__c ledgerRecord : ledgersToInsert) {
                ledgerByWorkOrderId.put(ledgerRecord.Work_Order__c, ledgerRecord);
            }
        }

        String eventType = invoiceType == TYPE_DEPOSIT ? 'DEPOSIT_RECORDED' : 'INVOICE_CREATED';
        List<Work_Order_Ledger_Entry__c> entriesToInsert = new List<Work_Order_Ledger_Entry__c>();
        for (Id workOrderId : workOrderIds) {
            Work_Order_Ledger__c ledgerRecord = ledgerByWorkOrderId.get(workOrderId);
            if (ledgerRecord == null) {
                continue;
            }
            String eventKey = (eventType + '|' + String.valueOf(invoiceRecord.Id) + '|' + String.valueOf(workOrderId));
            if (eventKey.length() > 80) {
                eventKey = eventKey.substring(0, 80);
            }
            entriesToInsert.add(new Work_Order_Ledger_Entry__c(
                Work_Order_Ledger__c = ledgerRecord.Id,
                Event_Type__c = eventType,
                Event_Key__c = eventKey,
                Event_Datetime__c = System.now(),
                Invoice__c = invoiceRecord.Id,
                Opportunity__c = opportunityId,
                Amount__c = invoiceAmount,
                Description__c = invoiceType + ' invoice ' + invoiceRecord.Invoice_Number__c,
                System_Generated__c = true,
                Changed_By__c = UserInfo.getUserId(),
                Source_Object__c = 'Invoice',
                Source_Record_Id__c = String.valueOf(invoiceRecord.Id)
            ));
        }
        if (!entriesToInsert.isEmpty()) {
            insert entriesToInsert;
        }
    }

    private static Set<Id> opportunityIdsForWorkOrder(Id workOrderId) {
        Set<Id> opportunityIds = new Set<Id>();
        if (workOrderId == null) {
            return opportunityIds;
        }
        List<Opportunity_WorkOrder__c> junctions =
            BillingControl_Attribution.queryJunctionsByWorkOrderId(new Set<Id>{ workOrderId }).get(workOrderId);
        if (junctions == null) {
            return opportunityIds;
        }
        for (Opportunity_WorkOrder__c junctionRecord : junctions) {
            if (junctionRecord.Opportunity__c != null) {
                opportunityIds.add(junctionRecord.Opportunity__c);
            }
        }
        return opportunityIds;
    }

    private static Decimal remainingToInvoice(Decimal opportunityAmount, Decimal invoicedTotal) {
        return BillingControl_InvoiceMath.remainingToInvoice(opportunityAmount, invoicedTotal);
    }

    private static Decimal suggestedAmountForType(
        String invoiceType,
        Opportunity opportunityRecord,
        Decimal remainingAmount
    ) {
        if (invoiceType == TYPE_DEPOSIT) {
            if (opportunityRecord.Deposit_Amount_Required__c != null) {
                return opportunityRecord.Deposit_Amount_Required__c;
            }
            if (opportunityRecord.Amount != null && opportunityRecord.Deposit_Percent__c != null) {
                return (opportunityRecord.Amount * opportunityRecord.Deposit_Percent__c / 100)
                    .setScale(2, RoundingMode.HALF_UP);
            }
            return null;
        }
        if (invoiceType == TYPE_BALANCE) {
            return remainingAmount;
        }
        return null;
    }

    private static String descriptiveLineText(String invoiceType, Opportunity opportunityRecord) {
        if (invoiceType == TYPE_DEPOSIT) {
            Decimal percentValue = opportunityRecord.Deposit_Percent__c;
            if (percentValue != null) {
                return 'Deposit — ' + String.valueOf(percentValue) + '% of quoted amount';
            }
            return 'Deposit';
        }
        return invoiceType + ' invoice';
    }
}
