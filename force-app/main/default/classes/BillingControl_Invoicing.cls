/**
 * Billing lifecycle and commissions: order-diary-backed billing, receivables, and commission
 * metrics plus receipt posting helpers. Order is the source of truth for BCC Orders and
 * Invoicing, with Invoice_Line__c and Commission__c linked back to Order for Receivables.
 */
public with sharing class BillingControl_Invoicing {
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';
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
    /** Legacy value kept for compatibility with existing records/orgs. */
    private static final String OUTSTANDING_RECEIVABLE = 'Billed (Outstanding Receivable)';
    /** Required target status for Complete Billing. */
    private static final String OUTSTANDING_RECEIVABLES = 'Billed (Outstanding Receivables)';
    private static final List<String> OUTSTANDING_RECEIVABLE_BILLING_STATUSES = new List<String>{
        OUTSTANDING_RECEIVABLE,
        OUTSTANDING_RECEIVABLES
    };
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final String KPI_CATEGORY_REVENUE_UNDER_COLLECTION = 'REVENUE_UNDER_COLLECTION';
    private static final String KPI_CATEGORY_COMMISSION_EARNED = 'COMMISSION_EARNED';
    private static final String KPI_CATEGORY_COMMISSION_PAYABLE = 'COMMISSION_PAYABLE';
    private static final String KPI_LABEL_REVENUE_UNDER_COLLECTION = 'Accounts Receivable (A/R)';
    private static final String KPI_LABEL_COMMISSION_EARNED = 'Commission Accrued';
    private static final String KPI_LABEL_COMMISSION_PAYABLE = 'Commission Payable';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final String BILLING_STATE_READY = 'Pending Invoice';
    private static final String BILLING_STATE_PARTIAL = 'Partial';
    private static final String KPI_CATEGORY_AGED_COMPLETED = 'AGED_COMPLETED';
    private static final String KPI_CATEGORY_READY_TO_BILL = 'READY_TO_BILL';
    private static final String KPI_CATEGORY_UNBILLED_REVENUE = 'UNBILLED_REVENUE';
    private static final String KPI_LABEL_AGED_COMPLETED = 'Aged Ready to Bill (>2 Days)';
    private static final String KPI_LABEL_READY_TO_BILL = 'Ready to Bill';
    private static final String KPI_LABEL_UNBILLED_REVENUE = 'Uninvoiced Amount';
    private static final String INVOICE_STATUS_DRAFT = 'Draft';
    private static final String INVOICE_STATUS_SENT = 'Sent';
    private static final String INVOICE_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String INVOICE_STATUS_PAID = 'Paid';
    private static final String ORDER_DIARY_STATUS_READY_TO_BILL = 'Ready to Bill';
    private static final String ORDER_DIARY_STATUS_INVOICED = 'Invoiced';
    private static final String ORDER_DIARY_STATUS_PAID = 'Paid';
    private static final String ORDER_DIARY_STATUS_CANCELLED = 'Cancelled';
    private static final String SERVICE_APPOINTMENT_WO_INV_STATUS_FIELD = 'WO_Inv_Status__c';
    private static final List<String> EXCLUDED_INVOICING_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Billing Completed',
        'Cannot Complete – Rescheduled'
    };

    private static Boolean isInvoicingPageOpportunityBillingStatus(String billingStatus) {
        return String.isNotBlank(billingStatus) && INVOICING_PAGE_OPPORTUNITY_BILLING_STATUSES.contains(billingStatus);
    }

    private static AuraHandledException buildHandledException(String message) {
        AuraHandledException exceptionRecord = new AuraHandledException(message);
        exceptionRecord.setMessage(message);
        return exceptionRecord;
    }

    private static Boolean isOutstandingReceivableStatus(String billingStatus) {
        return String.isNotBlank(billingStatus) && OUTSTANDING_RECEIVABLE_BILLING_STATUSES.contains(billingStatus);
    }

    /**
     * Prefer the required plural status when it exists in picklist metadata, otherwise fall back
     * to the legacy singular value to avoid runtime DML failures in orgs that haven't migrated yet.
     */
    private static String getOutstandingReceivableStatusForUpdate() {
        List<Schema.PicklistEntry> entries = Opportunity.Billing_Status__c.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry != null && entry.isActive() && entry.getValue() == OUTSTANDING_RECEIVABLES) {
                return OUTSTANDING_RECEIVABLES;
            }
        }
        return OUTSTANDING_RECEIVABLE;
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
            WHERE Billing_Status__c IN :OUTSTANDING_RECEIVABLE_BILLING_STATUSES
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
            WHERE Billing_Status__c IN :OUTSTANDING_RECEIVABLE_BILLING_STATUSES
        ];
        metrics.outstandingReceivables = extractInteger(outstandingReceivableResults, 'opportunityCount');

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static BillingControlMetricsWrapper getServiceAppointmentBillingMetrics() {
        return getServiceAppointmentBillingMetricsWithRefresh(null);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControlMetricsWrapper getServiceAppointmentBillingMetricsWithRefresh(Long refreshToken) {
        return getServiceAppointmentBillingMetricsWithRefresh(refreshToken, null);
    }

    public static BillingControlMetricsWrapper getServiceAppointmentBillingMetricsWithRefresh(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        // refreshToken intentionally unused in server logic; it exists to vary cache keys on demand.
        Long ignoredRefreshToken = refreshToken;
        BillingControlMetricsWrapper metrics = new BillingControlMetricsWrapper();
        // The aged category is retained only for backward-compatible response shape. Invoicing
        // eligibility must not be restricted by ActualEndTime.
        metrics.completedMoreThan2Days = 0;
        metrics.readyToBill = queryReadyToInvoiceCount(filterContext, false);
        metrics.unbilledRevenue = queryReadyToInvoiceRevenue(filterContext);
        metrics.outstandingAr = 0;

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroups() {
        return getBillableServiceAppointmentGroupsWithRefresh(null);
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroupsWithRefresh(Long refreshToken) {
        return getBillableServiceAppointmentGroupsWithRefresh(refreshToken, null);
    }

    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroupsWithRefresh(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        // refreshToken intentionally unused in server logic; it exists to vary cache keys on demand.
        Long ignoredRefreshToken = refreshToken;
        List<ServiceAppointmentRowWrapper> rows = buildBillableServiceAppointmentRows(filterContext);
        List<ServiceAppointmentKpiCategoryWrapper> sections = new List<ServiceAppointmentKpiCategoryWrapper>{
            new ServiceAppointmentKpiCategoryWrapper(KPI_CATEGORY_AGED_COMPLETED, KPI_LABEL_AGED_COMPLETED),
            new ServiceAppointmentKpiCategoryWrapper(KPI_CATEGORY_READY_TO_BILL, KPI_LABEL_READY_TO_BILL),
            new ServiceAppointmentKpiCategoryWrapper(KPI_CATEGORY_UNBILLED_REVENUE, KPI_LABEL_UNBILLED_REVENUE)
        };

        Map<String, List<ServiceAppointmentRowWrapper>> appointmentRowsByCategory =
            new Map<String, List<ServiceAppointmentRowWrapper>>{
                KPI_CATEGORY_AGED_COMPLETED => new List<ServiceAppointmentRowWrapper>(),
                KPI_CATEGORY_READY_TO_BILL => new List<ServiceAppointmentRowWrapper>(),
                KPI_CATEGORY_UNBILLED_REVENUE => new List<ServiceAppointmentRowWrapper>()
            };

        if (!rows.isEmpty()) {
            for (ServiceAppointmentRowWrapper row : rows) {
                appointmentRowsByCategory.get(KPI_CATEGORY_READY_TO_BILL).add(row);
                appointmentRowsByCategory.get(KPI_CATEGORY_UNBILLED_REVENUE).add(row);
            }
        }

        for (ServiceAppointmentKpiCategoryWrapper section : sections) {
            List<ServiceAppointmentRowWrapper> sectionRows = appointmentRowsByCategory.containsKey(section.categoryKey)
                ? appointmentRowsByCategory.get(section.categoryKey)
                : new List<ServiceAppointmentRowWrapper>();
            section.rows = groupServiceAppointmentRowsByWorkOrder(sectionRows);
            section.opportunityGroups = buildServiceAppointmentOpportunityGroups(section.rows);
            section.serviceAppointmentCount = sectionRows.size();
            section.totalBillableAmount = calculateUniqueOpportunityRevenue(sectionRows);
        }

        return sections;
    }

    private static String buildServiceAppointmentDisplay(ServiceAppointmentRowWrapper row) {
        if (row == null) {
            return null;
        }
        if (String.isNotBlank(row.serviceAppointmentNumber)) {
            return row.serviceAppointmentNumber;
        }
        return row.serviceAppointmentId != null ? String.valueOf(row.serviceAppointmentId) : null;
    }

    private static Decimal calculateUniqueOpportunityRevenue(List<ServiceAppointmentRowWrapper> rows) {
        if (rows == null || rows.isEmpty()) {
            return 0;
        }

        Map<Id, Decimal> amountByOpportunityId = new Map<Id, Decimal>();
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row == null || row.opportunityId == null || amountByOpportunityId.containsKey(row.opportunityId)) {
                continue;
            }
            amountByOpportunityId.put(row.opportunityId, row.opportunityAmount);
        }

        Decimal totalRevenue = 0;
        for (Decimal opportunityAmount : amountByOpportunityId.values()) {
            totalRevenue += opportunityAmount != null ? opportunityAmount : 0;
        }
        return totalRevenue;
    }

    private static List<ServiceAppointmentRowWrapper> groupServiceAppointmentRowsByWorkOrder(
        List<ServiceAppointmentRowWrapper> appointmentRows
    ) {
        List<ServiceAppointmentRowWrapper> groupedRows = new List<ServiceAppointmentRowWrapper>();
        if (appointmentRows == null || appointmentRows.isEmpty()) {
            return groupedRows;
        }

        Map<String, ServiceAppointmentRowWrapper> rowByGroupingKey = new Map<String, ServiceAppointmentRowWrapper>();
        for (ServiceAppointmentRowWrapper appointmentRow : appointmentRows) {
            if (appointmentRow == null) {
                continue;
            }

            String groupingKey = buildServiceAppointmentGroupingKey(appointmentRow);
            ServiceAppointmentRowWrapper groupedRow = rowByGroupingKey.get(groupingKey);
            if (groupedRow == null) {
                groupedRow = cloneServiceAppointmentRow(appointmentRow);
                groupedRow.relatedServiceAppointments = new List<ServiceAppointmentRowWrapper>();
                groupedRow.serviceAppointmentCount = 0;
                rowByGroupingKey.put(groupingKey, groupedRow);
                groupedRows.add(groupedRow);
            }

            groupedRow.relatedServiceAppointments.add(cloneServiceAppointmentRow(appointmentRow));
            groupedRow.serviceAppointmentCount++;
        }

        for (ServiceAppointmentRowWrapper groupedRow : groupedRows) {
            groupedRow.opportunityAmount = resolveGroupedOpportunityAmount(groupedRow.relatedServiceAppointments);
        }

        return groupedRows;
    }

    private static Decimal resolveGroupedOpportunityAmount(List<ServiceAppointmentRowWrapper> appointmentRows) {
        if (appointmentRows == null || appointmentRows.isEmpty()) {
            return null;
        }

        Id resolvedOpportunityId;
        for (ServiceAppointmentRowWrapper appointmentRow : appointmentRows) {
            if (appointmentRow == null || appointmentRow.opportunityId == null) {
                return null;
            }
            if (resolvedOpportunityId == null) {
                resolvedOpportunityId = appointmentRow.opportunityId;
            } else if (resolvedOpportunityId != appointmentRow.opportunityId) {
                return null;
            }
        }

        return resolvedOpportunityId != null ? appointmentRows[0].opportunityAmount : null;
    }

    private static String buildServiceAppointmentGroupingKey(ServiceAppointmentRowWrapper row) {
        if (row == null) {
            return null;
        }
        if (row.workOrderId != null) {
            return 'WORK_ORDER:' + String.valueOf(row.workOrderId);
        }
        return 'ORDER:' + String.valueOf(row.orderId);
    }

    private static ServiceAppointmentRowWrapper cloneServiceAppointmentRow(ServiceAppointmentRowWrapper source) {
        if (source == null) {
            return null;
        }

        ServiceAppointmentRowWrapper clone = new ServiceAppointmentRowWrapper();
        clone.orderId = source.orderId;
        clone.orderNumber = source.orderNumber;
        clone.serviceAppointmentId = source.serviceAppointmentId;
        clone.serviceAppointmentNumber = source.serviceAppointmentNumber;
        clone.serviceAppointmentStatus = source.serviceAppointmentStatus;
        clone.opportunityId = source.opportunityId;
        clone.opportunityName = source.opportunityName;
        clone.opportunityAmount = source.opportunityAmount;
        clone.invoiceableOpportunityAmount = source.invoiceableOpportunityAmount;
        clone.accountId = source.accountId;
        clone.accountName = source.accountName;
        clone.workOrderId = source.workOrderId;
        clone.workOrderNumber = source.workOrderNumber;
        clone.serviceAppointmentDisplay = source.serviceAppointmentDisplay;
        clone.createdDate = source.createdDate;
        clone.subject = source.subject;
        clone.status = source.status;
        clone.ownerId = source.ownerId;
        clone.ownerName = source.ownerName;
        clone.completionDateTime = source.completionDateTime;
        clone.technicianId = source.technicianId;
        clone.technicianName = source.technicianName;
        clone.billingStatus = source.billingStatus;
        clone.invoiceNumber = source.invoiceNumber;
        clone.readyForBilling = source.readyForBilling;
        clone.invoicedAmount = source.invoicedAmount;
        clone.receivedAmount = source.receivedAmount;
        clone.outstandingAmount = source.outstandingAmount;
        clone.effectiveDate = source.effectiveDate;
        clone.serviceAppointmentCount = source.serviceAppointmentCount;
        return clone;
    }

    private static List<ServiceAppointmentOpportunityGroupWrapper> buildServiceAppointmentOpportunityGroups(
        List<ServiceAppointmentRowWrapper> rows
    ) {
        if (rows == null || rows.isEmpty()) {
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
                SELECT OpportunityId opportunityId, COUNT(Id) billedCount
                FROM Order
                WHERE OpportunityId IN :opportunityIds
                AND Invoiced_Amount__c > 0
                GROUP BY OpportunityId
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
                opportunityGroup.opportunityAmount = row.opportunityAmount;
                opportunityGroup.opportunityBillingStatus = row.billingStatus;
                opportunityGroup.accountId = row.accountId;
                opportunityGroup.accountName = row.accountName;
                opportunityGroup.totalBillableAmount = row.opportunityAmount;
                opportunityGroup.serviceAppointmentCount = 0;
                opportunityGroup.rows = new List<ServiceAppointmentRowWrapper>();
                groupByOpportunityId.put(row.opportunityId, opportunityGroup);
                groups.add(opportunityGroup);
            }

            opportunityGroup.rows.add(row);
            opportunityGroup.serviceAppointmentCount += row.serviceAppointmentCount != null
                ? row.serviceAppointmentCount
                : 0;
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

        Set<Id> requestedAppointmentIds = new Set<Id>(serviceAppointmentIds);
        Set<Id> lockedAppointmentIds = new Map<Id, ServiceAppointment>(lockedAppointments).keySet();
        if (lockedAppointmentIds.size() != requestedAppointmentIds.size()) {
            List<String> ineligibleSelections = new List<String>();
            for (Id requestedAppointmentId : requestedAppointmentIds) {
                if (!lockedAppointmentIds.contains(requestedAppointmentId)) {
                    ineligibleSelections.add(String.valueOf(requestedAppointmentId));
                }
            }
            throw buildHandledException(
                'Complete Billing requires selected Service Appointments to be completed and uninvoiced. Ineligible selections: '
                + String.join(ineligibleSelections, ', ')
                + '.'
            );
        }

        List<ServiceAppointment> appointmentsToBill = new List<ServiceAppointment>(lockedAppointments);
        Map<Id, Order> billingDiaryOrderByAppointmentId = resolveBillingDiaryOrdersForBilling(appointmentsToBill);

        Map<Id, Id> effectiveOpportunityByAppointmentId = new Map<Id, Id>();
        Map<Id, List<ServiceAppointment>> appointmentsByOpportunityId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointment : appointmentsToBill) {
            Order billingDiaryOrder = billingDiaryOrderByAppointmentId.get(appointment.Id);
            Id opportunityId = billingDiaryOrder != null ? billingDiaryOrder.OpportunityId : null;
            if (opportunityId == null) {
                throw buildHandledException(
                    'Complete Billing requires Order.OpportunityId for Service Appointment '
                    + String.valueOf(appointment.Id)
                    + '.'
                );
            }
            effectiveOpportunityByAppointmentId.put(appointment.Id, opportunityId);
            if (!appointmentsByOpportunityId.containsKey(opportunityId)) {
                appointmentsByOpportunityId.put(opportunityId, new List<ServiceAppointment>());
            }
            appointmentsByOpportunityId.get(opportunityId).add(appointment);
        }

        Set<Id> resolvedOpportunityIds = new Set<Id>(appointmentsByOpportunityId.keySet());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, Billing_Status__c, AccountId, Amount
            FROM Opportunity
            WHERE Id IN :resolvedOpportunityIds
            FOR UPDATE
        ]);

        Map<Id, Decimal> historicalInvoiceTotalByOpportunityId = queryHistoricalInvoiceTotalByOpportunityId(
            resolvedOpportunityIds
        );
        Map<Id, Decimal> invoiceTotalByOpportunityId = new Map<Id, Decimal>();
        Map<Id, Decimal> invoiceLineAmountByAppointmentId = new Map<Id, Decimal>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            Decimal opportunityAmount = opportunityRecord != null ? opportunityRecord.Amount : null;
            if (opportunityAmount == null || opportunityAmount <= 0) {
                throw buildHandledException(
                    'Complete Billing requires Opportunity.Amount greater than 0 for Opportunity '
                    + String.valueOf(opportunityId)
                    + '.'
                );
            }

            Decimal historicalInvoiceTotal = historicalInvoiceTotalByOpportunityId.containsKey(opportunityId)
                ? historicalInvoiceTotalByOpportunityId.get(opportunityId)
                : 0;
            Decimal invoiceTotal = opportunityAmount - historicalInvoiceTotal;
            if (invoiceTotal <= 0) {
                throw buildHandledException(
                    'Complete Billing cannot create additional invoice value for Opportunity '
                    + String.valueOf(opportunityId)
                    + ' because its current Opportunity.Amount has already been fully invoiced.'
                );
            }
            invoiceTotalByOpportunityId.put(opportunityId, invoiceTotal);
            invoiceLineAmountByAppointmentId.putAll(
                allocateInvoiceTotalAcrossAppointments(invoiceTotal, appointmentsByOpportunityId.get(opportunityId))
            );
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
                throw buildHandledException('Invoice number must be 80 characters or fewer.');
            }
            if (invoiceNumbersForUniqueness.contains(invoiceNumber)) {
                throw buildHandledException('Each invoice number in this batch must be unique.');
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
                throw buildHandledException(
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
        List<Order> ordersToUpdate = new List<Order>();
        String invoicedDiaryStatus = getInvoicedOrderDiaryStatusForUpdate();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Invoice__c invoiceRecord = invoiceByOpportunityId.get(opportunityId);
            if (invoiceRecord == null || invoiceRecord.Id == null) {
                continue;
            }

            for (ServiceAppointment appointment : appointmentsByOpportunityId.get(opportunityId)) {
                Order billingDiaryOrder = billingDiaryOrderByAppointmentId.get(appointment.Id);
                Decimal invoiceLineAmount = invoiceLineAmountByAppointmentId.get(appointment.Id);
                invoiceLinesToInsert.add(new Invoice_Line__c(
                    Invoice__c = invoiceRecord.Id,
                    Service_Appointment__c = appointment.Id,
                    Opportunity__c = opportunityId,
                    Work_Order__c = appointment.ParentRecordId,
                    Billing_Order__c = billingDiaryOrder != null ? billingDiaryOrder.Id : null,
                    Description__c = 'Service Appointment ' + appointment.Id,
                    Quantity__c = 1,
                    Unit_Price__c = invoiceLineAmount,
                    Line_Total__c = invoiceLineAmount
                ));

                appointment.Invoice_Number__c = invoiceRecord.Invoice_Number__c;
                if (appointment.Opportunity__c == null) {
                    appointment.Opportunity__c = effectiveOpportunityByAppointmentId.get(appointment.Id);
                }
                serviceAppointmentsToUpdate.add(appointment);

                if (billingDiaryOrder != null) {
                    ordersToUpdate.add(new Order(
                        Id = billingDiaryOrder.Id,
                        Billing_Diary_Status__c = invoicedDiaryStatus,
                        Ready_For_Billing__c = false,
                        Invoiced_Amount__c = invoiceLineAmount,
                        Received_Amount__c = 0
                    ));
                }
            }
        }

        if (!invoiceLinesToInsert.isEmpty()) {
            insert invoiceLinesToInsert;
        }

        if (!serviceAppointmentsToUpdate.isEmpty()) {
            update serviceAppointmentsToUpdate;
        }

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }

        Set<Id> opportunityIdsToUpdate = new Set<Id>();
        for (ServiceAppointment appointmentRecord : serviceAppointmentsToUpdate) {
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            if (effectiveOpportunityId != null) {
                opportunityIdsToUpdate.add(effectiveOpportunityId);
            }
        }

        String billedStatusForUpdate = getOutstandingReceivableStatusForUpdate();
        if (!opportunityIdsToUpdate.isEmpty()) {
            List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
            for (Opportunity opportunityRecord : [
                SELECT Id, Billing_Status__c
                FROM Opportunity
                WHERE Id IN :opportunityIdsToUpdate
            ]) {
                if (opportunityRecord.Billing_Status__c == billedStatusForUpdate) {
                    continue;
                }
                opportunitiesToUpdate.add(new Opportunity(
                    Id = opportunityRecord.Id,
                    Billing_Status__c = billedStatusForUpdate
                ));
            }
            if (!opportunitiesToUpdate.isEmpty()) {
                update opportunitiesToUpdate;
            }
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
            WHERE Billing_Status__c IN :OUTSTANDING_RECEIVABLE_BILLING_STATUSES
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
            SELECT Id, Billing_Status__c, AccountId
            FROM Opportunity
            WHERE Id = :input.opportunityId
            LIMIT 1
            FOR UPDATE
        ];

        Invoice__c invoiceRecord = getOpenReceivableInvoice(opportunityRecord.Id);
        Decimal invoiceAmount;
        Decimal previouslyPaid;
        if (invoiceRecord != null) {
            invoiceAmount = invoiceRecord.Total_Amount__c != null ? invoiceRecord.Total_Amount__c : 0;
            previouslyPaid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
        } else {
            invoiceAmount = resolveReceivableInvoiceAmountFromOrderDiary(opportunityRecord.Id);
            previouslyPaid = 0;
            if (invoiceAmount <= 0) {
                throw new AuraHandledException(
                    'No invoiced Order diary balance is available for this opportunity. Post billing before recording a receipt.'
                );
            }
            invoiceRecord = getOrCreateReceivableInvoice(opportunityRecord, invoiceAmount, previouslyPaid);
        }

        if (invoiceAmount <= 0) {
            throw new AuraHandledException(
                'The receivable invoice total must be greater than 0 before recording a receipt.'
            );
        }

        Decimal totalPaid = previouslyPaid + input.amountReceived;

        if (input.amountReceived > invoiceAmount - previouslyPaid) {
            throw new AuraHandledException('Payment amount cannot exceed the balance due.');
        }
        if (totalPaid > invoiceAmount) {
            throw new AuraHandledException('Payment amount cannot exceed the balance due.');
        }

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
        return getCommissionMetrics(null, null);
    }

    public static CommissionMetricsWrapper getCommissionMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        CommissionMetricsWrapper metrics = new CommissionMetricsWrapper();
        metrics.unbilledRevenue = 0;
        metrics.unbilledRevenueCount = 0;
        Set<Id> billingOrderIds = queryInvoiceLinkedBillingOrderIds();
        if (!billingOrderIds.isEmpty()) {
            for (AggregateResult revenueAggregateRow : Database.query(
                'SELECT OpportunityId opportunityId, SUM(Invoiced_Amount__c) totalInvoiced, SUM(Received_Amount__c) totalReceived'
                + ' FROM Order'
                + buildReceivableOrdersWhereClause(invoicesFilterContext, false)
                + ' GROUP BY OpportunityId'
            )) {
                Decimal invoicedAmount = revenueAggregateRow.get('totalInvoiced') != null
                    ? (Decimal) revenueAggregateRow.get('totalInvoiced')
                    : 0;
                Decimal receivedAmount = revenueAggregateRow.get('totalReceived') != null
                    ? (Decimal) revenueAggregateRow.get('totalReceived')
                    : 0;
                Decimal outstandingAmount = invoicedAmount - receivedAmount;
                if (outstandingAmount <= 0) {
                    continue;
                }

                metrics.revenueUnderCollectionCount++;
                metrics.revenueUnderCollection += outstandingAmount;
            }
        }

        AggregateResult[] commissionEarnedResults = Database.query(
            'SELECT COUNT(Id) recordCount, SUM(Commission_Amount__c) totalCommission'
            + ' FROM Commission__c'
            + buildCommissionWhereClause(commissionsFilterContext, true, false)
        );
        metrics.commissionEarnedCount = extractInteger(commissionEarnedResults, 'recordCount');
        metrics.commissionEarned = extractDecimal(commissionEarnedResults, 'totalCommission');

        List<Commission__c> payableCommissionRecords = queryOrderLinkedReceivableCommissionRecords(commissionsFilterContext);
        for (Commission__c payableCommissionRecord : payableCommissionRecords) {
            Order linkedOrder = payableCommissionRecord != null ? payableCommissionRecord.Billing_Order__r : null;
            String billingStatus = linkedOrder != null ? (String) linkedOrder.get('Billing_Diary_Status__c') : null;
            Decimal commissionAmount = payableCommissionRecord != null && payableCommissionRecord.Commission_Amount__c != null
                ? payableCommissionRecord.Commission_Amount__c
                : 0;
            Decimal commissionPaid = payableCommissionRecord != null && payableCommissionRecord.Commission_Paid__c != null
                ? payableCommissionRecord.Commission_Paid__c
                : 0;
            if (billingStatus != ORDER_DIARY_STATUS_PAID || commissionPaid >= commissionAmount) {
                continue;
            }

            metrics.commissionPayableCount++;
            metrics.commissionPayable += (commissionAmount - commissionPaid);
        }

        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static List<CommissionKpiCategoryWrapper> getCommissionData(String subtabType) {
        return getCommissionData(subtabType, null, null);
    }

    public static List<CommissionKpiCategoryWrapper> getCommissionData(
        String subtabType,
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        List<CommissionKpiCategoryWrapper> sections = new List<CommissionKpiCategoryWrapper>{
            new CommissionKpiCategoryWrapper(
                KPI_CATEGORY_REVENUE_UNDER_COLLECTION,
                KPI_LABEL_REVENUE_UNDER_COLLECTION
            ),
            new CommissionKpiCategoryWrapper(
                KPI_CATEGORY_COMMISSION_EARNED,
                KPI_LABEL_COMMISSION_EARNED
            ),
            new CommissionKpiCategoryWrapper(
                KPI_CATEGORY_COMMISSION_PAYABLE,
                KPI_LABEL_COMMISSION_PAYABLE
            )
        };

        Map<String, CommissionKpiCategoryWrapper> sectionByKey = new Map<String, CommissionKpiCategoryWrapper>();
        Map<String, Map<String, SalespersonWrapper>> salespersonIndexByCategoryKey =
            new Map<String, Map<String, SalespersonWrapper>>();
        for (CommissionKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
            salespersonIndexByCategoryKey.put(section.categoryKey, new Map<String, SalespersonWrapper>());
        }

        String ignoredSubtabType = subtabType;
        List<ReceivableOrderSummary> receivableSummaries = queryReceivableOrderSummaries(invoicesFilterContext);
        List<Commission__c> commissionRecords = queryOrderLinkedReceivableCommissionRecords(commissionsFilterContext);

        CommissionKpiCategoryWrapper revenueSection = sectionByKey.get(KPI_CATEGORY_REVENUE_UNDER_COLLECTION);
        CommissionKpiCategoryWrapper earnedSection = sectionByKey.get(KPI_CATEGORY_COMMISSION_EARNED);
        CommissionKpiCategoryWrapper payableSection = sectionByKey.get(KPI_CATEGORY_COMMISSION_PAYABLE);

        for (ReceivableOrderSummary summary : receivableSummaries) {
            addOpportunityToCommissionSection(
                revenueSection,
                salespersonIndexByCategoryKey.get(revenueSection.categoryKey),
                summary.ownerId,
                summary.ownerName,
                buildOpportunityFromReceivableSummary(summary)
            );
        }

        for (Commission__c commissionRecord : commissionRecords) {
            Order linkedOrder = commissionRecord != null ? commissionRecord.Billing_Order__r : null;
            Decimal outstandingAmount = linkedOrder != null
                ? coalesceDecimal((Decimal) linkedOrder.get('Outstanding_Amount__c'))
                : 0;
            Decimal commissionAmount = commissionRecord != null && commissionRecord.Commission_Amount__c != null
                ? commissionRecord.Commission_Amount__c
                : 0;
            Decimal commissionPaid = commissionRecord != null && commissionRecord.Commission_Paid__c != null
                ? commissionRecord.Commission_Paid__c
                : 0;
            String billingStatus = linkedOrder != null ? (String) linkedOrder.get('Billing_Diary_Status__c') : null;

            if (outstandingAmount > 0) {
                addOpportunityToCommissionSection(
                    earnedSection,
                    salespersonIndexByCategoryKey.get(earnedSection.categoryKey),
                    commissionRecord.Sales_Person__c,
                    commissionRecord.Sales_Person__r != null ? commissionRecord.Sales_Person__r.Name : null,
                    buildOpportunityFromOrderLinkedCommission(commissionRecord)
                );
            }

            if (billingStatus == ORDER_DIARY_STATUS_PAID && commissionPaid < commissionAmount) {
                addOpportunityToCommissionSection(
                    payableSection,
                    salespersonIndexByCategoryKey.get(payableSection.categoryKey),
                    commissionRecord.Sales_Person__c,
                    commissionRecord.Sales_Person__r != null ? commissionRecord.Sales_Person__r.Name : null,
                    buildOpportunityFromOrderLinkedCommission(commissionRecord)
                );
            }
        }

        return sections;
    }

    private static List<ReceivableOrderSummary> queryReceivableOrderSummaries(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Set<Id> billingOrderIds = queryInvoiceLinkedBillingOrderIds();
        if (billingOrderIds.isEmpty()) {
            return new List<ReceivableOrderSummary>();
        }

        List<Order> outstandingReceivableOrders = Database.query(
            'SELECT Id,'
            + ' OpportunityId,'
            + ' Opportunity_Name__c,'
            + ' Opportunity.CloseDate,'
            + ' Opportunity.OwnerId,'
            + ' Opportunity.Owner.Name,'
            + ' Account_Name__c,'
            + ' Billing_Diary_Status__c,'
            + ' Invoiced_Amount__c,'
            + ' Received_Amount__c,'
            + ' Outstanding_Amount__c,'
            + ' EffectiveDate'
            + ' FROM Order'
            + buildReceivableOrdersWhereClause(filterContext, false)
            + ' ORDER BY Opportunity_Name__c ASC NULLS LAST, OrderNumber ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT
        );

        if (outstandingReceivableOrders.size() >= QUERY_ROW_LIMIT) {
            while (outstandingReceivableOrders.size() > MAX_ROWS_PER_SECTION) {
                outstandingReceivableOrders.remove(outstandingReceivableOrders.size() - 1);
            }
            addRuntimeWarning(filterContext, KPI_LABEL_REVENUE_UNDER_COLLECTION + ': ' + ROW_LIMIT_WARNING_MESSAGE);
        }

        return summarizeReceivableOrders(outstandingReceivableOrders);
    }

    private static List<Commission__c> queryOrderLinkedReceivableCommissionRecords(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Commission__c> commissionRecords = Database.query(
            'SELECT Id,'
            + ' Billing_Order__c,'
            + ' Billing_Order__r.OpportunityId,'
            + ' Billing_Order__r.Opportunity_Name__c,'
            + ' Billing_Order__r.Opportunity.CloseDate,'
            + ' Billing_Order__r.Opportunity.OwnerId,'
            + ' Billing_Order__r.Opportunity.Owner.Name,'
            + ' Billing_Order__r.Account_Name__c,'
            + ' Billing_Order__r.Billing_Diary_Status__c,'
            + ' Billing_Order__r.Invoiced_Amount__c,'
            + ' Billing_Order__r.Received_Amount__c,'
            + ' Billing_Order__r.Outstanding_Amount__c,'
            + ' Billing_Order__r.EffectiveDate,'
            + ' Sales_Person__c,'
            + ' Sales_Person__r.Name,'
            + ' Commission_Amount__c,'
            + ' Commission_Paid__c'
            + ' FROM Commission__c'
            + buildCommissionPrefilterWhereClause(filterContext)
            + ' ORDER BY Sales_Person__r.Name ASC NULLS LAST, Billing_Order__r.Opportunity_Name__c ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT
        );

        if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
            commissionRecords = filterReceivablesCommissionRecords(commissionRecords, filterContext);
        }

        if (commissionRecords.size() >= QUERY_ROW_LIMIT) {
            while (commissionRecords.size() > MAX_ROWS_PER_SECTION) {
                commissionRecords.remove(commissionRecords.size() - 1);
            }
            addRuntimeWarning(filterContext, KPI_LABEL_COMMISSION_EARNED + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            addRuntimeWarning(filterContext, KPI_LABEL_COMMISSION_PAYABLE + ': ' + ROW_LIMIT_WARNING_MESSAGE);
        }

        return commissionRecords;
    }

    private static List<Opportunity> queryOutstandingReceivableOpportunities() {
        return [
            SELECT Id,
                Name,
                Account.Name,
                Amount,
                Amount_Paid__c,
                Billing_Status__c,
                CloseDate,
                OwnerId,
                Owner.Name
            FROM Opportunity
            WHERE Billing_Status__c IN :OUTSTANDING_RECEIVABLE_BILLING_STATUSES
            ORDER BY Owner.Name ASC NULLS LAST, Name ASC NULLS LAST
        ];
    }

    private static List<Order> filterReceivableOrders(
        List<Order> orderRecords,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Order> filtered = new List<Order>();
        for (Order orderRecord : orderRecords) {
            if (matchesReceivableOrderFilters(orderRecord, filterContext)) {
                filtered.add(orderRecord);
            }
        }
        return filtered;
    }

    private static Boolean matchesReceivableOrderFilters(
        Order orderRecord,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return true;
        }

        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.' + normalizeFilterValue(filterRecord.fieldApiName);
            Object fieldValue;

            if (fieldKey == 'ORDER.BILLING_DIARY_STATUS__C') {
                fieldValue = orderRecord != null ? (String) orderRecord.get('Billing_Diary_Status__c') : null;
            } else if (fieldKey == 'ORDER.RECEIVED_AMOUNT__C') {
                fieldValue = orderRecord != null ? (Decimal) orderRecord.get('Received_Amount__c') : null;
            } else if (fieldKey == 'ORDER.OUTSTANDING_AMOUNT__C') {
                fieldValue = orderRecord != null ? (Decimal) orderRecord.get('Outstanding_Amount__c') : null;
            } else if (fieldKey == 'ORDER.EFFECTIVEDATE') {
                if (!evaluateDateFilter(orderRecord != null ? orderRecord.EffectiveDate : null, filterRecord)) {
                    return false;
                }
                continue;
            } else {
                continue;
            }

            if (!evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    private static List<Commission__c> queryReceivablesCommissionRecords() {
        return [
            SELECT Id,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Account.Name,
                Opportunity__r.Amount,
                Opportunity__r.Amount_Paid__c,
                Opportunity__r.Billing_Status__c,
                Opportunity__r.CloseDate,
                Sales_Person__c,
                Sales_Person__r.Name,
                Commission_Amount__c,
                Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__r.Billing_Status__c IN :OUTSTANDING_RECEIVABLE_BILLING_STATUSES
            OR Opportunity__r.Billing_Status__c = :PAID
            ORDER BY Sales_Person__r.Name ASC NULLS LAST, Opportunity__r.Name ASC NULLS LAST
        ];
    }

    private static List<Opportunity> filterReceivablesOpportunities(
        List<Opportunity> opportunities,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Opportunity> filtered = new List<Opportunity>();
        for (Opportunity opportunityRecord : opportunities) {
            if (matchesReceivablesOpportunityFilters(opportunityRecord, filterContext)) {
                filtered.add(opportunityRecord);
            }
        }
        return filtered;
    }

    private static Boolean matchesReceivablesOpportunityFilters(
        Opportunity opportunityRecord,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return true;
        }

        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.' + normalizeFilterValue(filterRecord.fieldApiName);
            Object fieldValue;

            if (fieldKey == 'OPPORTUNITY.BILLING_STATUS__C') {
                fieldValue = opportunityRecord != null ? (String) opportunityRecord.get('Billing_Status__c') : null;
            } else if (fieldKey == 'OPPORTUNITY.AMOUNT_PAID__C') {
                fieldValue = opportunityRecord != null ? (Decimal) opportunityRecord.get('Amount_Paid__c') : null;
            } else if (fieldKey == 'OPPORTUNITY.CLOSEDATE') {
                fieldValue = opportunityRecord != null ? opportunityRecord.CloseDate : null;
            } else {
                continue;
            }

            if (!evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    private static List<Commission__c> filterReceivablesCommissionRecords(
        List<Commission__c> commissionRecords,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Commission__c> filtered = new List<Commission__c>();
        for (Commission__c commissionRecord : commissionRecords) {
            if (matchesReceivablesCommissionFilters(commissionRecord, filterContext)) {
                filtered.add(commissionRecord);
            }
        }
        return filtered;
    }

    private static Boolean matchesReceivablesCommissionFilters(
        Commission__c commissionRecord,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return true;
        }

        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.' + normalizeFilterValue(filterRecord.fieldApiName);
            Object fieldValue;

            if (fieldKey == 'ORDER.BILLING_DIARY_STATUS__C') {
                fieldValue = (
                    commissionRecord != null && commissionRecord.Billing_Order__r != null
                ) ? (String) commissionRecord.Billing_Order__r.get('Billing_Diary_Status__c') : null;
            } else if (fieldKey == 'ORDER.RECEIVED_AMOUNT__C') {
                fieldValue = (
                    commissionRecord != null && commissionRecord.Billing_Order__r != null
                ) ? (Decimal) commissionRecord.Billing_Order__r.get('Received_Amount__c') : null;
            } else if (fieldKey == 'ORDER.OUTSTANDING_AMOUNT__C') {
                fieldValue = (
                    commissionRecord != null && commissionRecord.Billing_Order__r != null
                ) ? (Decimal) commissionRecord.Billing_Order__r.get('Outstanding_Amount__c') : null;
            } else if (fieldKey == 'ORDER.EFFECTIVEDATE') {
                if (!evaluateDateFilter(
                    (commissionRecord != null && commissionRecord.Billing_Order__r != null)
                        ? commissionRecord.Billing_Order__r.EffectiveDate
                        : null,
                    filterRecord
                )) {
                    return false;
                }
                continue;
            } else if (fieldKey == 'COMMISSION__C.COMMISSION_PAID__C') {
                fieldValue = commissionRecord != null ? commissionRecord.Commission_Paid__c : null;
            } else {
                continue;
            }

            if (!evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    private static Decimal sumOpportunityAmounts(List<Opportunity> opportunities) {
        Decimal total = 0;
        if (opportunities == null) {
            return total;
        }
        for (Opportunity opportunityRecord : opportunities) {
            total += opportunityRecord != null && opportunityRecord.Amount != null ? opportunityRecord.Amount : 0;
        }
        return total;
    }

    private static List<ReceivableOrderSummary> summarizeReceivableOrders(List<Order> orderRecords) {
        Map<Id, ReceivableOrderSummary> summaryByOpportunityId = new Map<Id, ReceivableOrderSummary>();
        List<ReceivableOrderSummary> summaries = new List<ReceivableOrderSummary>();
        if (orderRecords == null) {
            return summaries;
        }

        for (Order orderRecord : orderRecords) {
            if (orderRecord == null || orderRecord.OpportunityId == null) {
                continue;
            }

            Decimal invoicedAmount = coalesceDecimal((Decimal) orderRecord.get('Invoiced_Amount__c'));
            Decimal receivedAmount = coalesceDecimal((Decimal) orderRecord.get('Received_Amount__c'));
            Decimal outstandingAmount = invoicedAmount - receivedAmount;
            if (outstandingAmount <= 0) {
                continue;
            }

            ReceivableOrderSummary summary = summaryByOpportunityId.get(orderRecord.OpportunityId);
            if (summary == null) {
                summary = new ReceivableOrderSummary();
                summary.opportunityId = orderRecord.OpportunityId;
                summary.opportunityName = (String) orderRecord.get('Opportunity_Name__c');
                summary.accountName = (String) orderRecord.get('Account_Name__c');
                summary.closeDate = orderRecord.Opportunity != null ? orderRecord.Opportunity.CloseDate : null;
                summary.ownerId = orderRecord.Opportunity != null ? orderRecord.Opportunity.OwnerId : null;
                summary.ownerName = orderRecord.Opportunity != null && orderRecord.Opportunity.Owner != null
                    ? orderRecord.Opportunity.Owner.Name
                    : null;
                summary.billingStatus = (String) orderRecord.get('Billing_Diary_Status__c');
                summary.amount = 0;
                summary.amountPaid = 0;
                summary.balanceDue = 0;
                summaryByOpportunityId.put(summary.opportunityId, summary);
                summaries.add(summary);
            }

            summary.amount += invoicedAmount;
            summary.amountPaid += receivedAmount;
            summary.balanceDue += outstandingAmount;
        }

        return summaries;
    }

    private static Decimal sumReceivableBalances(List<ReceivableOrderSummary> summaries) {
        Decimal total = 0;
        if (summaries == null) {
            return total;
        }
        for (ReceivableOrderSummary summary : summaries) {
            total += summary != null ? summary.balanceDue : 0;
        }
        return total;
    }

    private static OpportunityWrapper buildOpportunityFromReceivableSummary(ReceivableOrderSummary summary) {
        OpportunityWrapper opportunity = new OpportunityWrapper();
        opportunity.opportunityId = summary != null ? summary.opportunityId : null;
        opportunity.name = summary != null ? summary.opportunityName : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = summary != null ? summary.accountName : null;
        opportunity.amount = summary != null ? summary.amount : 0;
        opportunity.amountPaid = summary != null ? summary.amountPaid : 0;
        opportunity.balanceDue = summary != null ? summary.balanceDue : 0;
        opportunity.billingStatus = summary != null ? summary.billingStatus : null;
        opportunity.closeDate = summary != null ? summary.closeDate : null;
        opportunity.ownerId = summary != null ? summary.ownerId : null;
        opportunity.ownerName = summary != null ? summary.ownerName : null;
        opportunity.commissionAmount = 0;
        opportunity.commissionPaid = 0;
        opportunity.commissionId = null;
        return opportunity;
    }

    private static OpportunityWrapper buildOpportunityFromOrderLinkedCommission(Commission__c commissionRecord) {
        OpportunityWrapper opportunity = new OpportunityWrapper();
        Order linkedOrder = commissionRecord != null ? commissionRecord.Billing_Order__r : null;
        opportunity.opportunityId = linkedOrder != null ? linkedOrder.OpportunityId : null;
        opportunity.name = linkedOrder != null ? (String) linkedOrder.get('Opportunity_Name__c') : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = linkedOrder != null ? (String) linkedOrder.get('Account_Name__c') : null;
        opportunity.amount = linkedOrder != null ? coalesceDecimal((Decimal) linkedOrder.get('Invoiced_Amount__c')) : 0;
        opportunity.amountPaid = linkedOrder != null ? coalesceDecimal((Decimal) linkedOrder.get('Received_Amount__c')) : 0;
        opportunity.balanceDue = linkedOrder != null ? coalesceDecimal((Decimal) linkedOrder.get('Outstanding_Amount__c')) : 0;
        opportunity.billingStatus = linkedOrder != null ? (String) linkedOrder.get('Billing_Diary_Status__c') : null;
        opportunity.closeDate = linkedOrder != null && linkedOrder.Opportunity != null
            ? linkedOrder.Opportunity.CloseDate
            : null;
        opportunity.ownerId = commissionRecord != null ? commissionRecord.Sales_Person__c : null;
        opportunity.ownerName = commissionRecord != null && commissionRecord.Sales_Person__r != null
            ? commissionRecord.Sales_Person__r.Name
            : null;
        opportunity.commissionAmount = commissionRecord != null ? coalesceDecimal(commissionRecord.Commission_Amount__c) : 0;
        opportunity.commissionPaid = commissionRecord != null ? coalesceDecimal(commissionRecord.Commission_Paid__c) : 0;
        opportunity.commissionId = commissionRecord != null ? commissionRecord.Id : null;
        return opportunity;
    }

    private static Decimal coalesceDecimal(Decimal value) {
        return value != null ? value : 0;
    }

    private static String coalesceText(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }

    private static OpportunityWrapper buildOpportunityFromOpportunity(Opportunity opportunityRecord) {
        OpportunityWrapper opportunity = new OpportunityWrapper();
        opportunity.opportunityId = opportunityRecord != null ? opportunityRecord.Id : null;
        opportunity.name = opportunityRecord != null ? opportunityRecord.Name : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = opportunityRecord != null && opportunityRecord.Account != null
            ? opportunityRecord.Account.Name
            : null;
        opportunity.amount = opportunityRecord != null ? opportunityRecord.Amount : null;
        Decimal amountPaid = opportunityRecord != null
            ? (Decimal) opportunityRecord.get('Amount_Paid__c')
            : null;
        opportunity.amountPaid = amountPaid != null ? amountPaid : 0;
        Decimal amount = opportunity.amount != null ? opportunity.amount : 0;
        opportunity.balanceDue = amount - opportunity.amountPaid;
        opportunity.billingStatus = opportunityRecord != null
            ? (String) opportunityRecord.get('Billing_Status__c')
            : null;
        opportunity.closeDate = opportunityRecord != null ? opportunityRecord.CloseDate : null;
        opportunity.commissionAmount = 0;
        opportunity.commissionPaid = 0;
        opportunity.commissionId = null;
        return opportunity;
    }

    private static OpportunityWrapper buildOpportunityFromCommission(Commission__c commissionRecord) {
        OpportunityWrapper opportunity = new OpportunityWrapper();
        opportunity.opportunityId = commissionRecord != null ? commissionRecord.Opportunity__c : null;
        opportunity.name = commissionRecord != null && commissionRecord.Opportunity__r != null
            ? commissionRecord.Opportunity__r.Name
            : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = commissionRecord != null
            && commissionRecord.Opportunity__r != null
            && commissionRecord.Opportunity__r.Account != null
                ? commissionRecord.Opportunity__r.Account.Name
                : null;
        opportunity.amount = commissionRecord != null && commissionRecord.Opportunity__r != null
            ? commissionRecord.Opportunity__r.Amount
            : null;
        Decimal amountPaid = commissionRecord != null && commissionRecord.Opportunity__r != null
            ? (Decimal) commissionRecord.Opportunity__r.get('Amount_Paid__c')
            : null;
        opportunity.amountPaid = amountPaid != null ? amountPaid : 0;
        Decimal amount = opportunity.amount != null ? opportunity.amount : 0;
        opportunity.balanceDue = amount - opportunity.amountPaid;
        opportunity.billingStatus = commissionRecord != null && commissionRecord.Opportunity__r != null
            ? commissionRecord.Opportunity__r.Billing_Status__c
            : null;
        opportunity.closeDate = commissionRecord != null && commissionRecord.Opportunity__r != null
            ? commissionRecord.Opportunity__r.CloseDate
            : null;
        opportunity.commissionAmount = commissionRecord != null && commissionRecord.Commission_Amount__c != null
            ? commissionRecord.Commission_Amount__c
            : 0;
        opportunity.commissionPaid = commissionRecord != null && commissionRecord.Commission_Paid__c != null
            ? commissionRecord.Commission_Paid__c
            : 0;
        opportunity.commissionId = commissionRecord != null ? commissionRecord.Id : null;
        return opportunity;
    }

    private static void addOpportunityToCommissionSection(
        CommissionKpiCategoryWrapper section,
        Map<String, SalespersonWrapper> salespersonIndex,
        Id salespersonId,
        String salespersonName,
        OpportunityWrapper opportunity
    ) {
        if (section == null || salespersonIndex == null || opportunity == null || opportunity.opportunityId == null) {
            return;
        }

        String salespersonKey = salespersonId != null ? String.valueOf(salespersonId) : 'UNASSIGNED';
        SalespersonWrapper salesperson = salespersonIndex.get(salespersonKey);
        if (salesperson == null) {
            salesperson = new SalespersonWrapper();
            salesperson.salespersonId = salespersonId;
            salesperson.salespersonName = String.isNotBlank(salespersonName) ? salespersonName : 'Unassigned';
            salesperson.totalAmount = 0;
            salesperson.totalCommission = 0;
            salesperson.totalPaid = 0;
            salesperson.opportunities = new List<OpportunityWrapper>();
            salespersonIndex.put(salespersonKey, salesperson);
            section.salespersonGroups.add(salesperson);
        }

        Decimal amount = opportunity.amount != null ? opportunity.amount : 0;
        Decimal commissionAmount = opportunity.commissionAmount != null ? opportunity.commissionAmount : 0;
        Decimal commissionPaid = opportunity.commissionPaid != null ? opportunity.commissionPaid : 0;

        salesperson.totalAmount += amount;
        salesperson.totalCommission += commissionAmount;
        salesperson.totalPaid += commissionPaid;
        salesperson.opportunities.add(opportunity);

        section.opportunityCount++;
        section.totalAmount += amount;
        section.totalCommission += commissionAmount;
        section.totalPaid += commissionPaid;
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
                    Billing_Status__c = getOutstandingReceivableStatusForUpdate()
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
     * Legacy allocation helper retained only so older internal call sites can compile. BCC Order
     * Diary billing must not derive billable amount from WorkOrder or Opportunity totals.
     */
    private static Decimal resolveBillableAmount(
        Id workOrderId,
        Id effectiveOpportunityId,
        Map<Id, WorkOrder> workOrderById,
        Map<Id, Integer> appointmentCountByWorkOrderId,
        Map<String, Integer> appointmentCountByWorkOrderAndOpportunityId,
        Map<Id, Opportunity> opportunityById
    ) {
        return 0;
    }

    private static Invoice__c getOrCreateReceivableInvoice(
        Opportunity opportunityRecord,
        Decimal invoiceAmount,
        Decimal previouslyPaid
    ) {
        Invoice__c existingInvoice = getOpenReceivableInvoice(opportunityRecord.Id);
        if (existingInvoice != null) {
            return existingInvoice;
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

    private static Invoice__c getOpenReceivableInvoice(Id opportunityId) {
        List<Invoice__c> existingInvoices = [
            SELECT Id,
                Invoice_Number__c,
                Amount_Paid__c,
                Balance_Due__c,
                Total_Amount__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityId
            AND Status__c != :INVOICE_STATUS_PAID
            LIMIT 1
            FOR UPDATE
        ];
        return existingInvoices.isEmpty() ? null : existingInvoices[0];
    }

    private static Decimal resolveReceivableInvoiceAmountFromOrderDiary(Id opportunityId) {
        Decimal totalAmount = 0;
        for (AggregateResult aggregateResult : [
            SELECT SUM(Invoiced_Amount__c) totalAmount
            FROM Order
            WHERE OpportunityId = :opportunityId
            AND Invoiced_Amount__c != null
            AND Invoiced_Amount__c > 0
        ]) {
            Decimal value = (Decimal) aggregateResult.get('totalAmount');
            totalAmount += value != null ? value : 0;
        }
        return totalAmount;
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
        return buildBillableServiceAppointmentRows(null);
    }

    private static List<ServiceAppointmentRowWrapper> buildBillableServiceAppointmentRows(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        // Query all selective base candidates, then apply the relationship checks below. Applying
        // LIMIT before the staged eligibility filter could hide an otherwise eligible diary record.
        List<Order> readyToInvoiceOrders = queryEligibleInvoicingOrders(filterContext, null);

        if (readyToInvoiceOrders.isEmpty()) {
            return new List<ServiceAppointmentRowWrapper>();
        }

        List<ServiceAppointmentRowWrapper> rows = new List<ServiceAppointmentRowWrapper>();
        for (Order orderRecord : readyToInvoiceOrders) {
            ServiceAppointmentRowWrapper row = new ServiceAppointmentRowWrapper();
            row.orderId = orderRecord.Id;
            row.orderNumber = orderRecord.OrderNumber;
            row.serviceAppointmentId = (Id) orderRecord.get('Service_Appointment__c');
            row.serviceAppointmentNumber = orderRecord.Service_Appointment__r != null
                ? orderRecord.Service_Appointment__r.AppointmentNumber
                : null;
            row.serviceAppointmentStatus = orderRecord.Service_Appointment__r != null
                ? orderRecord.Service_Appointment__r.Status
                : null;
            row.serviceAppointmentDisplay = buildServiceAppointmentDisplay(row);
            row.opportunityId = orderRecord.OpportunityId;
            row.opportunityName = (String) orderRecord.get('Opportunity_Name__c');
            row.opportunityAmount = orderRecord.OpportunityId != null && orderRecord.Opportunity != null
                ? orderRecord.Opportunity.Amount
                : null;
            row.accountId = orderRecord.AccountId;
            row.accountName = (String) orderRecord.get('Account_Name__c');
            row.workOrderId = (Id) orderRecord.get('Work_Order__c');
            row.workOrderNumber = (String) orderRecord.get('Work_Order_Number__c');
            row.createdDate = orderRecord.CreatedDate;
            row.subject = coalesceText((String) orderRecord.get('Work_Order_Subject__c'), orderRecord.Name);
            row.status = (String) orderRecord.get('Billing_Diary_Status__c');
            row.ownerId = (Id) orderRecord.get('Technician__c');
            row.ownerName = orderRecord.Technician__r != null ? orderRecord.Technician__r.Name : null;
            row.completionDateTime = orderRecord.Service_Appointment__r != null
                ? orderRecord.Service_Appointment__r.ActualEndTime
                : null;
            row.technicianId = (Id) orderRecord.get('Technician__c');
            row.technicianName = orderRecord.Technician__r != null ? orderRecord.Technician__r.Name : null;
            row.billingStatus = (String) orderRecord.get('Billing_Diary_Status__c');
            row.invoiceNumber = orderRecord.Service_Appointment__r != null
                ? orderRecord.Service_Appointment__r.Invoice_Number__c
                : null;
            row.readyForBilling = (Boolean) orderRecord.get('Ready_For_Billing__c');
            row.invoicedAmount = (Decimal) orderRecord.get('Invoiced_Amount__c');
            row.receivedAmount = (Decimal) orderRecord.get('Received_Amount__c');
            row.outstandingAmount = (Decimal) orderRecord.get('Outstanding_Amount__c');
            row.effectiveDate = orderRecord.EffectiveDate;
            rows.add(row);
        }

        if (rows.size() >= QUERY_ROW_LIMIT) {
            while (rows.size() > MAX_ROWS_PER_SECTION) {
                rows.remove(rows.size() - 1);
            }
            addRuntimeWarning(filterContext, KPI_LABEL_READY_TO_BILL + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            addRuntimeWarning(filterContext, KPI_LABEL_AGED_COMPLETED + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            addRuntimeWarning(filterContext, KPI_LABEL_UNBILLED_REVENUE + ': ' + ROW_LIMIT_WARNING_MESSAGE);
        }

        if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
            rows = filterBillableServiceAppointmentRows(rows, filterContext);
        }

        populateInvoiceableOpportunityAmounts(rows);
        return rows;
    }

    private static void populateInvoiceableOpportunityAmounts(List<ServiceAppointmentRowWrapper> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Set<Id> opportunityIds = new Set<Id>();
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row != null && row.opportunityId != null) {
                opportunityIds.add(row.opportunityId);
            }
        }
        Map<Id, Decimal> historicalInvoiceTotalByOpportunityId = queryHistoricalInvoiceTotalByOpportunityId(
            opportunityIds
        );
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row == null || row.opportunityId == null || row.opportunityAmount == null) {
                row.invoiceableOpportunityAmount = null;
                continue;
            }
            Decimal historicalInvoiceTotal = historicalInvoiceTotalByOpportunityId.containsKey(row.opportunityId)
                ? historicalInvoiceTotalByOpportunityId.get(row.opportunityId)
                : 0;
            row.invoiceableOpportunityAmount = row.opportunityAmount - historicalInvoiceTotal;
        }
    }

    private static List<ServiceAppointmentRowWrapper> filterBillableServiceAppointmentRows(
        List<ServiceAppointmentRowWrapper> rows,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<ServiceAppointmentRowWrapper> filteredRows = new List<ServiceAppointmentRowWrapper>();
        for (ServiceAppointmentRowWrapper row : rows) {
            if (matchesBillableServiceAppointmentFilters(row, filterContext)) {
                filteredRows.add(row);
            }
        }
        return filteredRows;
    }

    private static Boolean matchesBillableServiceAppointmentFilters(
        ServiceAppointmentRowWrapper row,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.' + normalizeFilterValue(filterRecord.fieldApiName);
            if (isLegacyInvoicingEligibilityFilter(fieldKey)) {
                continue;
            }
            Object fieldValue;

            if (fieldKey == 'ORDER.BILLING_DIARY_STATUS__C') {
                fieldValue = row.status;
            } else if (fieldKey == 'ORDER.READY_FOR_BILLING__C') {
                fieldValue = row.readyForBilling;
            } else if (fieldKey == 'ORDER.SERVICE_APPOINTMENT__C') {
                fieldValue = row.serviceAppointmentId;
            } else if (fieldKey == 'ORDER.INVOICED_AMOUNT__C') {
                fieldValue = normalizeInvoicedAmountFilterValue(row.invoicedAmount, filterRecord);
            } else if (fieldKey == 'ORDER.EFFECTIVEDATE') {
                if (!evaluateDateFilter(row.effectiveDate, filterRecord)) {
                    return false;
                }
                continue;
            } else if (fieldKey == 'SERVICEAPPOINTMENT.ACTUALENDTIME') {
                if (!evaluateDateTimeFilter(row.completionDateTime, filterRecord)) {
                    return false;
                }
                continue;
            } else {
                continue;
            }

            if (!evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    private static Object normalizeInvoicedAmountFilterValue(
        Decimal invoicedAmount,
        BillingControl_DataProvider.BillingFilterDTO filterRecord
    ) {
        String operatorValue = normalizeFilterValue(filterRecord != null ? filterRecord.operator : null);
        if (invoicedAmount == null && operatorValue != 'IS NULL' && operatorValue != 'IS NOT NULL') {
            return 0;
        }
        return invoicedAmount;
    }

    private static Integer queryReadyToInvoiceCount(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean completedMoreThanTwoDaysOnly
    ) {
        return queryEligibleInvoicingOrders(filterContext, null).size();
    }

    private static Decimal queryReadyToInvoiceRevenue(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Map<Id, Decimal> amountByOpportunityId = new Map<Id, Decimal>();
        for (Order orderRecord : queryEligibleInvoicingOrders(filterContext, null)) {
            if (orderRecord.OpportunityId != null && !amountByOpportunityId.containsKey(orderRecord.OpportunityId)) {
                amountByOpportunityId.put(orderRecord.OpportunityId, orderRecord.Opportunity != null ? orderRecord.Opportunity.Amount : null);
            }
        }
        Decimal totalRevenue = 0;
        for (Decimal opportunityAmount : amountByOpportunityId.values()) {
            totalRevenue += opportunityAmount != null ? opportunityAmount : 0;
        }
        return totalRevenue;
    }

    private static String buildReadyToInvoiceWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean completedMoreThanTwoDaysOnly
    ) {
        List<String> clauses = new List<String>{
            'Service_Appointment__c != NULL'
        };
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(
                getNonLegacyInvoicingFilterContext(filterContext),
                getReadyToInvoiceFilterFieldMappings()
            )
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static BillingControl_DataProvider.BillingFilterContextDTO getNonLegacyInvoicingFilterContext(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return filterContext;
        }
        BillingControl_DataProvider.BillingFilterContextDTO filteredContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filteredContext.tabKey = filterContext.tabKey;
        filteredContext.datasetKey = filterContext.datasetKey;
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.'
                + normalizeFilterValue(filterRecord.fieldApiName);
            if (!isLegacyInvoicingEligibilityFilter(fieldKey)) {
                filteredContext.filters.add(filterRecord);
            }
        }
        return filteredContext;
    }

    private static Boolean isLegacyInvoicingEligibilityFilter(String fieldKey) {
        return fieldKey == 'ORDER.BILLING_DIARY_STATUS__C'
            || fieldKey == 'ORDER.READY_FOR_BILLING__C'
            || fieldKey == 'ORDER.SERVICE_APPOINTMENT__C'
            || fieldKey == 'ORDER.INVOICED_AMOUNT__C'
            || fieldKey == 'SERVICEAPPOINTMENT.ACTUALENDTIME';
    }

    private static List<Order> queryEligibleInvoicingOrders(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Integer rowLimit
    ) {
        String queryText = 'SELECT Id, Name, OrderNumber, AccountId, Account_Name__c, OpportunityId, Opportunity.Amount, Opportunity_Name__c,'
            + ' Work_Order__c, Work_Order_Number__c, Work_Order_Subject__c, Work_Order__r.Status, Work_Order__r.Parent_Account__r.Name,'
            + ' Service_Appointment__c, Service_Appointment__r.AppointmentNumber, Service_Appointment__r.Status,'
            + ' Service_Appointment__r.SchedStartTime, Service_Appointment__r.ActualEndTime, Service_Appointment__r.Invoice_Number__c,'
            + ' Service_Appointment__r.WO_Inv_Status__c, Technician__c, Technician__r.Name, Billing_Diary_Status__c,'
            + ' Ready_For_Billing__c, Invoiced_Amount__c, Received_Amount__c, Outstanding_Amount__c, EffectiveDate, CreatedDate'
            + ' FROM Order' + buildReadyToInvoiceWhereClause(filterContext, false)
            + ' ORDER BY Service_Appointment__r.ActualEndTime DESC NULLS LAST, OrderNumber ASC NULLS LAST';
        List<Order> eligible = new List<Order>();
        for (Order orderRecord : Database.query(queryText)) {
            if (isEligibleInvoicingOrder(orderRecord)) {
                eligible.add(orderRecord);
                if (rowLimit != null && eligible.size() >= rowLimit) {
                    break;
                }
            }
        }
        return eligible;
    }

    private static Boolean isEligibleInvoicingOrder(Order orderRecord) {
        ServiceAppointment appointment = orderRecord.Service_Appointment__r;
        if (appointment == null || appointment.Status != SERVICE_APPOINTMENT_STATUS_COMPLETED) return false;
        if (containsExcludedInvoicingMarker(appointment.Invoice_Number__c)
            || containsExcludedInvoicingMarker(appointment.WO_Inv_Status__c)) return false;
        WorkOrder workOrder = orderRecord.Work_Order__r;
        if (workOrder == null) return true;
        if (EXCLUDED_INVOICING_WORK_ORDER_STATUSES.contains(workOrder.Status)) return false;
        return workOrder.Parent_Account__r == null || !containsExcludedInvoicingMarkerForAccount(workOrder.Parent_Account__r.Name);
    }

    private static Boolean containsExcludedInvoicingMarkerForAccount(String value) { return value != null && value.contains('NYCDOE'); }

    @TestVisible
    private static Boolean containsExcludedInvoicingMarker(String value) {
        return value != null && (value.contains('Inv') || value.contains('Inspection'));
    }

    private static String buildReceivableOrdersWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean onlyOutstanding
    ) {
        List<String> clauses = new List<String>{
            'Id IN :billingOrderIds',
            'OpportunityId != NULL',
            'Billing_Diary_Status__c != \'' + String.escapeSingleQuotes(ORDER_DIARY_STATUS_CANCELLED) + '\''
        };
        if (onlyOutstanding) {
            clauses.add('Outstanding_Amount__c > 0');
        }
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getReceivableOrderFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static String buildCommissionWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean onlyEarned,
        Boolean onlyPayable
    ) {
        List<String> clauses = new List<String>{ 'Billing_Order__c != NULL' };
        if (onlyEarned) {
            clauses.add('Billing_Order__r.Outstanding_Amount__c > 0');
        }
        if (onlyPayable) {
            clauses.add(
                'Billing_Order__r.Billing_Diary_Status__c = \''
                + String.escapeSingleQuotes(ORDER_DIARY_STATUS_PAID)
                + '\''
            );
        }
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getCommissionFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static String buildCommissionPrefilterWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<String> clauses = new List<String>{ 'Billing_Order__c != NULL' };
        if (filterContext != null && filterContext.filters != null) {
            for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
                String fieldKey = normalizeFilterValue(filterRecord.objectApiName) + '.' + normalizeFilterValue(filterRecord.fieldApiName);
                if (fieldKey != 'ORDER.EFFECTIVEDATE') {
                    continue;
                }
                BillingControl_DataProvider.BillingFilterContextDTO singleFilterContext =
                    new BillingControl_DataProvider.BillingFilterContextDTO();
                singleFilterContext.filters.add(filterRecord);
                List<String> queryClauses = BillingControl_DataProvider.buildQueryFilterClauses(
                    singleFilterContext,
                    new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
                        'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                            'Billing_Order__r.EffectiveDate',
                            BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
                        )
                    }
                );
                clauses.addAll(queryClauses);
            }
        }
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static Set<Id> queryInvoiceLinkedBillingOrderIds() {
        Set<Id> billingOrderIds = new Set<Id>();
        for (Invoice_Line__c invoiceLineRecord : [
            SELECT Billing_Order__c
            FROM Invoice_Line__c
            WHERE Billing_Order__c != NULL
        ]) {
            billingOrderIds.add(invoiceLineRecord.Billing_Order__c);
        }
        return billingOrderIds;
    }

    private static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getReadyToInvoiceFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.BILLING_DIARY_STATUS__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Diary_Status__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_STRING
            ),
            'ORDER.READY_FOR_BILLING__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Ready_For_Billing__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_BOOLEAN
            ),
            'ORDER.SERVICE_APPOINTMENT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Service_Appointment__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_ID
            ),
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'EffectiveDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'SERVICEAPPOINTMENT.ACTUALENDTIME' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Service_Appointment__r.ActualEndTime',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATETIME
            )
        };
    }

    private static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getReceivableOrderFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.BILLING_DIARY_STATUS__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Diary_Status__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_STRING
            ),
            'ORDER.RECEIVED_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Received_Amount__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.OUTSTANDING_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Outstanding_Amount__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'EffectiveDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            )
        };
    }

    private static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getCommissionFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.BILLING_DIARY_STATUS__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Order__r.Billing_Diary_Status__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_STRING
            ),
            'ORDER.RECEIVED_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Order__r.Received_Amount__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.OUTSTANDING_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Order__r.Outstanding_Amount__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Order__r.EffectiveDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'COMMISSION__C.COMMISSION_PAID__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Commission_Paid__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            )
        };
    }

    private static Boolean evaluateDateTimeFilter(
        Datetime fieldValue,
        BillingControl_DataProvider.BillingFilterDTO filterRecord
    ) {
        String operatorValue = normalizeFilterValue(filterRecord != null ? filterRecord.operator : null);
        if (operatorValue == 'IS NULL') {
            return fieldValue == null;
        }
        if (operatorValue == 'IS NOT NULL') {
            return fieldValue != null;
        }
        if (fieldValue == null) {
            return false;
        }

        Datetime comparisonValue = resolveDatetimeFilterValue(filterRecord);
        if (comparisonValue == null) {
            return false;
        }
        return compareComparable(fieldValue.getTime(), comparisonValue.getTime(), operatorValue);
    }

    private static void addRuntimeWarning(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        String warning
    ) {
        if (filterContext == null || String.isBlank(warning)) {
            return;
        }
        if (filterContext.runtimeWarnings == null) {
            filterContext.runtimeWarnings = new List<String>();
        }
        if (!filterContext.runtimeWarnings.contains(warning)) {
            filterContext.runtimeWarnings.add(warning);
        }
    }

    private static Map<Id, Order> resolveBillingDiaryOrdersForBilling(
        List<ServiceAppointment> appointmentsToBill
    ) {
        Map<Id, Order> orderByAppointmentId = new Map<Id, Order>();
        if (appointmentsToBill == null || appointmentsToBill.isEmpty()) {
            return orderByAppointmentId;
        }

        Set<Id> appointmentIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : appointmentsToBill) {
            appointmentIds.add(appointmentRecord.Id);
        }

        for (Order orderRecord : [
            SELECT Id,
                OpportunityId,
                Opportunity.Amount,
                Service_Appointment__c,
                Billing_Diary_Status__c,
                Ready_For_Billing__c,
                Invoiced_Amount__c
            FROM Order
            WHERE Service_Appointment__c IN :appointmentIds
            AND Billing_Diary_Status__c = :ORDER_DIARY_STATUS_READY_TO_BILL
            AND Ready_For_Billing__c = true
            AND (Invoiced_Amount__c = NULL OR Invoiced_Amount__c = 0)
        ]) {
            Id appointmentId = (Id) orderRecord.get('Service_Appointment__c');
            if (appointmentId == null) {
                continue;
            }
            if (orderByAppointmentId.containsKey(appointmentId)) {
                throw buildHandledException(
                    'Complete Billing found multiple ready-to-bill Order diary records for Service Appointment ' +
                    String.valueOf(appointmentId) + '.'
                );
            }
            orderByAppointmentId.put(appointmentId, orderRecord);
        }

        for (ServiceAppointment appointmentRecord : appointmentsToBill) {
            if (!orderByAppointmentId.containsKey(appointmentRecord.Id)) {
                throw buildHandledException(
                    'Complete Billing requires one ready-to-bill Order diary record for Service Appointment ' +
                    String.valueOf(appointmentRecord.Id) + '.'
                );
            }
            if (orderByAppointmentId.get(appointmentRecord.Id).OpportunityId == null) {
                throw buildHandledException(
                    'Complete Billing requires Order.OpportunityId for Service Appointment '
                    + String.valueOf(appointmentRecord.Id)
                    + '.'
                );
            }
        }

        return orderByAppointmentId;
    }

    private static Map<Id, Decimal> queryHistoricalInvoiceTotalByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Decimal> totalByOpportunityId = new Map<Id, Decimal>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return totalByOpportunityId;
        }

        for (AggregateResult aggregateRow : [
            SELECT Opportunity__c opportunityId, SUM(Line_Total__c) totalAmount
            FROM Invoice_Line__c
            WHERE Opportunity__c IN :opportunityIds
            GROUP BY Opportunity__c
        ]) {
            totalByOpportunityId.put(
                (Id) aggregateRow.get('opportunityId'),
                coalesceDecimal((Decimal) aggregateRow.get('totalAmount'))
            );
        }

        // Legacy invoice headers may predate Invoice_Line__c records. Count only headers with no
        // lines so they are not double-counted with the authoritative line totals above.
        for (AggregateResult aggregateRow : [
            SELECT Opportunity__c opportunityId, SUM(Total_Amount__c) totalAmount
            FROM Invoice__c
            WHERE Opportunity__c IN :opportunityIds
            AND Id NOT IN (SELECT Invoice__c FROM Invoice_Line__c WHERE Invoice__c != NULL)
            GROUP BY Opportunity__c
        ]) {
            Id opportunityId = (Id) aggregateRow.get('opportunityId');
            Decimal totalAmount = coalesceDecimal((Decimal) aggregateRow.get('totalAmount'));
            totalByOpportunityId.put(
                opportunityId,
                (totalByOpportunityId.containsKey(opportunityId) ? totalByOpportunityId.get(opportunityId) : 0)
                + totalAmount
            );
        }
        return totalByOpportunityId;
    }

    private static Map<Id, Decimal> allocateInvoiceTotalAcrossAppointments(
        Decimal invoiceTotal,
        List<ServiceAppointment> appointments
    ) {
        Map<Id, Decimal> amountByAppointmentId = new Map<Id, Decimal>();
        if (invoiceTotal == null || appointments == null || appointments.isEmpty()) {
            return amountByAppointmentId;
        }

        Decimal amountPerAppointment = (invoiceTotal / appointments.size()).setScale(2, RoundingMode.DOWN);
        Decimal finalAppointmentAmount = invoiceTotal - (amountPerAppointment * (appointments.size() - 1));
        for (Integer indexValue = 0; indexValue < appointments.size(); indexValue++) {
            amountByAppointmentId.put(
                appointments[indexValue].Id,
                indexValue == appointments.size() - 1 ? finalAppointmentAmount : amountPerAppointment
            );
        }
        return amountByAppointmentId;
    }

    private static String getInvoicedOrderDiaryStatusForUpdate() {
        String firstActiveStatus = null;
        String partiallyPaidStatus = null;
        for (Schema.PicklistEntry entry : Order.Billing_Diary_Status__c.getDescribe().getPicklistValues()) {
            if (entry == null || !entry.isActive()) {
                continue;
            }
            if (firstActiveStatus == null) {
                firstActiveStatus = entry.getValue();
            }
            if (entry.getValue() == ORDER_DIARY_STATUS_INVOICED) {
                return entry.getValue();
            }
            if (entry.getValue() == PARTIALLY_PAID) {
                partiallyPaidStatus = entry.getValue();
            }
        }
        return partiallyPaidStatus != null
            ? partiallyPaidStatus
            : (firstActiveStatus != null ? firstActiveStatus : ORDER_DIARY_STATUS_READY_TO_BILL);
    }

    private static Boolean evaluateFilter(Object fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        String operatorValue = normalizeFilterValue(filterRecord.operator);
        if (operatorValue == 'IS NULL') {
            return fieldValue == null;
        }
        if (operatorValue == 'IS NOT NULL') {
            return fieldValue != null;
        }
        if (fieldValue == null) {
            return false;
        }

        if (fieldValue instanceof Datetime) {
            Datetime comparisonValue = resolveDatetimeFilterValue(filterRecord);
            if (comparisonValue == null) {
                return false;
            }
            return compareComparable(((Datetime) fieldValue).getTime(), comparisonValue.getTime(), operatorValue);
        }

        if (fieldValue instanceof Date) {
            Date comparisonValue = resolveDateFilterValue(filterRecord);
            if (comparisonValue == null) {
                return false;
            }
            Long fieldDayNumber = Date.newInstance(1970, 1, 1).daysBetween((Date) fieldValue);
            Long comparisonDayNumber = Date.newInstance(1970, 1, 1).daysBetween(comparisonValue);
            return compareComparable(fieldDayNumber, comparisonDayNumber, operatorValue);
        }

        if (
            fieldValue instanceof Decimal
            || fieldValue instanceof Integer
            || fieldValue instanceof Long
            || fieldValue instanceof Double
        ) {
            Decimal comparisonValue = resolveDecimalFilterValue(filterRecord);
            if (comparisonValue == null) {
                return false;
            }
            return compareComparable(toDecimal(fieldValue), comparisonValue, operatorValue);
        }

        return compareStringValue(String.valueOf(fieldValue), filterRecord, operatorValue);
    }

    private static Boolean evaluateDateFilter(Date fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        String operatorValue = normalizeFilterValue(filterRecord.operator);
        if (operatorValue == 'IS NULL') {
            return fieldValue == null;
        }
        if (operatorValue == 'IS NOT NULL') {
            return fieldValue != null;
        }
        if (fieldValue == null) {
            return false;
        }

        Date comparisonValue = resolveDateFilterValue(filterRecord);
        if (comparisonValue == null) {
            return false;
        }

        Long fieldDayNumber = Date.newInstance(1970, 1, 1).daysBetween(fieldValue);
        Long comparisonDayNumber = Date.newInstance(1970, 1, 1).daysBetween(comparisonValue);
        return compareComparable(fieldDayNumber, comparisonDayNumber, operatorValue);
    }

    private static Boolean compareStringValue(String fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord, String operatorValue) {
        String normalizedFieldValue = normalizeFilterValue(fieldValue);
        List<String> comparisonValues = splitFilterValues(filterRecord.value);
        if (operatorValue == 'EQUALS') {
            return normalizedFieldValue == normalizeFilterValue(filterRecord.value);
        }
        if (operatorValue == 'NOT EQUALS') {
            return normalizedFieldValue != normalizeFilterValue(filterRecord.value);
        }
        if (operatorValue == 'IN') {
            return comparisonValues.contains(normalizedFieldValue);
        }
        if (operatorValue == 'NOT IN') {
            return !comparisonValues.contains(normalizedFieldValue);
        }
        return false;
    }

    private static Boolean compareComparable(Long fieldValue, Long comparisonValue, String operatorValue) {
        if (operatorValue == 'EQUALS') {
            return fieldValue == comparisonValue;
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldValue != comparisonValue;
        }
        if (operatorValue == 'GREATER THAN') {
            return fieldValue > comparisonValue;
        }
        if (operatorValue == 'GREATER OR EQUAL') {
            return fieldValue >= comparisonValue;
        }
        if (operatorValue == 'LESS THAN') {
            return fieldValue < comparisonValue;
        }
        if (operatorValue == 'LESS OR EQUAL') {
            return fieldValue <= comparisonValue;
        }
        return false;
    }

    private static Boolean compareComparable(Decimal fieldValue, Decimal comparisonValue, String operatorValue) {
        if (operatorValue == 'EQUALS') {
            return fieldValue == comparisonValue;
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldValue != comparisonValue;
        }
        if (operatorValue == 'GREATER THAN') {
            return fieldValue > comparisonValue;
        }
        if (operatorValue == 'GREATER OR EQUAL') {
            return fieldValue >= comparisonValue;
        }
        if (operatorValue == 'LESS THAN') {
            return fieldValue < comparisonValue;
        }
        if (operatorValue == 'LESS OR EQUAL') {
            return fieldValue <= comparisonValue;
        }
        return false;
    }

    private static Datetime resolveDatetimeFilterValue(BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        if (normalizeFilterValue(filterRecord.valueType) == 'DATE LITERAL') {
            Date literalDate = resolveDateLiteralValue(filterRecord.value);
            return literalDate == null ? null : Datetime.newInstance(literalDate, Time.newInstance(0, 0, 0, 0));
        }
        try {
            return Datetime.valueOf(filterRecord.value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date resolveDateFilterValue(BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        if (normalizeFilterValue(filterRecord.valueType) == 'DATE LITERAL') {
            return resolveDateLiteralValue(filterRecord.value);
        }
        try {
            return Date.valueOf(filterRecord.value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal resolveDecimalFilterValue(BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        try {
            return Decimal.valueOf(filterRecord.value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date resolveDateLiteralValue(String value) {
        String normalizedValue = normalizeFilterValue(value);
        Date todayDate = Date.today();
        if (normalizedValue == 'TODAY') {
            return todayDate;
        }
        if (normalizedValue == 'YESTERDAY') {
            return todayDate.addDays(-1);
        }
        if (normalizedValue == 'TOMORROW') {
            return todayDate.addDays(1);
        }
        if (normalizedValue == 'THIS WEEK') {
            return todayDate.toStartOfWeek();
        }
        if (normalizedValue == 'THIS MONTH') {
            return Date.newInstance(todayDate.year(), todayDate.month(), 1);
        }
        if (normalizedValue == 'THIS QUARTER') {
            Integer quarterStartMonth = (((todayDate.month() - 1) / 3) * 3) + 1;
            return Date.newInstance(todayDate.year(), quarterStartMonth, 1);
        }
        if (normalizedValue == 'THIS YEAR') {
            return Date.newInstance(todayDate.year(), 1, 1);
        }
        if (normalizedValue != null && normalizedValue.startsWith('LAST_N_DAYS:')) {
            return todayDate.addDays(-Integer.valueOf(normalizedValue.substring('LAST_N_DAYS:'.length())));
        }
        if (normalizedValue != null && normalizedValue.startsWith('NEXT_N_DAYS:')) {
            return todayDate.addDays(Integer.valueOf(normalizedValue.substring('NEXT_N_DAYS:'.length())));
        }
        if (normalizedValue != null && normalizedValue.startsWith('LAST_N_YEARS:')) {
            return todayDate.addYears(-Integer.valueOf(normalizedValue.substring('LAST_N_YEARS:'.length())));
        }
        return null;
    }

    private static List<String> splitFilterValues(String value) {
        List<String> values = new List<String>();
        if (String.isBlank(value)) {
            return values;
        }
        for (String token : value.split(';')) {
            values.add(normalizeFilterValue(token));
        }
        return values;
    }

    private static String normalizeFilterValue(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
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

        public CommissionMetricsWrapper() {
            unbilledRevenue = 0;
            unbilledRevenueCount = 0;
            revenueUnderCollection = 0;
            revenueUnderCollectionCount = 0;
            commissionEarned = 0;
            commissionEarnedCount = 0;
            commissionPayable = 0;
            commissionPayableCount = 0;
        }
    }

    public class SalespersonWrapper {
        @AuraEnabled public Id salespersonId;
        @AuraEnabled public String salespersonName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalCommission;
        @AuraEnabled public Decimal totalPaid;
        @AuraEnabled public List<OpportunityWrapper> opportunities;

        public SalespersonWrapper() {
            totalAmount = 0;
            totalCommission = 0;
            totalPaid = 0;
            opportunities = new List<OpportunityWrapper>();
        }
    }

    public class CommissionKpiCategoryWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalCommission;
        @AuraEnabled public Decimal totalPaid;
        @AuraEnabled public List<SalespersonWrapper> salespersonGroups;

        public CommissionKpiCategoryWrapper(String categoryKeyValue, String categoryLabelValue) {
            categoryKey = categoryKeyValue;
            categoryLabel = categoryLabelValue;
            opportunityCount = 0;
            totalAmount = 0;
            totalCommission = 0;
            totalPaid = 0;
            salespersonGroups = new List<SalespersonWrapper>();
        }
    }

    public class ServiceAppointmentRowWrapper {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public String serviceAppointmentStatus;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public Decimal invoiceableOpportunityAmount;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String serviceAppointmentDisplay;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime completionDateTime;
        @AuraEnabled public Id technicianId;
        @AuraEnabled public String technicianName;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public Boolean readyForBilling;
        @AuraEnabled public Decimal invoicedAmount;
        @AuraEnabled public Decimal receivedAmount;
        @AuraEnabled public Decimal outstandingAmount;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public List<ServiceAppointmentRowWrapper> relatedServiceAppointments;
    }

    public class ServiceAppointmentOpportunityGroupWrapper {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public String opportunityBillingStatus;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public Decimal totalBillableAmount;
        @AuraEnabled public String billingState;
        @AuraEnabled public List<ServiceAppointmentRowWrapper> rows;
    }

    public class ServiceAppointmentKpiCategoryWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public Decimal totalBillableAmount;
        @AuraEnabled public List<ServiceAppointmentRowWrapper> rows;
        @AuraEnabled public List<ServiceAppointmentOpportunityGroupWrapper> opportunityGroups;

        public ServiceAppointmentKpiCategoryWrapper(String categoryKeyValue, String categoryLabelValue) {
            categoryKey = categoryKeyValue;
            categoryLabel = categoryLabelValue;
            serviceAppointmentCount = 0;
            totalBillableAmount = 0;
            rows = new List<ServiceAppointmentRowWrapper>();
            opportunityGroups = new List<ServiceAppointmentOpportunityGroupWrapper>();
        }
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

    private class ReceivableOrderSummary {
        public Id opportunityId;
        public String opportunityName;
        public String accountName;
        public Date closeDate;
        public Id ownerId;
        public String ownerName;
        public String billingStatus;
        public Decimal amount;
        public Decimal amountPaid;
        public Decimal balanceDue;
    }
}