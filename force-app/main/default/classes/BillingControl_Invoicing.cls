/**
 * Billing lifecycle and commissions: opportunity lists/metrics by Billing_Status__c, postReceipt
 * (Invoice_Payment__c + Opportunity updates), and Commission__c metrics / grouping / creation.
 * Junction WorkOrder context: Opportunity_WorkOrder__c. For Closed Won pipeline KPIs and bucket drilldown,
 * use BillingControl_Orders (separate API; billingControlCenterOrders LWC calls that class).
 */
public with sharing class BillingControl_Invoicing {
    private static final String READY_FOR_BILLING = 'Ready for Billing';
    /** Matches picklist label/API on Opportunity.Billing_Status__c; distinct from Ready for Billing */
    private static final String AWAITING_BILLING = 'Awaiting Billing';
    /**
     * Opportunity billing statuses for which completed unbilled SAs appear on the Invoicing tab
     * and may be completed via Complete Billing (must match production picklist API values).
     */
    private static final List<String> INVOICING_PAGE_OPPORTUNITY_BILLING_STATUSES = new List<String>{
        READY_FOR_BILLING,
        AWAITING_BILLING
    };
    private static final String OUTSTANDING_RECEIVABLE = 'Billed (Outstanding Receivable)';
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final String COMMISSION_EARNED = 'earned';
    private static final String COMMISSION_PAYABLE = 'payable';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final String BILLING_STATE_READY = 'Pending Invoice';
    private static final String BILLING_STATE_PARTIAL = 'Partial';
    private static final String INVOICE_STATUS_DRAFT = 'Draft';
    private static final String INVOICE_STATUS_SENT = 'Sent';
    private static final String INVOICE_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String INVOICE_STATUS_PAID = 'Paid';

    private static Boolean isInvoicingPageOpportunityBillingStatus(String billingStatus) {
        return String.isNotBlank(billingStatus) && INVOICING_PAGE_OPPORTUNITY_BILLING_STATUSES.contains(billingStatus);
    }

    /**
     * Work Orders with exactly one related opportunity (via Opportunity_WorkOrder__c) map to that opportunity.
     * When a WO has multiple opportunities, the map has no entry — caller must rely on ServiceAppointment.Opportunity__c.
     */
    private static Map<Id, Id> buildWorkOrderToSingleOpportunityMap(Set<Id> workOrderIds) {
        Map<Id, Id> workOrderToSingleOpportunityId = new Map<Id, Id>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return workOrderToSingleOpportunityId;
        }

        Map<Id, Integer> junctionCountByWorkOrderId = new Map<Id, Integer>();
        Map<Id, Id> firstOpportunityIdByWorkOrderId = new Map<Id, Id>();

        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Work_Order__c, Opportunity__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c IN :workOrderIds
        ]) {
            Id workOrderId = junctionRecord.Work_Order__c;
            if (!firstOpportunityIdByWorkOrderId.containsKey(workOrderId)) {
                firstOpportunityIdByWorkOrderId.put(workOrderId, junctionRecord.Opportunity__c);
            }
            Integer prior = junctionCountByWorkOrderId.containsKey(workOrderId) ? junctionCountByWorkOrderId.get(workOrderId) : 0;
            junctionCountByWorkOrderId.put(workOrderId, prior + 1);
        }

        for (Id workOrderId : firstOpportunityIdByWorkOrderId.keySet()) {
            if (junctionCountByWorkOrderId.get(workOrderId) == 1) {
                workOrderToSingleOpportunityId.put(workOrderId, firstOpportunityIdByWorkOrderId.get(workOrderId));
            }
        }

        return workOrderToSingleOpportunityId;
    }

    private static Id resolveEffectiveOpportunityId(ServiceAppointment appointment, Map<Id, Id> workOrderToSingleOpportunityId) {
        if (appointment == null) {
            return null;
        }
        if (appointment.Opportunity__c != null) {
            return appointment.Opportunity__c;
        }
        if (
            appointment.ParentRecordId != null
            && workOrderToSingleOpportunityId != null
            && workOrderToSingleOpportunityId.containsKey(appointment.ParentRecordId)
        ) {
            return workOrderToSingleOpportunityId.get(appointment.ParentRecordId);
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityWrapper> getReadyForBillingOpportunities() {
        return buildOpportunityWrappers([
            SELECT Id,
                Name,
                Account.Name,
                StageName,
                Amount,
                CloseDate,
                OwnerId,
                Owner.Name,
                Billing_Status__c,
                Amount_Paid__c,
                Ready_for_Billing_Date__c
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c >= LAST_N_DAYS:2
            ORDER BY CloseDate ASC NULLS LAST, Name ASC
        ]);
    }

    @AuraEnabled
    public static List<OpportunityWrapper> getAwaitingBillingOpportunities() {
        return buildOpportunityWrappers([
            SELECT Id,
                Name,
                Account.Name,
                StageName,
                Amount,
                CloseDate,
                OwnerId,
                Owner.Name,
                Billing_Status__c,
                Amount_Paid__c,
                Ready_for_Billing_Date__c
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c < LAST_N_DAYS:2
            ORDER BY CloseDate ASC NULLS LAST, Name ASC
        ]);
    }

    @AuraEnabled
    public static List<OpportunityWrapper> getOutstandingReceivableOpportunities() {
        return buildOpportunityWrappers([
            SELECT Id,
                Name,
                Account.Name,
                StageName,
                Amount,
                CloseDate,
                OwnerId,
                Owner.Name,
                Billing_Status__c,
                Amount_Paid__c,
                Ready_for_Billing_Date__c
            FROM Opportunity
            WHERE Billing_Status__c = :OUTSTANDING_RECEIVABLE
            OR Billing_Status__c = :PARTIALLY_PAID
            ORDER BY CloseDate ASC NULLS LAST, Name ASC
        ]);
    }

    @AuraEnabled(cacheable=true)
    public static OpportunityBillingMetricsWrapper getOpportunityBillingMetrics() {
        OpportunityBillingMetricsWrapper metrics = new OpportunityBillingMetricsWrapper();

        AggregateResult[] readyForBillingResults = [
            SELECT COUNT(Id) opportunityCount, SUM(Amount) totalAmount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c >= LAST_N_DAYS:2
        ];
        metrics.readyForBillingLast2Days = extractInteger(readyForBillingResults, 'opportunityCount');
        metrics.totalUnbilledRevenue = extractDecimal(readyForBillingResults, 'totalAmount');

        AggregateResult[] awaitedBillingResults = [
            SELECT COUNT(Id) opportunityCount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c < LAST_N_DAYS:2
        ];
        metrics.awaitedBilling = extractInteger(awaitedBillingResults, 'opportunityCount');

        AggregateResult[] outstandingReceivableResults = [
            SELECT COUNT(Id) opportunityCount
            FROM Opportunity
            WHERE Billing_Status__c = :OUTSTANDING_RECEIVABLE
        ];
        metrics.outstandingReceivables = extractInteger(outstandingReceivableResults, 'opportunityCount');

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static BillingControlMetricsWrapper getServiceAppointmentBillingMetrics() {
        List<ServiceAppointmentRowWrapper> rows = buildBillableServiceAppointmentRows();

        BillingControlMetricsWrapper metrics = new BillingControlMetricsWrapper();
        metrics.completedMoreThan2Days = 0;
        metrics.readyToBill = rows.size();
        metrics.unbilledRevenue = 0;
        metrics.outstandingAr = 0;

        Datetime twoDaysAgo = System.now().addDays(-2);
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row.completionDateTime != null && row.completionDateTime < twoDaysAgo) {
                metrics.completedMoreThan2Days++;
            }
            metrics.unbilledRevenue += row.billableAmount != null ? row.billableAmount : 0;
        }

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceAppointmentOpportunityGroupWrapper> getBillableServiceAppointmentGroups() {
        List<ServiceAppointmentRowWrapper> rows = buildBillableServiceAppointmentRows();
        if (rows.isEmpty()) {
            return new List<ServiceAppointmentOpportunityGroupWrapper>();
        }

        Map<Id, Integer> historicalBilledCountByOpportunityId = new Map<Id, Integer>();
        Set<Id> opportunityIds = new Set<Id>();
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row.opportunityId != null) {
                opportunityIds.add(row.opportunityId);
            }
        }
        if (!opportunityIds.isEmpty()) {
            for (AggregateResult aggregateRow : [
                SELECT Opportunity__c opportunityId, COUNT(Id) billedCount
                FROM ServiceAppointment
                WHERE Opportunity__c IN :opportunityIds
                AND Invoice_Number__c != NULL
                GROUP BY Opportunity__c
            ]) {
                historicalBilledCountByOpportunityId.put(
                    (Id) aggregateRow.get('opportunityId'),
                    (Integer) aggregateRow.get('billedCount')
                );
            }
        }

        Map<Id, ServiceAppointmentOpportunityGroupWrapper> groupByOpportunityId = new Map<Id, ServiceAppointmentOpportunityGroupWrapper>();
        List<ServiceAppointmentOpportunityGroupWrapper> groups = new List<ServiceAppointmentOpportunityGroupWrapper>();

        for (ServiceAppointmentRowWrapper row : rows) {
            ServiceAppointmentOpportunityGroupWrapper opportunityGroup = groupByOpportunityId.get(row.opportunityId);
            if (opportunityGroup == null) {
                opportunityGroup = new ServiceAppointmentOpportunityGroupWrapper();
                opportunityGroup.opportunityId = row.opportunityId;
                opportunityGroup.opportunityName = row.opportunityName;
                opportunityGroup.accountName = row.accountName;
                opportunityGroup.totalBillableAmount = 0;
                opportunityGroup.serviceAppointmentCount = 0;
                opportunityGroup.rows = new List<ServiceAppointmentRowWrapper>();
                groupByOpportunityId.put(row.opportunityId, opportunityGroup);
                groups.add(opportunityGroup);
            }

            opportunityGroup.rows.add(row);
            opportunityGroup.totalBillableAmount += row.billableAmount != null ? row.billableAmount : 0;
            opportunityGroup.serviceAppointmentCount++;
        }

        for (ServiceAppointmentOpportunityGroupWrapper opportunityGroup : groups) {
            Integer historicalBilledCount = historicalBilledCountByOpportunityId.containsKey(opportunityGroup.opportunityId)
                ? historicalBilledCountByOpportunityId.get(opportunityGroup.opportunityId)
                : 0;
            opportunityGroup.billingState = historicalBilledCount > 0 ? BILLING_STATE_PARTIAL : BILLING_STATE_READY;
            opportunityGroup.rows.sort(new ServiceAppointmentRowCompletionComparator());
        }

        groups.sort(new ServiceAppointmentGroupNameComparator());
        return groups;
    }

    @AuraEnabled
    public static CompleteBillingResultWrapper completeServiceAppointmentBilling(
        List<Id> serviceAppointmentIds,
        Map<String, String> invoiceNumberByOpportunityId
    ) {
        CompleteBillingResultWrapper result = new CompleteBillingResultWrapper();
        result.invoicesCreated = 0;
        result.serviceAppointmentsUpdated = 0;
        result.invoiceGroups = new List<InvoiceGroupResultWrapper>();

        if (serviceAppointmentIds == null || serviceAppointmentIds.isEmpty()) {
            return result;
        }

        List<ServiceAppointment> lockedAppointments = [
            SELECT Id,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.AccountId,
                Opportunity__r.Billing_Status__c,
                ParentRecordId,
                Invoice_Number__c,
                Status
            FROM ServiceAppointment
            WHERE Id IN :serviceAppointmentIds
            AND Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND Invoice_Number__c = NULL
            FOR UPDATE
        ];

        if (lockedAppointments.isEmpty()) {
            return result;
        }

        Set<Id> workOrderIdsForResolution = new Set<Id>();
        for (ServiceAppointment appointmentRecord : lockedAppointments) {
            if (appointmentRecord.ParentRecordId != null) {
                workOrderIdsForResolution.add(appointmentRecord.ParentRecordId);
            }
        }

        Map<Id, Id> workOrderToSingleOpportunityId = buildWorkOrderToSingleOpportunityMap(workOrderIdsForResolution);

        Map<Id, Id> effectiveOpportunityByAppointmentId = new Map<Id, Id>();
        for (ServiceAppointment appointmentRecord : lockedAppointments) {
            Id effectiveOpportunityId = resolveEffectiveOpportunityId(appointmentRecord, workOrderToSingleOpportunityId);
            if (effectiveOpportunityId != null) {
                effectiveOpportunityByAppointmentId.put(appointmentRecord.Id, effectiveOpportunityId);
            }
        }

        if (effectiveOpportunityByAppointmentId.isEmpty()) {
            return result;
        }

        Set<Id> resolvedOpportunityIds = new Set<Id>(effectiveOpportunityByAppointmentId.values());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, Amount, Billing_Status__c, AccountId
            FROM Opportunity
            WHERE Id IN :resolvedOpportunityIds
        ]);

        List<ServiceAppointment> appointmentsToBill = new List<ServiceAppointment>();
        for (ServiceAppointment appointmentRecord : lockedAppointments) {
            if (!effectiveOpportunityByAppointmentId.containsKey(appointmentRecord.Id)) {
                continue;
            }
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            Opportunity opportunityRecord = opportunityById.get(effectiveOpportunityId);
            if (
                opportunityRecord == null
                || !isInvoicingPageOpportunityBillingStatus(opportunityRecord.Billing_Status__c)
            ) {
                continue;
            }
            appointmentsToBill.add(appointmentRecord);
        }

        if (appointmentsToBill.isEmpty()) {
            return result;
        }

        Map<Id, WorkOrder> workOrderById = buildWorkOrderLookup(appointmentsToBill);
        Map<Id, Integer> appointmentCountByWorkOrderId = buildAppointmentCountByWorkOrder(appointmentsToBill);
        Map<String, Integer> appointmentCountByWorkOrderAndOpportunityId =
            buildAppointmentCountByWorkOrderAndOpportunity(appointmentsToBill, effectiveOpportunityByAppointmentId);

        Map<Id, List<ServiceAppointment>> appointmentsByOpportunityId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointment : appointmentsToBill) {
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointment.Id);
            if (!appointmentsByOpportunityId.containsKey(effectiveOpportunityId)) {
                appointmentsByOpportunityId.put(effectiveOpportunityId, new List<ServiceAppointment>());
            }
            appointmentsByOpportunityId.get(effectiveOpportunityId).add(appointment);
        }

        Map<Id, Decimal> invoiceTotalByOpportunityId = new Map<Id, Decimal>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Decimal invoiceTotal = 0;
            for (ServiceAppointment appointment : appointmentsByOpportunityId.get(opportunityId)) {
                invoiceTotal += resolveBillableAmount(
                    appointment.ParentRecordId,
                    effectiveOpportunityByAppointmentId.get(appointment.Id),
                    workOrderById,
                    appointmentCountByWorkOrderId,
                    appointmentCountByWorkOrderAndOpportunityId,
                    opportunityById
                );
            }
            invoiceTotalByOpportunityId.put(opportunityId, invoiceTotal);
        }

        Integer invoiceSequence = 1;
        Map<Id, String> invoiceNumberResolvedByOpportunityId = new Map<Id, String>();
        Set<String> invoiceNumbersForUniqueness = new Set<String>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            String invoiceNumber = resolveInvoiceNumberForBilling(
                opportunityId,
                invoiceNumberByOpportunityId,
                invoiceSequence
            );
            invoiceSequence++;

            if (invoiceNumber.length() > 80) {
                throw new AuraHandledException('Invoice number must be 80 characters or fewer.');
            }
            if (invoiceNumbersForUniqueness.contains(invoiceNumber)) {
                throw new AuraHandledException('Each invoice number in this batch must be unique.');
            }
            invoiceNumbersForUniqueness.add(invoiceNumber);
            invoiceNumberResolvedByOpportunityId.put(opportunityId, invoiceNumber);
        }

        if (!invoiceNumbersForUniqueness.isEmpty()) {
            Integer existingInvoiceCount = [
                SELECT COUNT()
                FROM Invoice__c
                WHERE Invoice_Number__c IN :invoiceNumbersForUniqueness
            ];
            if (existingInvoiceCount > 0) {
                throw new AuraHandledException(
                    'One or more invoice numbers are already used on another invoice. Enter a different number.'
                );
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        Map<Id, Invoice__c> invoiceByOpportunityId = new Map<Id, Invoice__c>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            String invoiceNumber = invoiceNumberResolvedByOpportunityId.get(opportunityId);
            Decimal invoiceTotal = invoiceTotalByOpportunityId.get(opportunityId);
            List<ServiceAppointment> groupedAppointments = appointmentsByOpportunityId.get(opportunityId);

            Opportunity headerOpportunity = opportunityById.get(opportunityId);
            Invoice__c invoiceRecord = new Invoice__c(
                Invoice_Number__c = invoiceNumber,
                Opportunity__c = opportunityId,
                Account__c = headerOpportunity != null ? headerOpportunity.AccountId : null,
                Status__c = INVOICE_STATUS_SENT,
                Invoice_Date__c = Date.today(),
                Due_Date__c = Date.today().addDays(30),
                Subtotal__c = invoiceTotal,
                Tax_Amount__c = 0,
                Total_Amount__c = invoiceTotal,
                Amount_Paid__c = 0,
                Balance_Due__c = invoiceTotal
            );
            invoicesToInsert.add(invoiceRecord);
            invoiceByOpportunityId.put(opportunityId, invoiceRecord);

            InvoiceGroupResultWrapper invoiceGroup = new InvoiceGroupResultWrapper();
            invoiceGroup.opportunityId = opportunityId;
            invoiceGroup.opportunityName = headerOpportunity != null ? headerOpportunity.Name : null;
            invoiceGroup.invoiceNumber = invoiceNumber;
            invoiceGroup.serviceAppointmentCount = groupedAppointments.size();
            result.invoiceGroups.add(invoiceGroup);
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }

        List<Invoice_Line__c> invoiceLinesToInsert = new List<Invoice_Line__c>();
        List<ServiceAppointment> serviceAppointmentsToUpdate = new List<ServiceAppointment>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Invoice__c invoiceRecord = invoiceByOpportunityId.get(opportunityId);
            if (invoiceRecord == null || invoiceRecord.Id == null) {
                continue;
            }

            for (ServiceAppointment appointment : appointmentsByOpportunityId.get(opportunityId)) {
                Decimal billableAmount = resolveBillableAmount(
                    appointment.ParentRecordId,
                    effectiveOpportunityByAppointmentId.get(appointment.Id),
                    workOrderById,
                    appointmentCountByWorkOrderId,
                    appointmentCountByWorkOrderAndOpportunityId,
                    opportunityById
                );
                invoiceLinesToInsert.add(new Invoice_Line__c(
                    Invoice__c = invoiceRecord.Id,
                    Service_Appointment__c = appointment.Id,
                    Opportunity__c = opportunityId,
                    Work_Order__c = appointment.ParentRecordId,
                    Description__c = 'Service Appointment ' + appointment.Id,
                    Quantity__c = 1,
                    Unit_Price__c = billableAmount,
                    Line_Total__c = billableAmount
                ));

                appointment.Invoice_Number__c = invoiceRecord.Invoice_Number__c;
                if (appointment.Opportunity__c == null) {
                    appointment.Opportunity__c = effectiveOpportunityByAppointmentId.get(appointment.Id);
                }
                serviceAppointmentsToUpdate.add(appointment);
            }
        }

        if (!invoiceLinesToInsert.isEmpty()) {
            insert invoiceLinesToInsert;
        }

        if (!serviceAppointmentsToUpdate.isEmpty()) {
            update serviceAppointmentsToUpdate;
        }

        result.invoicesCreated = result.invoiceGroups.size();
        result.serviceAppointmentsUpdated = serviceAppointmentsToUpdate.size();
        return result;
    }

    @AuraEnabled
    public static BillingControlMetricsWrapper getBillingControlMetrics() {
        BillingControlMetricsWrapper metrics = new BillingControlMetricsWrapper();

        AggregateResult[] completedMoreThanTwoDaysResults = [
            SELECT COUNT(Id) opportunityCount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c < LAST_N_DAYS:2
        ];
        metrics.completedMoreThan2Days = extractInteger(completedMoreThanTwoDaysResults, 'opportunityCount');

        AggregateResult[] readyToBillResults = [
            SELECT COUNT(Id) opportunityCount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c >= LAST_N_DAYS:2
        ];
        metrics.readyToBill = extractInteger(readyToBillResults, 'opportunityCount');

        AggregateResult[] unbilledRevenueResults = [
            SELECT SUM(Amount) totalAmount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
            AND Ready_for_Billing_Date__c < LAST_N_DAYS:2
        ];
        metrics.unbilledRevenue = extractDecimal(unbilledRevenueResults, 'totalAmount');

        Decimal outstandingArTotal = 0;
        for (Opportunity opportunityRecord : [
            SELECT Amount, Amount_Paid__c
            FROM Opportunity
            WHERE Billing_Status__c = :OUTSTANDING_RECEIVABLE
            OR Billing_Status__c = :PARTIALLY_PAID
        ]) {
            Decimal amount = opportunityRecord.Amount != null ? opportunityRecord.Amount : 0;
            Decimal amountPaid = (Decimal) opportunityRecord.get('Amount_Paid__c');
            outstandingArTotal += amount - (amountPaid != null ? amountPaid : 0);
        }
        metrics.outstandingAr = outstandingArTotal;

        return metrics;
    }

    @AuraEnabled
    public static PaymentReceiptResultWrapper postReceipt(PostReceiptInputWrapper input) {
        if (input == null || input.opportunityId == null) {
            throw new AuraHandledException('A valid opportunity is required.');
        }
        if (input.amountReceived == null || input.amountReceived <= 0) {
            throw new AuraHandledException('Payment amount must be greater than 0.');
        }
        if (input.paymentDate == null) {
            throw new AuraHandledException('Payment date is required.');
        }
        if (String.isBlank(input.paymentMethod)) {
            throw new AuraHandledException('Payment method is required.');
        }
        if (String.isBlank(input.referenceNumber)) {
            throw new AuraHandledException('Reference number is required.');
        }

        Opportunity opportunityRecord = [
            SELECT Id, Amount, Amount_Paid__c, Billing_Status__c, AccountId
            FROM Opportunity
            WHERE Id = :input.opportunityId
            LIMIT 1
            FOR UPDATE
        ];

        Decimal invoiceAmount = opportunityRecord.Amount != null ? opportunityRecord.Amount : 0;
        Decimal previouslyPaid = (Decimal) opportunityRecord.get('Amount_Paid__c');
        previouslyPaid = previouslyPaid != null ? previouslyPaid : 0;
        Decimal totalPaid = previouslyPaid + input.amountReceived;

        if (input.amountReceived > invoiceAmount - previouslyPaid) {
            throw new AuraHandledException('Payment amount cannot exceed the balance due.');
        }
        if (totalPaid > invoiceAmount) {
            throw new AuraHandledException('Payment amount cannot exceed the balance due.');
        }

        Invoice__c invoiceRecord = getOrCreateReceivableInvoice(opportunityRecord, invoiceAmount, previouslyPaid);

        insert new Invoice_Payment__c(
            Opportunity__c = input.opportunityId,
            Invoice__c = invoiceRecord.Id,
            Amount_Received__c = input.amountReceived,
            Payment_Date__c = input.paymentDate,
            Payment_Method__c = input.paymentMethod,
            Reference_Number__c = input.referenceNumber
        );

        String nextStatus = totalPaid < invoiceAmount ? PARTIALLY_PAID : PAID;
        update new Opportunity(
            Id = opportunityRecord.Id,
            Billing_Status__c = nextStatus
        );

        Decimal updatedInvoicePaid = (invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0) + input.amountReceived;
        Decimal updatedBalanceDue = invoiceAmount - updatedInvoicePaid;
        update new Invoice__c(
            Id = invoiceRecord.Id,
            Amount_Paid__c = updatedInvoicePaid,
            Balance_Due__c = updatedBalanceDue,
            Status__c = updatedBalanceDue <= 0 ? INVOICE_STATUS_PAID : INVOICE_STATUS_PARTIALLY_PAID
        );

        applyPartialCommissionAccrual(input.opportunityId, input.amountReceived, invoiceAmount, totalPaid >= invoiceAmount);

        PaymentReceiptResultWrapper result = new PaymentReceiptResultWrapper();
        result.totalPaid = totalPaid;
        result.balanceDue = invoiceAmount - totalPaid;
        result.billingStatus = nextStatus;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static CommissionMetricsWrapper getCommissionMetrics() {
        CommissionMetricsWrapper metrics = new CommissionMetricsWrapper();

        AggregateResult[] unbilledRevenueResults = [
            SELECT COUNT(Id) recordCount, SUM(Amount) totalAmount
            FROM Opportunity
            WHERE Billing_Status__c = :READY_FOR_BILLING
        ];
        metrics.unbilledRevenueCount = extractInteger(unbilledRevenueResults, 'recordCount');
        metrics.unbilledRevenue = extractDecimal(unbilledRevenueResults, 'totalAmount');

        AggregateResult[] revenueUnderCollectionResults = [
            SELECT COUNT(Id) recordCount, SUM(Amount) totalAmount
            FROM Opportunity
            WHERE Billing_Status__c = :OUTSTANDING_RECEIVABLE
        ];
        metrics.revenueUnderCollectionCount = extractInteger(revenueUnderCollectionResults, 'recordCount');
        metrics.revenueUnderCollection = extractDecimal(revenueUnderCollectionResults, 'totalAmount');

        AggregateResult[] commissionEarnedResults = [
            SELECT COUNT(Id) recordCount, SUM(Commission_Amount__c) totalAmount
            FROM Commission__c
            WHERE Opportunity__r.Billing_Status__c = :OUTSTANDING_RECEIVABLE
        ];
        metrics.commissionEarnedCount = extractInteger(commissionEarnedResults, 'recordCount');
        metrics.commissionEarned = extractDecimal(commissionEarnedResults, 'totalAmount');

        Decimal payableTotal = 0;
        Integer payableCount = 0;
        for (Commission__c commissionRecord : [
            SELECT Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__r.Billing_Status__c = :PAID
        ]) {
            Decimal commissionAmount = commissionRecord.Commission_Amount__c != null
                ? commissionRecord.Commission_Amount__c
                : 0;
            Decimal commissionPaid = commissionRecord.Commission_Paid__c != null
                ? commissionRecord.Commission_Paid__c
                : 0;

            if (commissionPaid < commissionAmount) {
                payableTotal += (commissionAmount - commissionPaid);
                payableCount++;
            }
        }
        metrics.commissionPayable = payableTotal;
        metrics.commissionPayableCount = payableCount;

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static List<SalespersonWrapper> getCommissionData(String subtabType) {
        String normalizedSubtabType = String.isBlank(subtabType)
            ? COMMISSION_EARNED
            : subtabType.trim().toLowerCase();

        List<Commission__c> commissionRecords;
        if (normalizedSubtabType == COMMISSION_PAYABLE) {
            commissionRecords = [
                SELECT Id,
                    Opportunity__c,
                    Opportunity__r.Name,
                    Opportunity__r.Account.Name,
                    Opportunity__r.Amount,
                    Opportunity__r.Amount_Paid__c,
                    Opportunity__r.Billing_Status__c,
                    Sales_Person__c,
                    Sales_Person__r.Name,
                    Commission_Amount__c,
                    Commission_Paid__c
                FROM Commission__c
                WHERE Opportunity__r.Billing_Status__c = :PAID
                ORDER BY Sales_Person__r.Name ASC NULLS LAST, Opportunity__r.Name ASC NULLS LAST
            ];
        } else {
            commissionRecords = [
                SELECT Id,
                    Opportunity__c,
                    Opportunity__r.Name,
                    Opportunity__r.Account.Name,
                    Opportunity__r.Amount,
                    Opportunity__r.Amount_Paid__c,
                    Opportunity__r.Billing_Status__c,
                    Sales_Person__c,
                    Sales_Person__r.Name,
                    Commission_Amount__c,
                    Commission_Paid__c
                FROM Commission__c
                WHERE Opportunity__r.Billing_Status__c = :OUTSTANDING_RECEIVABLE
                ORDER BY Sales_Person__r.Name ASC NULLS LAST, Opportunity__r.Name ASC NULLS LAST
            ];
        }

        List<SalespersonWrapper> results = new List<SalespersonWrapper>();
        Map<String, SalespersonWrapper> salespersonByKey = new Map<String, SalespersonWrapper>();

        for (Commission__c commissionRecord : commissionRecords) {
            Decimal commissionAmount = commissionRecord.Commission_Amount__c != null
                ? commissionRecord.Commission_Amount__c
                : 0;
            Decimal commissionPaid = commissionRecord.Commission_Paid__c != null
                ? commissionRecord.Commission_Paid__c
                : 0;

            if (normalizedSubtabType == COMMISSION_PAYABLE && commissionPaid >= commissionAmount) {
                continue;
            }

            String salespersonKey = commissionRecord.Sales_Person__c != null
                ? String.valueOf(commissionRecord.Sales_Person__c)
                : 'UNASSIGNED';
            SalespersonWrapper salesperson = salespersonByKey.get(salespersonKey);

            if (salesperson == null) {
                salesperson = new SalespersonWrapper();
                salesperson.salespersonId = commissionRecord.Sales_Person__c;
                salesperson.salespersonName = commissionRecord.Sales_Person__r != null
                    ? commissionRecord.Sales_Person__r.Name
                    : 'Unassigned';
                salesperson.totalAmount = 0;
                salesperson.totalCommission = 0;
                salesperson.totalPaid = 0;
                salesperson.opportunities = new List<OpportunityWrapper>();
                salespersonByKey.put(salespersonKey, salesperson);
                results.add(salesperson);
            }

            OpportunityWrapper opportunity = new OpportunityWrapper();
            opportunity.opportunityId = commissionRecord.Opportunity__c;
            opportunity.name = commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.Name : null;
            opportunity.opportunityName = opportunity.name;
            opportunity.accountName = commissionRecord.Opportunity__r != null && commissionRecord.Opportunity__r.Account != null
                ? commissionRecord.Opportunity__r.Account.Name
                : null;
            opportunity.amount = commissionRecord.Opportunity__r != null
                ? commissionRecord.Opportunity__r.Amount
                : null;
            opportunity.amountPaid = commissionRecord.Opportunity__r != null
                ? (Decimal) commissionRecord.Opportunity__r.get('Amount_Paid__c')
                : null;
            Decimal opportunityAmount = opportunity.amount != null ? opportunity.amount : 0;
            Decimal opportunityAmountPaid = opportunity.amountPaid != null ? opportunity.amountPaid : 0;
            opportunity.balanceDue = opportunityAmount - opportunityAmountPaid;
            opportunity.billingStatus = commissionRecord.Opportunity__r != null
                ? commissionRecord.Opportunity__r.Billing_Status__c
                : null;
            opportunity.commissionAmount = commissionAmount;
            opportunity.commissionPaid = commissionPaid;
            opportunity.commissionId = commissionRecord.Id;

            salesperson.totalAmount += opportunity.amount != null ? opportunity.amount : 0;
            salesperson.totalCommission += opportunity.commissionAmount != null ? opportunity.commissionAmount : 0;
            salesperson.totalPaid += opportunity.commissionPaid != null ? opportunity.commissionPaid : 0;
            salesperson.opportunities.add(opportunity);
        }

        return results;
    }

    @AuraEnabled
    public static void updateCommissionPaid(List<Id> commissionIds) {
        if (commissionIds == null || commissionIds.isEmpty()) {
            return;
        }

        List<Commission__c> commissionsToUpdate = new List<Commission__c>();
        for (Commission__c commissionRecord : [
            SELECT Id, Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Id IN :commissionIds
        ]) {
            if (commissionRecord.Commission_Paid__c != commissionRecord.Commission_Amount__c) {
                commissionRecord.Commission_Paid__c = commissionRecord.Commission_Amount__c;
                commissionsToUpdate.add(commissionRecord);
            }
        }

        if (!commissionsToUpdate.isEmpty()) {
            update commissionsToUpdate;
        }
    }

    @AuraEnabled
    public static CommissionResultWrapper createCommissionRecords(List<CommissionInputWrapper> inputs) {
        System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords START');
        System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords inputs=' + JSON.serialize(inputs));

        CommissionResultWrapper result = new CommissionResultWrapper();
        result.successCount = 0;
        result.errorMessages = new List<String>();

        if (inputs == null || inputs.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords exiting early: inputs empty');
            return result;
        }

        Map<Id, CommissionInputWrapper> inputByOpportunityId = new Map<Id, CommissionInputWrapper>();
        Set<Id> opportunityIds = new Set<Id>();
        for (CommissionInputWrapper input : inputs) {
            System.debug(LoggingLevel.ERROR, 'BCC iterating input=' + JSON.serialize(input));
            if (input != null && input.opportunityId != null) {
                inputByOpportunityId.put(input.opportunityId, input);
                opportunityIds.add(input.opportunityId);
            }
        }

        System.debug(LoggingLevel.ERROR, 'BCC inputByOpportunityId keys=' + inputByOpportunityId.keySet());
        System.debug(LoggingLevel.ERROR, 'BCC opportunityIds=' + opportunityIds);

        if (inputByOpportunityId.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords exiting early: no valid opportunity ids');
            return result;
        }

        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, OwnerId, Owner.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);

        System.debug(LoggingLevel.ERROR, 'BCC queried opportunities count=' + opportunityById.size());
        System.debug(LoggingLevel.ERROR, 'BCC queried opportunities=' + JSON.serialize(opportunityById.values()));

        List<Commission__c> commissionRecords = new List<Commission__c>();
        List<Id> commissionOpportunityIds = new List<Id>();

        for (CommissionInputWrapper input : inputs) {
            if (input == null || input.opportunityId == null) {
                System.debug(LoggingLevel.ERROR, 'BCC skipping null/invalid input=' + JSON.serialize(input));
                continue;
            }

            Opportunity opportunityRecord = opportunityById.get(input.opportunityId);
            Id salesPersonId = input.ownerId != null
                ? input.ownerId
                : (opportunityRecord != null ? opportunityRecord.OwnerId : null);

            Commission__c commissionRecord = new Commission__c();
            commissionRecord.Opportunity__c = input.opportunityId;
            commissionRecord.Commission_Rate__c = input.commissionRate;
            commissionRecord.Sales_Person__c = salesPersonId;
            commissionRecord.Unique_Key__c = String.valueOf(input.opportunityId) + String.valueOf(salesPersonId);
            commissionRecords.add(commissionRecord);
            commissionOpportunityIds.add(input.opportunityId);

            System.debug(LoggingLevel.ERROR,
                'BCC prepared commissionRecord for opportunity=' + input.opportunityId +
                ', salesPersonId=' + salesPersonId +
                ', commissionRate=' + input.commissionRate +
                ', uniqueKey=' + commissionRecord.Unique_Key__c
            );
        }

        System.debug(LoggingLevel.ERROR, 'BCC commissionRecords size=' + commissionRecords.size());
        System.debug(LoggingLevel.ERROR, 'BCC commissionRecords payload=' + JSON.serialize(commissionRecords));
        System.debug(LoggingLevel.ERROR, 'BCC commissionOpportunityIds=' + commissionOpportunityIds);

        if (commissionRecords.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords exiting early: no commission records prepared');
            return result;
        }

        Database.SaveResult[] saveResults = Database.insert(commissionRecords, false);
        System.debug(LoggingLevel.ERROR, 'BCC saveResults size=' + saveResults.size());
        Set<Id> successfulOpportunityIds = new Set<Id>();

        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Id opportunityId = commissionOpportunityIds[index];
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            String opportunityName = opportunityRecord != null ? opportunityRecord.Name : String.valueOf(opportunityId);
            String ownerName = opportunityRecord != null && opportunityRecord.Owner != null
                ? opportunityRecord.Owner.Name
                : '';

            System.debug(LoggingLevel.ERROR,
                'BCC saveResult index=' + index +
                ', opportunityId=' + opportunityId +
                ', success=' + saveResult.isSuccess() +
                ', id=' + saveResult.getId()
            );

            if (saveResult.isSuccess()) {
                successfulOpportunityIds.add(opportunityId);
                result.successCount = (result.successCount == null ? 0 : result.successCount) + 1;
                continue;
            }

            for (Database.Error dbError : saveResult.getErrors()) {
                String message = dbError.getMessage();
                System.debug(LoggingLevel.ERROR,
                    'BCC saveResult error opportunity=' + opportunityId +
                    ', statusCode=' + dbError.getStatusCode() +
                    ', message=' + message +
                    ', fields=' + dbError.getFields()
                );
                if (String.isNotBlank(message) &&
                    (message.contains('DUPLICATE_VALUE') || message.contains('duplicate value'))) {
                    result.errorMessages.add(
                        'Commission already exists for Opportunity: ' + opportunityName +
                        ' and Owner: ' + ownerName
                    );
                } else {
                    result.errorMessages.add(
                        'Opportunity: ' + opportunityName +
                        ', Owner: ' + ownerName +
                        ' - ' + message
                    );
                }
            }
        }

        System.debug(LoggingLevel.ERROR, 'BCC successfulOpportunityIds=' + successfulOpportunityIds);
        System.debug(LoggingLevel.ERROR, 'BCC interim result=' + JSON.serialize(result));

        if (!successfulOpportunityIds.isEmpty()) {
            List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
            for (Id opportunityId : successfulOpportunityIds) {
                opportunitiesToUpdate.add(new Opportunity(
                    Id = opportunityId,
                    Billing_Status__c = OUTSTANDING_RECEIVABLE
                ));
            }
            System.debug(LoggingLevel.ERROR, 'BCC opportunitiesToUpdate=' + JSON.serialize(opportunitiesToUpdate));
            update opportunitiesToUpdate;
            System.debug(LoggingLevel.ERROR, 'BCC opportunity update complete count=' + opportunitiesToUpdate.size());
        }

        if (result.successCount == 0 && result.errorMessages.isEmpty()) {
            result.errorMessages.add('No commission records were created.');
            System.debug(LoggingLevel.ERROR, 'BCC added fallback no-records-created message');
        }

        System.debug(LoggingLevel.ERROR, 'BCC createCommissionRecords END result=' + JSON.serialize(result));
        return result;
    }

    private static Map<Id, WorkOrder> buildWorkOrderLookup(List<ServiceAppointment> appointments) {
        Set<Id> workOrderIds = new Set<Id>();
        for (ServiceAppointment appointment : appointments) {
            if (appointment.ParentRecordId != null) {
                workOrderIds.add(appointment.ParentRecordId);
            }
        }

        if (workOrderIds.isEmpty()) {
            return new Map<Id, WorkOrder>();
        }

        return new Map<Id, WorkOrder>([
            SELECT Id, WorkOrderNumber, TotalPrice
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
    }

    private static Map<Id, Integer> buildAppointmentCountByWorkOrder(List<ServiceAppointment> appointments) {
        Map<Id, Integer> appointmentCountByWorkOrderId = new Map<Id, Integer>();
        for (ServiceAppointment appointment : appointments) {
            if (appointment.ParentRecordId == null) {
                continue;
            }
            Integer currentCount = appointmentCountByWorkOrderId.containsKey(appointment.ParentRecordId)
                ? appointmentCountByWorkOrderId.get(appointment.ParentRecordId)
                : 0;
            appointmentCountByWorkOrderId.put(appointment.ParentRecordId, currentCount + 1);
        }
        return appointmentCountByWorkOrderId;
    }

    private static Map<String, Integer> buildAppointmentCountByWorkOrderAndOpportunity(
        List<ServiceAppointment> appointments,
        Map<Id, Id> effectiveOpportunityByAppointmentId
    ) {
        Map<String, Integer> countByWorkOrderAndOpportunity = new Map<String, Integer>();
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord.ParentRecordId == null) {
                continue;
            }
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            if (effectiveOpportunityId == null) {
                continue;
            }
            String key = workOrderOpportunityKey(appointmentRecord.ParentRecordId, effectiveOpportunityId);
            Integer current = countByWorkOrderAndOpportunity.containsKey(key)
                ? countByWorkOrderAndOpportunity.get(key)
                : 0;
            countByWorkOrderAndOpportunity.put(key, current + 1);
        }
        return countByWorkOrderAndOpportunity;
    }

    private static String workOrderOpportunityKey(Id workOrderId, Id opportunityId) {
        return String.valueOf(workOrderId) + '|' + String.valueOf(opportunityId);
    }

    /**
     * Prefers WorkOrder.TotalPrice split across service appointments on that work order.
     * When the work order has no positive total, falls back to Opportunity.Amount split across
     * appointments on the same work order that bill to the same opportunity (multi-opportunity work
     * orders can still allocate each opportunity's amount only across its own appointments).
     */
    private static Decimal resolveBillableAmount(
        Id workOrderId,
        Id effectiveOpportunityId,
        Map<Id, WorkOrder> workOrderById,
        Map<Id, Integer> appointmentCountByWorkOrderId,
        Map<String, Integer> appointmentCountByWorkOrderAndOpportunityId,
        Map<Id, Opportunity> opportunityById
    ) {
        if (workOrderId == null || effectiveOpportunityId == null) {
            return 0;
        }

        WorkOrder workOrderRecord = workOrderById != null ? workOrderById.get(workOrderId) : null;
        if (workOrderRecord != null
            && workOrderRecord.TotalPrice != null
            && workOrderRecord.TotalPrice > 0
        ) {
            Integer shareCount = appointmentCountByWorkOrderId.containsKey(workOrderId)
                ? appointmentCountByWorkOrderId.get(workOrderId)
                : 0;
            if (shareCount <= 0) {
                return 0;
            }
            return workOrderRecord.TotalPrice / shareCount;
        }

        Opportunity opportunityRecord = opportunityById != null
            ? opportunityById.get(effectiveOpportunityId)
            : null;
        if (opportunityRecord == null || opportunityRecord.Amount == null) {
            return 0;
        }

        String key = workOrderOpportunityKey(workOrderId, effectiveOpportunityId);
        Integer opportunityShareCount = appointmentCountByWorkOrderAndOpportunityId.containsKey(key)
            ? appointmentCountByWorkOrderAndOpportunityId.get(key)
            : 0;
        if (opportunityShareCount <= 0) {
            opportunityShareCount = 1;
        }

        return opportunityRecord.Amount / opportunityShareCount;
    }

    private static Invoice__c getOrCreateReceivableInvoice(
        Opportunity opportunityRecord,
        Decimal invoiceAmount,
        Decimal previouslyPaid
    ) {
        List<Invoice__c> existingInvoices = [
            SELECT Id,
                Invoice_Number__c,
                Amount_Paid__c,
                Balance_Due__c,
                Total_Amount__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
            AND Status__c != :INVOICE_STATUS_PAID
            LIMIT 1
            FOR UPDATE
        ];

        if (!existingInvoices.isEmpty()) {
            return existingInvoices[0];
        }

        String invoiceNumber = buildInvoiceNumber(opportunityRecord.Id, 1);
        Invoice__c invoiceRecord = new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = opportunityRecord.Id,
            Account__c = opportunityRecord.AccountId,
            Status__c = INVOICE_STATUS_SENT,
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = invoiceAmount,
            Tax_Amount__c = 0,
            Total_Amount__c = invoiceAmount,
            Amount_Paid__c = previouslyPaid,
            Balance_Due__c = invoiceAmount - previouslyPaid
        );
        insert invoiceRecord;
        return invoiceRecord;
    }

    private static void applyPartialCommissionAccrual(
        Id opportunityId,
        Decimal paymentAmount,
        Decimal invoiceAmount,
        Boolean isFinalPayment
    ) {
        if (opportunityId == null || paymentAmount == null || paymentAmount <= 0 || invoiceAmount == null || invoiceAmount <= 0) {
            return;
        }

        Decimal paymentRatio = paymentAmount / invoiceAmount;
        List<Commission__c> commissionsToUpdate = new List<Commission__c>();
        for (Commission__c commissionRecord : [
            SELECT Id, Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__c = :opportunityId
        ]) {
            Decimal commissionAmount = commissionRecord.Commission_Amount__c != null
                ? commissionRecord.Commission_Amount__c
                : 0;
            Decimal commissionPaid = commissionRecord.Commission_Paid__c != null
                ? commissionRecord.Commission_Paid__c
                : 0;

            if (commissionAmount <= 0 || commissionPaid >= commissionAmount) {
                continue;
            }

            if (isFinalPayment) {
                commissionRecord.Commission_Paid__c = commissionAmount;
                commissionsToUpdate.add(commissionRecord);
                continue;
            }

            Decimal accrualAmount = (commissionAmount * paymentRatio).setScale(2);
            Decimal remainingAmount = commissionAmount - commissionPaid;
            Decimal commissionDelta = accrualAmount > remainingAmount ? remainingAmount : accrualAmount;
            if (commissionDelta <= 0) {
                continue;
            }
            commissionRecord.Commission_Paid__c = commissionPaid + commissionDelta;
            commissionsToUpdate.add(commissionRecord);
        }

        if (!commissionsToUpdate.isEmpty()) {
            update commissionsToUpdate;
        }
    }

    private static List<ServiceAppointmentRowWrapper> buildBillableServiceAppointmentRows() {
        List<ServiceAppointment> candidateAppointments = [
            SELECT Id,
                AppointmentNumber,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Account.Name,
                Opportunity__r.Billing_Status__c,
                ParentRecordId,
                OwnerId,
                Owner.Name,
                Status,
                ActualEndTime,
                Invoice_Number__c
            FROM ServiceAppointment
            WHERE Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND Invoice_Number__c = NULL
            AND ParentRecordId != NULL
        ];

        if (candidateAppointments.isEmpty()) {
            return new List<ServiceAppointmentRowWrapper>();
        }

        Set<Id> workOrderIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : candidateAppointments) {
            workOrderIds.add(appointmentRecord.ParentRecordId);
        }

        Map<Id, Id> workOrderToSingleOpportunityId = buildWorkOrderToSingleOpportunityMap(workOrderIds);

        Map<Id, Id> effectiveOpportunityByAppointmentId = new Map<Id, Id>();
        for (ServiceAppointment appointmentRecord : candidateAppointments) {
            Id effectiveOpportunityId = resolveEffectiveOpportunityId(appointmentRecord, workOrderToSingleOpportunityId);
            if (effectiveOpportunityId != null) {
                effectiveOpportunityByAppointmentId.put(appointmentRecord.Id, effectiveOpportunityId);
            }
        }

        if (effectiveOpportunityByAppointmentId.isEmpty()) {
            return new List<ServiceAppointmentRowWrapper>();
        }

        Set<Id> resolvedOpportunityIds = new Set<Id>(effectiveOpportunityByAppointmentId.values());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, Billing_Status__c, Amount, Account.Name
            FROM Opportunity
            WHERE Id IN :resolvedOpportunityIds
        ]);

        List<ServiceAppointment> appointments = new List<ServiceAppointment>();
        for (ServiceAppointment appointmentRecord : candidateAppointments) {
            if (!effectiveOpportunityByAppointmentId.containsKey(appointmentRecord.Id)) {
                continue;
            }
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            Opportunity resolvedOpportunity = opportunityById.get(effectiveOpportunityId);
            if (
                resolvedOpportunity == null
                || !isInvoicingPageOpportunityBillingStatus(resolvedOpportunity.Billing_Status__c)
            ) {
                continue;
            }
            appointments.add(appointmentRecord);
        }

        if (appointments.isEmpty()) {
            return new List<ServiceAppointmentRowWrapper>();
        }

        workOrderIds.clear();
        Map<Id, Integer> appointmentCountByWorkOrderId = new Map<Id, Integer>();
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord.ParentRecordId != null) {
                workOrderIds.add(appointmentRecord.ParentRecordId);
                Integer currentCount = appointmentCountByWorkOrderId.containsKey(appointmentRecord.ParentRecordId)
                    ? appointmentCountByWorkOrderId.get(appointmentRecord.ParentRecordId)
                    : 0;
                appointmentCountByWorkOrderId.put(appointmentRecord.ParentRecordId, currentCount + 1);
            }
        }

        Map<String, Integer> appointmentCountByWorkOrderAndOpportunityId =
            buildAppointmentCountByWorkOrderAndOpportunity(appointments, effectiveOpportunityByAppointmentId);

        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>();
        if (!workOrderIds.isEmpty()) {
            workOrderById = new Map<Id, WorkOrder>([
                SELECT Id, WorkOrderNumber, TotalPrice
                FROM WorkOrder
                WHERE Id IN :workOrderIds
            ]);
        }

        List<ServiceAppointmentRowWrapper> rows = new List<ServiceAppointmentRowWrapper>();
        for (ServiceAppointment appointment : appointments) {
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointment.Id);
            Opportunity resolvedOpportunity = opportunityById.get(effectiveOpportunityId);

            ServiceAppointmentRowWrapper row = new ServiceAppointmentRowWrapper();
            row.serviceAppointmentId = appointment.Id;
            row.serviceAppointmentNumber = appointment.AppointmentNumber;
            row.opportunityId = effectiveOpportunityId;
            row.opportunityName = resolvedOpportunity != null ? resolvedOpportunity.Name : null;
            row.accountName = resolvedOpportunity != null && resolvedOpportunity.Account != null
                ? resolvedOpportunity.Account.Name
                : null;
            row.workOrderId = appointment.ParentRecordId;
            row.workOrderNumber = workOrderById.containsKey(appointment.ParentRecordId)
                ? workOrderById.get(appointment.ParentRecordId).WorkOrderNumber
                : null;
            row.completionDateTime = appointment.ActualEndTime;
            row.technicianId = appointment.OwnerId;
            row.technicianName = appointment.Owner != null ? appointment.Owner.Name : null;
            row.billingStatus = appointment.Invoice_Number__c == null ? 'Pending Invoice' : 'Billed';
            row.invoiceNumber = appointment.Invoice_Number__c;

            row.billableAmount = resolveBillableAmount(
                appointment.ParentRecordId,
                effectiveOpportunityId,
                workOrderById,
                appointmentCountByWorkOrderId,
                appointmentCountByWorkOrderAndOpportunityId,
                opportunityById
            );

            rows.add(row);
        }

        return rows;
    }

    private static String resolveInvoiceNumberForBilling(
        Id opportunityId,
        Map<String, String> invoiceNumberByOpportunityId,
        Integer sequenceForAuto
    ) {
        if (invoiceNumberByOpportunityId != null) {
            String explicit = invoiceNumberByOpportunityId.get(String.valueOf(opportunityId));
            if (!String.isBlank(explicit)) {
                return explicit.trim();
            }
        }
        return buildInvoiceNumber(opportunityId, sequenceForAuto);
    }

    private static String buildInvoiceNumber(Id opportunityId, Integer sequence) {
        String opportunityKey = String.valueOf(opportunityId);
        if (opportunityKey.length() > 5) {
            opportunityKey = opportunityKey.substring(opportunityKey.length() - 5, opportunityKey.length());
        }
        String sequenceValue = String.valueOf(sequence).leftPad(2, '0');
        return 'INV-' + Datetime.now().formatGMT('yyyyMMdd') + '-' + opportunityKey + '-' + sequenceValue;
    }

    private class ServiceAppointmentGroupNameComparator implements Comparator<ServiceAppointmentOpportunityGroupWrapper> {
        public Integer compare(
            ServiceAppointmentOpportunityGroupWrapper left,
            ServiceAppointmentOpportunityGroupWrapper right
        ) {
            String leftName = String.isNotBlank(left.opportunityName) ? left.opportunityName : '';
            String rightName = String.isNotBlank(right.opportunityName) ? right.opportunityName : '';
            Integer nameCompare = leftName.toLowerCase().compareTo(rightName.toLowerCase());
            if (nameCompare != 0) {
                return nameCompare;
            }
            String leftId = left.opportunityId != null ? String.valueOf(left.opportunityId) : '';
            String rightId = right.opportunityId != null ? String.valueOf(right.opportunityId) : '';
            return leftId.compareTo(rightId);
        }
    }

    private class ServiceAppointmentRowCompletionComparator implements Comparator<ServiceAppointmentRowWrapper> {
        public Integer compare(ServiceAppointmentRowWrapper left, ServiceAppointmentRowWrapper right) {
            if (left.completionDateTime == null && right.completionDateTime == null) {
                return compareAppointmentNumber(left.serviceAppointmentNumber, right.serviceAppointmentNumber);
            }
            if (left.completionDateTime == null) {
                return 1;
            }
            if (right.completionDateTime == null) {
                return -1;
            }
            if (left.completionDateTime > right.completionDateTime) {
                return -1;
            }
            if (left.completionDateTime < right.completionDateTime) {
                return 1;
            }
            return compareAppointmentNumber(left.serviceAppointmentNumber, right.serviceAppointmentNumber);
        }

        private Integer compareAppointmentNumber(String leftNumber, String rightNumber) {
            String leftValue = String.isNotBlank(leftNumber) ? leftNumber : '';
            String rightValue = String.isNotBlank(rightNumber) ? rightNumber : '';
            return leftValue.toLowerCase().compareTo(rightValue.toLowerCase());
        }
    }

    private static List<OpportunityWrapper> buildOpportunityWrappers(List<Opportunity> opportunities) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opportunityRecord : opportunities) {
            opportunityIds.add(opportunityRecord.Id);
        }

        Map<Id, List<WorkOrderWrapper>> workOrdersByOpportunityId = new Map<Id, List<WorkOrderWrapper>>();
        if (!opportunityIds.isEmpty()) {
            for (Opportunity_WorkOrder__c junctionRecord : [
                SELECT Opportunity__c,
                    Work_Order__r.Id,
                    Work_Order__r.WorkOrderNumber,
                    Work_Order__r.Subject,
                    Work_Order__r.Priority,
                    Work_Order__r.WorkType.Name
                FROM Opportunity_WorkOrder__c
                WHERE Opportunity__c IN :opportunityIds
                ORDER BY Work_Order__r.WorkOrderNumber ASC NULLS LAST
            ]) {
                if (!workOrdersByOpportunityId.containsKey(junctionRecord.Opportunity__c)) {
                    workOrdersByOpportunityId.put(junctionRecord.Opportunity__c, new List<WorkOrderWrapper>());
                }

                WorkOrderWrapper workOrder = new WorkOrderWrapper();
                workOrder.id = junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.Id : null;
                workOrder.workOrderNumber = junctionRecord.Work_Order__r != null
                    ? junctionRecord.Work_Order__r.WorkOrderNumber
                    : null;
                workOrder.subject = junctionRecord.Work_Order__r != null
                    ? junctionRecord.Work_Order__r.Subject
                    : null;
                workOrder.priority = junctionRecord.Work_Order__r != null
                    ? junctionRecord.Work_Order__r.Priority
                    : null;
                workOrder.workTypeName = junctionRecord.Work_Order__r != null && junctionRecord.Work_Order__r.WorkType != null
                    ? junctionRecord.Work_Order__r.WorkType.Name
                    : null;

                workOrdersByOpportunityId.get(junctionRecord.Opportunity__c).add(workOrder);
            }
        }

        List<OpportunityWrapper> results = new List<OpportunityWrapper>();
        for (Opportunity opportunityRecord : opportunities) {
            OpportunityWrapper wrapper = new OpportunityWrapper();
            wrapper.opportunityId = opportunityRecord.Id;
            wrapper.name = opportunityRecord.Name;
            wrapper.accountName = opportunityRecord.Account != null ? opportunityRecord.Account.Name : null;
            wrapper.stage = opportunityRecord.StageName;
            wrapper.amount = opportunityRecord.Amount;
            wrapper.closeDate = opportunityRecord.CloseDate;
            wrapper.ownerId = opportunityRecord.OwnerId;
            wrapper.ownerName = opportunityRecord.Owner != null ? opportunityRecord.Owner.Name : null;
            wrapper.billingStatus = (String) opportunityRecord.get('Billing_Status__c');
            Decimal amountPaid = (Decimal) opportunityRecord.get('Amount_Paid__c');
            wrapper.amountPaid = amountPaid != null ? amountPaid : 0;
            wrapper.balanceDue = (wrapper.amount != null ? wrapper.amount : 0) - wrapper.amountPaid;
            Datetime readyForBillingDatetime = (Datetime) opportunityRecord.get('Ready_for_Billing_Date__c');
            wrapper.readyForBillingDate = readyForBillingDatetime != null ? readyForBillingDatetime.date() : null;
            wrapper.workOrders = workOrdersByOpportunityId.containsKey(opportunityRecord.Id)
                ? workOrdersByOpportunityId.get(opportunityRecord.Id)
                : new List<WorkOrderWrapper>();
            results.add(wrapper);
        }

        return results;
    }

    private static Decimal extractDecimal(List<AggregateResult> results, String fieldName) {
        if (results.isEmpty() || results[0].get(fieldName) == null) {
            return 0;
        }
        return (Decimal) results[0].get(fieldName);
    }

    private static Integer extractInteger(List<AggregateResult> results, String fieldName) {
        if (results.isEmpty() || results[0].get(fieldName) == null) {
            return 0;
        }

        Object value = results[0].get(fieldName);
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return Integer.valueOf(String.valueOf(value));
        }
        return 0;
    }

    public class OpportunityWrapper {
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public String name;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String stage;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal balanceDue;
        @AuraEnabled public Date readyForBillingDate;
        @AuraEnabled public Decimal commissionAmount;
        @AuraEnabled public Decimal commissionPaid;
        @AuraEnabled public Id commissionId;
        @AuraEnabled public List<WorkOrderWrapper> workOrders;
    }

    public class WorkOrderWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String workTypeName;
    }

    public class OpportunityBillingMetricsWrapper {
        @AuraEnabled public Integer readyForBillingLast2Days;
        @AuraEnabled public Integer awaitedBilling;
        @AuraEnabled public Integer outstandingReceivables;
        @AuraEnabled public Decimal totalUnbilledRevenue;
    }

    public class BillingControlMetricsWrapper {
        @AuraEnabled public Integer completedMoreThan2Days;
        @AuraEnabled public Integer readyToBill;
        @AuraEnabled public Decimal unbilledRevenue;
        @AuraEnabled public Decimal outstandingAr;
    }

    public class CommissionMetricsWrapper {
        @AuraEnabled public Decimal unbilledRevenue;
        @AuraEnabled public Integer unbilledRevenueCount;
        @AuraEnabled public Decimal revenueUnderCollection;
        @AuraEnabled public Integer revenueUnderCollectionCount;
        @AuraEnabled public Decimal commissionEarned;
        @AuraEnabled public Integer commissionEarnedCount;
        @AuraEnabled public Decimal commissionPayable;
        @AuraEnabled public Integer commissionPayableCount;
    }

    public class SalespersonWrapper {
        @AuraEnabled public Id salespersonId;
        @AuraEnabled public String salespersonName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalCommission;
        @AuraEnabled public Decimal totalPaid;
        @AuraEnabled public List<OpportunityWrapper> opportunities;
    }

    public class ServiceAppointmentRowWrapper {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Datetime completionDateTime;
        @AuraEnabled public Id technicianId;
        @AuraEnabled public String technicianName;
        @AuraEnabled public Decimal billableAmount;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public String invoiceNumber;
    }

    public class ServiceAppointmentOpportunityGroupWrapper {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public Decimal totalBillableAmount;
        @AuraEnabled public String billingState;
        @AuraEnabled public List<ServiceAppointmentRowWrapper> rows;
    }

    public class InvoiceGroupResultWrapper {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public Integer serviceAppointmentCount;
    }

    public class CompleteBillingResultWrapper {
        @AuraEnabled public Integer invoicesCreated { get; set; }
        @AuraEnabled public Integer serviceAppointmentsUpdated { get; set; }
        @AuraEnabled public List<InvoiceGroupResultWrapper> invoiceGroups { get; set; }
    }

    public class CommissionInputWrapper {
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public Decimal commissionRate { get; set; }
    }

    public class CommissionResultWrapper {
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public List<String> errorMessages { get; set; }
    }

    public class PostReceiptInputWrapper {
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Decimal amountReceived { get; set; }
        @AuraEnabled public Date paymentDate { get; set; }
        @AuraEnabled public String paymentMethod { get; set; }
        @AuraEnabled public String referenceNumber { get; set; }
    }

    public class PaymentReceiptResultWrapper {
        @AuraEnabled public Decimal totalPaid { get; set; }
        @AuraEnabled public Decimal balanceDue { get; set; }
        @AuraEnabled public String billingStatus { get; set; }
    }
}