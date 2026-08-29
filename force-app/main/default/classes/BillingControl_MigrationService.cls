/**
 * Sandbox-first Phase 8 helpers. Default dryRun=true. Execute is blocked in production
 * (except unit tests). Never fabricate Invoice_Payment__c. Never auto-void stubs.
 */
public inherited sharing class BillingControl_MigrationService {
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_VOID = 'Void';
    private static final String SOURCE_PENDING_EXTERNAL = 'Pending External';
    private static final String TIMING_NOT_REQUIRED = 'Not Required';
    private static final String TIMING_BEFORE_COMPLETION = 'Before Completion';

    public class ReviewRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
    }

    public class MigrationReport {
        @AuraEnabled public Integer unattributedCompletedAppointments;
        @AuraEnabled public Integer uniqueJunctionAutoAttributeCandidates;
        @AuraEnabled public Integer stubInvoices;
        @AuraEnabled public Integer historicalInvoiceTokens;
        @AuraEnabled public Integer uniqueJunctionDepositSeeds;
        @AuraEnabled public Integer multiOppDepositReviews;
        @AuraEnabled public Integer openJobsMissingCommission;
        @AuraEnabled public Integer attributedAppointments;
        @AuraEnabled public Integer invoicesCreated;
        @AuraEnabled public Integer depositsSeeded;
        @AuraEnabled public Integer commissionsCreated;
        @AuraEnabled public List<ReviewRow> reviewRows;
        @AuraEnabled public Boolean dryRun;
        @AuraEnabled public List<String> notes;
    }

    @AuraEnabled
    public static MigrationReport preview() {
        return run(true);
    }

    public static MigrationReport run(Boolean dryRun) {
        Boolean isDryRun = dryRun != false;
        if (!isDryRun) {
            assertSandboxExecuteAllowed();
        }

        MigrationReport report = new MigrationReport();
        report.dryRun = isDryRun;
        report.reviewRows = new List<ReviewRow>();
        report.notes = new List<String>{
            'Run against a production copy in sandbox first.',
            'Never fabricate Invoice_Payment__c.',
            'Multi-Opportunity Work Orders are review-only for deposit dollars.',
            'Stub invoices are review-only; voiding requires finance sign-off.'
        };
        report.attributedAppointments = 0;
        report.invoicesCreated = 0;
        report.depositsSeeded = 0;
        report.commissionsCreated = 0;

        Map<Id, Id> uniqueOpportunityByWorkOrderId = uniqueOpportunityByWorkOrderId();
        Set<Id> uniqueJunctionWorkOrderIds = uniqueOpportunityByWorkOrderId.keySet();

        List<ServiceAppointment> unattributed = [
            SELECT Id, AppointmentNumber, ParentRecordId, Opportunity__c
            FROM ServiceAppointment
            WHERE Status = :STATUS_COMPLETED
            AND Opportunity__c = NULL
            LIMIT 500
        ];
        report.unattributedCompletedAppointments = unattributed.size();
        List<ServiceAppointment> autoAttribute = new List<ServiceAppointment>();
        for (ServiceAppointment appointmentRecord : unattributed) {
            if (uniqueJunctionWorkOrderIds.contains(appointmentRecord.ParentRecordId)) {
                appointmentRecord.Opportunity__c = uniqueOpportunityByWorkOrderId.get(appointmentRecord.ParentRecordId);
                autoAttribute.add(appointmentRecord);
            } else {
                report.reviewRows.add(reviewRow(
                    appointmentRecord.Id,
                    appointmentRecord.AppointmentNumber,
                    'Completed SA with no Opportunity on a multi-Opp or unlinked Work Order'
                ));
            }
        }
        report.uniqueJunctionAutoAttributeCandidates = autoAttribute.size();

        List<Invoice__c> stubInvoices = [
            SELECT Id, Invoice_Number__c, Total_Amount__c, Status__c
            FROM Invoice__c
            WHERE Status__c != :STATUS_VOID
            AND (Total_Amount__c = NULL OR Total_Amount__c = 0)
            LIMIT 500
        ];
        report.stubInvoices = stubInvoices.size();
        for (Invoice__c invoiceRecord : stubInvoices) {
            report.reviewRows.add(reviewRow(
                invoiceRecord.Id,
                invoiceRecord.Invoice_Number__c,
                'Stub or pending-amount invoice; void only with finance sign-off'
            ));
        }

        Set<String> existingInvoiceKeys = existingInvoiceKeys();
        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        Integer historicalTokens = 0;
        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>([
            SELECT Id, WorkOrderNumber, Invoice_Number__c, AccountId
            FROM WorkOrder
            WHERE Invoice_Number__c != NULL
            LIMIT 500
        ]);
        for (WorkOrder workOrderRecord : workOrderById.values()) {
            List<BillingControl_InvoiceNumberParser.ParsedToken> tokens =
                BillingControl_InvoiceNumberParser.parse(workOrderRecord.Invoice_Number__c);
            historicalTokens += tokens.size();
            Id opportunityId = uniqueOpportunityByWorkOrderId.get(workOrderRecord.Id);
            if (opportunityId == null) {
                if (!tokens.isEmpty()) {
                    report.reviewRows.add(reviewRow(
                        workOrderRecord.Id,
                        workOrderRecord.WorkOrderNumber,
                        'Historical invoice tokens on a multi-Opp or unlinked Work Order'
                    ));
                }
                continue;
            }
            addPendingExternalInvoices(
                tokens,
                opportunityId,
                workOrderRecord.AccountId,
                existingInvoiceKeys,
                invoicesToInsert
            );
        }
        for (ServiceAppointment appointmentRecord : [
            SELECT Id, AppointmentNumber, ParentRecordId, Opportunity__c, Invoice_Number__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c != NULL
            LIMIT 500
        ]) {
            List<BillingControl_InvoiceNumberParser.ParsedToken> tokens =
                BillingControl_InvoiceNumberParser.parse(appointmentRecord.Invoice_Number__c);
            historicalTokens += tokens.size();
            Id opportunityId = appointmentRecord.Opportunity__c != null
                ? appointmentRecord.Opportunity__c
                : uniqueOpportunityByWorkOrderId.get(appointmentRecord.ParentRecordId);
            if (opportunityId == null) {
                if (!tokens.isEmpty()) {
                    report.reviewRows.add(reviewRow(
                        appointmentRecord.Id,
                        appointmentRecord.AppointmentNumber,
                        'Historical invoice tokens on an SA without unique Opportunity'
                    ));
                }
                continue;
            }
            WorkOrder parentWorkOrder = workOrderById.get(appointmentRecord.ParentRecordId);
            Id accountId = parentWorkOrder != null ? parentWorkOrder.AccountId : null;
            addPendingExternalInvoices(
                tokens,
                opportunityId,
                accountId,
                existingInvoiceKeys,
                invoicesToInsert
            );
        }
        report.historicalInvoiceTokens = historicalTokens;

        Integer uniqueDepositSeeds = 0;
        Integer multiOppReviews = 0;
        List<Opportunity> depositsToUpdate = new List<Opportunity>();
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
        for (WorkOrder workOrderRecord : [
            SELECT Id, WorkOrderNumber, Deposit_Payments__c, Deposit_Amount__c
            FROM WorkOrder
            WHERE Deposit_Payments__c != NULL OR Deposit_Amount__c != NULL
            LIMIT 500
        ]) {
            if (uniqueJunctionWorkOrderIds.contains(workOrderRecord.Id)) {
                uniqueDepositSeeds++;
                Id opportunityId = uniqueOpportunityByWorkOrderId.get(workOrderRecord.Id);
                Opportunity opportunityRecord = opportunityById.get(opportunityId);
                if (opportunityRecord == null) {
                    opportunityRecord = new Opportunity(Id = opportunityId);
                    opportunityById.put(opportunityId, opportunityRecord);
                    depositsToUpdate.add(opportunityRecord);
                }
                applyDepositSeed(opportunityRecord, workOrderRecord);
            } else if (workOrderRecord.Deposit_Amount__c != null) {
                multiOppReviews++;
                report.reviewRows.add(reviewRow(
                    workOrderRecord.Id,
                    workOrderRecord.WorkOrderNumber,
                    'Deposit amount on a non-unique Work Order; do not split dollars'
                ));
            }
        }
        report.uniqueJunctionDepositSeeds = uniqueDepositSeeds;
        report.multiOppDepositReviews = multiOppReviews;

        Set<Id> opportunityIdsWithCommission = new Set<Id>();
        for (Commission__c commissionRecord : [
            SELECT Opportunity__c
            FROM Commission__c
            WHERE Opportunity__c != NULL
        ]) {
            opportunityIdsWithCommission.add(commissionRecord.Opportunity__c);
        }
        Set<Id> missingCommissionOpportunityIds = new Set<Id>();
        for (AggregateResult aggregateRow : [
            SELECT Opportunity__c opportunityId
            FROM Invoice__c
            WHERE Status__c != :STATUS_VOID
            AND Opportunity__c != NULL
            GROUP BY Opportunity__c
        ]) {
            Id opportunityId = (Id) aggregateRow.get('opportunityId');
            if (!opportunityIdsWithCommission.contains(opportunityId)) {
                missingCommissionOpportunityIds.add(opportunityId);
            }
        }
        for (Invoice__c invoiceRecord : invoicesToInsert) {
            if (invoiceRecord.Opportunity__c != null
                && !opportunityIdsWithCommission.contains(invoiceRecord.Opportunity__c)
            ) {
                missingCommissionOpportunityIds.add(invoiceRecord.Opportunity__c);
            }
        }
        report.openJobsMissingCommission = missingCommissionOpportunityIds.size();

        if (!isDryRun) {
            if (!autoAttribute.isEmpty()) {
                update autoAttribute;
                report.attributedAppointments = autoAttribute.size();
            }
            if (!invoicesToInsert.isEmpty()) {
                insert invoicesToInsert;
                report.invoicesCreated = invoicesToInsert.size();
                BillingControl_InvoiceMath.recalculate(new Map<Id, Invoice__c>(invoicesToInsert).keySet());
            }
            if (!depositsToUpdate.isEmpty()) {
                update depositsToUpdate;
                report.depositsSeeded = depositsToUpdate.size();
            }
            List<Opportunity> commissionOpportunities = missingCommissionOpportunityIds.isEmpty()
                ? new List<Opportunity>()
                : [
                    SELECT Id, OwnerId
                    FROM Opportunity
                    WHERE Id IN :missingCommissionOpportunityIds
                ];
            Integer beforeCount = missingCommissionOpportunityIds.isEmpty()
                ? 0
                : [SELECT COUNT() FROM Commission__c WHERE Opportunity__c IN :missingCommissionOpportunityIds];
            for (Opportunity opportunityRecord : commissionOpportunities) {
                BillingControl_CommissionLifecycle.ensureAccrued(opportunityRecord);
            }
            Integer afterCount = missingCommissionOpportunityIds.isEmpty()
                ? 0
                : [SELECT COUNT() FROM Commission__c WHERE Opportunity__c IN :missingCommissionOpportunityIds];
            report.commissionsCreated = afterCount - beforeCount;
            report.notes.add('Executed sandbox backfill. Stub invoices were not voided. No Invoice_Payment__c rows were created.');
        }
        return report;
    }

    private static void assertSandboxExecuteAllowed() {
        if (Test.isRunningTest()) {
            return;
        }
        Organization organizationRecord = [SELECT IsSandbox FROM Organization LIMIT 1];
        if (!organizationRecord.IsSandbox) {
            throw new AuraHandledException('Migration execute is sandbox-only. Use preview() in production.');
        }
    }

    private static Set<String> existingInvoiceKeys() {
        Set<String> keys = new Set<String>();
        for (Invoice__c invoiceRecord : [
            SELECT Opportunity__c, Invoice_Number__c
            FROM Invoice__c
            WHERE Status__c != :STATUS_VOID
            AND Opportunity__c != NULL
            LIMIT 5000
        ]) {
            String digitKey = BillingControl_InvoiceNumberParser.digitKey(invoiceRecord.Invoice_Number__c);
            if (digitKey != null) {
                keys.add(String.valueOf(invoiceRecord.Opportunity__c) + ':' + digitKey);
            }
        }
        return keys;
    }

    private static void applyDepositSeed(Opportunity opportunityRecord, WorkOrder workOrderRecord) {
        String depositPayments = workOrderRecord.Deposit_Payments__c;
        if (depositPayments == 'No Deposit required' || depositPayments == 'Due in Full') {
            opportunityRecord.Deposit_Required__c = false;
            opportunityRecord.Deposit_Timing__c = TIMING_NOT_REQUIRED;
        } else if (
            depositPayments == 'Deposit Required'
            || depositPayments == 'Waiting for deposit'
            || depositPayments == 'Deposit received'
        ) {
            opportunityRecord.Deposit_Required__c = true;
            opportunityRecord.Deposit_Timing__c = TIMING_BEFORE_COMPLETION;
        }
        if (workOrderRecord.Deposit_Amount__c != null) {
            opportunityRecord.Deposit_Amount_Required__c = workOrderRecord.Deposit_Amount__c;
        }
    }

    private static Map<Id, Id> uniqueOpportunityByWorkOrderId() {
        Map<Id, Id> opportunityByWorkOrderId = new Map<Id, Id>();
        Map<Id, Integer> junctionCountByWorkOrderId = new Map<Id, Integer>();
        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Work_Order__c, Opportunity__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c != NULL
            AND Opportunity__c != NULL
        ]) {
            Integer currentCount = junctionCountByWorkOrderId.containsKey(junctionRecord.Work_Order__c)
                ? junctionCountByWorkOrderId.get(junctionRecord.Work_Order__c)
                : 0;
            junctionCountByWorkOrderId.put(junctionRecord.Work_Order__c, currentCount + 1);
            opportunityByWorkOrderId.put(junctionRecord.Work_Order__c, junctionRecord.Opportunity__c);
        }
        Map<Id, Id> uniqueIds = new Map<Id, Id>();
        for (Id workOrderId : junctionCountByWorkOrderId.keySet()) {
            if (junctionCountByWorkOrderId.get(workOrderId) == 1) {
                uniqueIds.put(workOrderId, opportunityByWorkOrderId.get(workOrderId));
            }
        }
        return uniqueIds;
    }

    private static void addPendingExternalInvoices(
        List<BillingControl_InvoiceNumberParser.ParsedToken> tokens,
        Id opportunityId,
        Id accountId,
        Set<String> existingInvoiceKeys,
        List<Invoice__c> invoicesToInsert
    ) {
        for (BillingControl_InvoiceNumberParser.ParsedToken parsedToken : tokens) {
            String canonicalNumber = BillingControl_InvoiceNumberParser.canonicalNumber(parsedToken);
            String invoiceKey = String.valueOf(opportunityId) + ':' + BillingControl_InvoiceNumberParser.digitKey(canonicalNumber);
            if (String.isBlank(canonicalNumber) || existingInvoiceKeys.contains(invoiceKey)) {
                continue;
            }
            existingInvoiceKeys.add(invoiceKey);
            invoicesToInsert.add(
                BillingControl_InvoiceRecordFactory.buildTypedInvoiceHeader(
                    canonicalNumber,
                    opportunityId,
                    accountId,
                    null,
                    Date.today(),
                    null,
                    parsedToken.type,
                    SOURCE_PENDING_EXTERNAL
                )
            );
        }
    }

    private static ReviewRow reviewRow(Id recordId, String label, String detail) {
        ReviewRow row = new ReviewRow();
        row.recordId = recordId;
        row.label = label;
        row.detail = detail;
        return row;
    }
}
