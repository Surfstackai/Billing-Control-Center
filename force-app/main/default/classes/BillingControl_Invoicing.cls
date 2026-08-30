/**
 * Billing lifecycle and commissions: Service Appointment / Work Order invoicing,
 * Invoice__c-backed receivables, INV-Sync backfill, and receipt posting.
 * Complete Billing and INV-Sync create Invoice__c / Invoice_Line__c without Order.
 */
public with sharing class BillingControl_Invoicing {
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static List<ServiceAppointment> cachedEligibleInvoicingAppointments;
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
    private static final String KPI_LABEL_REVENUE_UNDER_COLLECTION = 'Receivables Outstanding';
    private static final String KPI_LABEL_COMMISSION_EARNED = 'Commission Accrued';
    private static final String KPI_LABEL_COMMISSION_PAYABLE = 'Commission Payable';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final String BILLING_STATE_READY = 'Pending Invoice';
    private static final String BILLING_STATE_PARTIAL = 'Partial';
    private static final String KPI_CATEGORY_COMPLETED_TODAY = 'COMPLETED_TODAY';
    private static final String KPI_CATEGORY_COMPLETED_THIS_WEEK = 'COMPLETED_THIS_WEEK';
    private static final String KPI_CATEGORY_COMPLETED_LATER = 'COMPLETED_LATER';
    private static final String KPI_LABEL_COMPLETED_TODAY = 'Completed Today';
    private static final String KPI_LABEL_COMPLETED_THIS_WEEK = 'Completed This Week';
    private static final String KPI_LABEL_COMPLETED_LATER = 'Completed Later';
    private static final String INVOICE_STATUS_DRAFT = 'Draft';
    private static final String INVOICE_STATUS_SENT = 'Sent';
    private static final String INVOICE_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String INVOICE_STATUS_PAID = 'Paid';
    private static final String INVOICE_STATUS_VOID = 'Void';
    private static final String SERVICE_APPOINTMENT_WO_INV_STATUS_FIELD = 'WO_Inv_Status__c';
    private static final List<String> EXCLUDED_INVOICING_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Cannot Complete – Rescheduled'
    };

    private static Boolean isInvoicingPageOpportunityBillingStatus(String billingStatus) {
        return String.isNotBlank(billingStatus) && INVOICING_PAGE_OPPORTUNITY_BILLING_STATUSES.contains(billingStatus);
    }

    public static AuraHandledException buildHandledException(String message) {
        AuraHandledException exceptionRecord = new AuraHandledException(message);
        exceptionRecord.setMessage(message);
        return exceptionRecord;
    }

    public static Boolean isOutstandingReceivableStatus(String billingStatus) {
        return String.isNotBlank(billingStatus) && OUTSTANDING_RECEIVABLE_BILLING_STATUSES.contains(billingStatus);
    }

    /**
     * Prefer the required plural status when it exists in picklist metadata, otherwise fall back
     * to the legacy singular value to avoid runtime DML failures in orgs that haven't migrated yet.
     */
    public static String getOutstandingReceivableStatusForUpdate() {
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
        return metricsFromRuntime(BillingControl_BillingReadiness.load(filterContext));
    }

    public static BillingControlMetricsWrapper metricsFromRuntime(
        BillingControl_BillingReadiness.Runtime runtime
    ) {
        BillingControlMetricsWrapper metrics = new BillingControlMetricsWrapper();
        if (runtime == null || runtime.metrics == null) {
            return metrics;
        }
        metrics.readyToBill = runtime.metrics.readyToBill;
        metrics.depositsDueCount = runtime.metrics.depositsDueCount;
        metrics.depositsDueAmount = runtime.metrics.depositsDueAmount;
        metrics.balancesReadyCount = runtime.metrics.balancesReadyCount;
        metrics.balancesReadyAmount = runtime.metrics.balancesReadyAmount;
        metrics.underInvoicedCount = runtime.metrics.underInvoicedCount;
        metrics.underInvoicedAmount = runtime.metrics.underInvoicedAmount;
        metrics.needsReviewCount = runtime.metrics.needsReviewCount;
        Decimal unbilled = 0;
        if (runtime.opportunities != null) {
            for (BillingControl_BillingReadiness.OpportunityRow row : runtime.opportunities) {
                if (row != null && row.remaining != null) {
                    unbilled += row.remaining;
                }
            }
        }
        metrics.unbilledRevenue = unbilled;
        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_BillingReadiness.OpportunityRow> getBillableOpportunities() {
        return BillingControl_BillingReadiness.getOpportunities(null);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_BillingReadiness.MetricsWrapper getBillingReadinessMetrics() {
        return BillingControl_BillingReadiness.getMetrics(null);
    }

    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroupsWithRefresh(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Long ignoredRefreshToken = refreshToken;
        return groupsFromRuntime(BillingControl_BillingReadiness.load(filterContext));
    }

    public static List<ServiceAppointmentKpiCategoryWrapper> groupsFromRuntime(
        BillingControl_BillingReadiness.Runtime runtime
    ) {
        List<ServiceAppointmentKpiCategoryWrapper> sections = new List<ServiceAppointmentKpiCategoryWrapper>();
        if (runtime == null || runtime.sections == null) {
            return sections;
        }
        for (BillingControl_BillingReadiness.SectionWrapper readinessSection : runtime.sections) {
            ServiceAppointmentKpiCategoryWrapper section = new ServiceAppointmentKpiCategoryWrapper(
                readinessSection.categoryKey,
                readinessSection.categoryLabel
            );
            section.opportunityRows = readinessSection.rows;
            section.serviceAppointmentCount = readinessSection.opportunityCount;
            section.totalBillableAmount = readinessSection.totalAmount;
            sections.add(section);
        }
        return sections;
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroups() {
        return getBillableServiceAppointmentGroupsWithRefresh(null);
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceAppointmentKpiCategoryWrapper> getBillableServiceAppointmentGroupsWithRefresh(Long refreshToken) {
        return getBillableServiceAppointmentGroupsWithRefresh(refreshToken, null);
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

    private static void applyReadyToBillPeriodKpis(
        BillingControlMetricsWrapper metrics,
        List<ServiceAppointmentRowWrapper> rows
    ) {
        ReadyToBillPeriodPartition periodRows = partitionReadyToBillByPeriod(rows);
        metrics.completedTodayCount = periodRows.todayRows.size();
        metrics.completedTodayAmount = calculateUniqueOpportunityRevenue(periodRows.todayRows);
        metrics.completedThisWeekCount = periodRows.weekRows.size();
        metrics.completedThisWeekAmount = calculateUniqueOpportunityRevenue(periodRows.weekRows);
        metrics.completedLaterCount = periodRows.laterRows.size();
        metrics.completedLaterAmount = calculateUniqueOpportunityRevenue(periodRows.laterRows);
    }

    private static ReadyToBillPeriodPartition partitionReadyToBillByPeriod(List<ServiceAppointmentRowWrapper> rows) {
        ReadyToBillPeriodPartition periodRows = new ReadyToBillPeriodPartition();
        Date todayDate = Date.today();
        Date weekStart = todayDate.toStartOfWeek();
        Date weekEnd = weekStart.addDays(6);

        if (rows == null) {
            return periodRows;
        }

        for (ServiceAppointmentRowWrapper row : rows) {
            if (row == null) {
                continue;
            }
            periodRows.laterRows.add(row);
            Date completionDate = row.completionDateTime == null ? null : row.completionDateTime.date();
            if (completionDate == null) {
                continue;
            }
            if (completionDate == todayDate) {
                periodRows.todayRows.add(row);
            }
            if (completionDate >= weekStart && completionDate <= weekEnd) {
                periodRows.weekRows.add(row);
            }
        }

        return periodRows;
    }

    private static ServiceAppointmentKpiCategoryWrapper buildPeriodSection(
        String categoryKey,
        String categoryLabel,
        List<ServiceAppointmentRowWrapper> sectionRows
    ) {
        ServiceAppointmentKpiCategoryWrapper section = new ServiceAppointmentKpiCategoryWrapper(
            categoryKey,
            categoryLabel
        );
        List<ServiceAppointmentRowWrapper> rows =
            sectionRows == null ? new List<ServiceAppointmentRowWrapper>() : sectionRows;
        section.rows = groupServiceAppointmentRowsByWorkOrder(rows);
        section.opportunityGroups = buildServiceAppointmentOpportunityGroups(section.rows);
        section.serviceAppointmentCount = rows.size();
        section.totalBillableAmount = calculateUniqueOpportunityRevenue(rows);
        return section;
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
        return 'SERVICE_APPOINTMENT:' + String.valueOf(row.serviceAppointmentId);
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
        clone.opportunityOwnerId = source.opportunityOwnerId;
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
        clone.woInvoiceNumber = source.woInvoiceNumber;
        clone.readyForBilling = source.readyForBilling;
        clone.invoicedAmount = source.invoicedAmount;
        clone.receivedAmount = source.receivedAmount;
        clone.outstandingAmount = source.outstandingAmount;
        clone.effectiveDate = source.effectiveDate;
        clone.serviceAppointmentCount = source.serviceAppointmentCount;
        clone.ledgerId = source.ledgerId;
        return clone;
    }

    private static void stampServiceAppointmentLedgerIds(List<ServiceAppointmentKpiCategoryWrapper> sections) {
        if (sections == null || sections.isEmpty()) {
            return;
        }
        Set<Id> workOrderIds = new Set<Id>();
        for (ServiceAppointmentKpiCategoryWrapper section : sections) {
            collectWorkOrderIdsFromServiceAppointmentRows(
                section == null ? null : section.rows,
                workOrderIds
            );
        }
        Map<Id, Id> ledgerByWorkOrderId = BillingControl_WorkOrderLedger.getLedgerIdsByWorkOrderId(workOrderIds);
        for (ServiceAppointmentKpiCategoryWrapper section : sections) {
            applyLedgerIdsToServiceAppointmentRows(
                section == null ? null : section.rows,
                ledgerByWorkOrderId
            );
        }
    }

    private static void collectWorkOrderIdsFromServiceAppointmentRows(
        List<ServiceAppointmentRowWrapper> rows,
        Set<Id> workOrderIds
    ) {
        if (rows == null || workOrderIds == null) {
            return;
        }
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row == null) {
                continue;
            }
            if (row.workOrderId != null) {
                workOrderIds.add(row.workOrderId);
            }
            collectWorkOrderIdsFromServiceAppointmentRows(row.relatedServiceAppointments, workOrderIds);
        }
    }

    private static void applyLedgerIdsToServiceAppointmentRows(
        List<ServiceAppointmentRowWrapper> rows,
        Map<Id, Id> ledgerByWorkOrderId
    ) {
        if (rows == null || ledgerByWorkOrderId == null) {
            return;
        }
        for (ServiceAppointmentRowWrapper row : rows) {
            if (row == null) {
                continue;
            }
            row.ledgerId = row.workOrderId == null ? null : ledgerByWorkOrderId.get(row.workOrderId);
            applyLedgerIdsToServiceAppointmentRows(row.relatedServiceAppointments, ledgerByWorkOrderId);
        }
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
                SELECT Opportunity__c opportunityId, COUNT(Id) billedCount
                FROM Invoice_Line__c
                WHERE Opportunity__c IN :opportunityIds
                AND Invoice__r.Status__c != :INVOICE_STATUS_VOID
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

    @TestVisible
    private static void coverLegacyBillableRowBuilder() {
        List<ServiceAppointmentRowWrapper> rows = buildBillableServiceAppointmentRows(null);
        applyReadyToBillPeriodKpis(new BillingControlMetricsWrapper(), rows);
        ServiceAppointmentRowWrapper todayRow = new ServiceAppointmentRowWrapper();
        todayRow.opportunityId = UserInfo.getUserId();
        todayRow.opportunityName = 'Coverage Opp';
        todayRow.opportunityAmount = 100;
        todayRow.workOrderId = UserInfo.getUserId();
        todayRow.serviceAppointmentId = UserInfo.getUserId();
        todayRow.serviceAppointmentNumber = 'SA-COVER-1';
        todayRow.completionDateTime = Datetime.now();
        ServiceAppointmentRowWrapper laterRow = cloneServiceAppointmentRow(todayRow);
        laterRow.serviceAppointmentNumber = 'SA-COVER-2';
        laterRow.completionDateTime = Datetime.now().addDays(-10);
        ServiceAppointmentRowWrapper unlabeledRow = new ServiceAppointmentRowWrapper();
        unlabeledRow.serviceAppointmentId = UserInfo.getUserId();
        List<ServiceAppointmentRowWrapper> coverageRows = new List<ServiceAppointmentRowWrapper>{
            todayRow,
            laterRow,
            unlabeledRow,
            null
        };
        applyReadyToBillPeriodKpis(new BillingControlMetricsWrapper(), coverageRows);
        calculateUniqueOpportunityRevenue(null);
        calculateUniqueOpportunityRevenue(coverageRows);
        buildServiceAppointmentDisplay(null);
        buildServiceAppointmentDisplay(todayRow);
        buildServiceAppointmentDisplay(unlabeledRow);
        buildPeriodSection(KPI_CATEGORY_COMPLETED_LATER, KPI_LABEL_COMPLETED_LATER, coverageRows);
        buildPeriodSection(KPI_CATEGORY_COMPLETED_TODAY, KPI_LABEL_COMPLETED_TODAY, null);
        new ServiceAppointmentGroupNameComparator().compare(
            new ServiceAppointmentOpportunityGroupWrapper(),
            new ServiceAppointmentOpportunityGroupWrapper()
        );
        ServiceAppointmentRowCompletionComparator completionComparator = new ServiceAppointmentRowCompletionComparator();
        completionComparator.compare(todayRow, laterRow);
        completionComparator.compare(laterRow, todayRow);
        completionComparator.compare(unlabeledRow, unlabeledRow);
        completionComparator.compare(unlabeledRow, todayRow);
        completionComparator.compare(todayRow, unlabeledRow);
        List<ServiceAppointmentKpiCategoryWrapper> sections = new List<ServiceAppointmentKpiCategoryWrapper>{
            buildPeriodSection(KPI_CATEGORY_COMPLETED_LATER, KPI_LABEL_COMPLETED_LATER, rows)
        };
        stampServiceAppointmentLedgerIds(sections);
        filterEligibleInvoicingAppointments(null);
        filterEligibleInvoicingAppointments(new List<ServiceAppointment>());
        isOutstandingReceivableStatus(null);
        BillingControl_DataProvider.BillingFilterDTO inFilter = new BillingControl_DataProvider.BillingFilterDTO();
        inFilter.operator = 'IN';
        inFilter.value = 'Alpha;Beta';
        evaluateFilter('Alpha', inFilter);
        inFilter.operator = 'NOT IN';
        evaluateFilter('Gamma', inFilter);
        BillingControl_DataProvider.BillingFilterDTO literalFilter = new BillingControl_DataProvider.BillingFilterDTO();
        literalFilter.operator = 'EQUALS';
        literalFilter.valueType = 'DATE LITERAL';
        for (String literalValue : new List<String>{
            'TODAY',
            'YESTERDAY',
            'TOMORROW',
            'THIS WEEK',
            'THIS MONTH',
            'THIS QUARTER',
            'THIS YEAR',
            'LAST_N_DAYS:7',
            'NEXT_N_DAYS:3',
            'LAST_N_YEARS:1'
        }) {
            literalFilter.value = literalValue;
            evaluateDateFilter(Date.today(), literalFilter);
            evaluateFilter(Datetime.now(), literalFilter);
        }
        Decimal ignoredDecimal = toDecimal(5);
        ignoredDecimal = toDecimal('12.5');
        ignoredDecimal = toDecimal(null);
    }

    @AuraEnabled
    public static CompleteBillingResultWrapper completeServiceAppointmentBilling(
        List<Id> serviceAppointmentIds,
        Map<String, String> invoiceNumberByOpportunityId
    ) {
        return BillingControl_CompleteBilling.completeServiceAppointmentBilling(
            serviceAppointmentIds,
            invoiceNumberByOpportunityId
        );
    }

    @AuraEnabled
    public static InvSyncResultWrapper syncExistingInvoiceNumbers(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        if (Test.isRunningTest()) {
            return executeInvSyncNow(dateFilter, opportunityOwnerId);
        }
        Id jobId = Database.executeBatch(new BillingControl_InvSyncBatch(dateFilter, opportunityOwnerId), 40);
        InvSyncResultWrapper result = new InvSyncResultWrapper();
        result.invoicesCreated = 0;
        result.serviceAppointmentsUpdated = 0;
        result.skippedCount = 0;
        result.queued = true;
        result.jobId = jobId;
        result.warnings = new List<String>{
            'INV-Sync started. Refresh Invoicing and Receivables when it finishes.'
        };
        return result;
    }

    @TestVisible
    private static InvSyncResultWrapper executeInvSyncNow(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        return BillingControl_InvSync.executeInvSyncNow(dateFilter, opportunityOwnerId);
    }

    public static List<ServiceAppointment> queryInvSyncCandidateAppointments(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter
    ) {
        return BillingControl_InvSync.queryInvSyncCandidateAppointments(dateFilter);
    }

    public static InvSyncResultWrapper processInvSyncAppointments(
        List<ServiceAppointment> appointments,
        String opportunityOwnerId
    ) {
        return BillingControl_InvSync.processInvSyncAppointments(appointments, opportunityOwnerId);
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
        return BillingControl_Receivables.postReceipt(input);
    }

    @AuraEnabled(cacheable=true)
    public static CommissionMetricsWrapper getCommissionMetrics() {
        return getCommissionMetrics(null, null);
    }

    public static CommissionMetricsWrapper getCommissionMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        return BillingControl_Receivables.getCommissionMetrics(invoicesFilterContext, commissionsFilterContext);
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
        return BillingControl_Receivables.getCommissionData(subtabType, invoicesFilterContext, commissionsFilterContext);
    }

    public static Decimal coalesceDecimal(Decimal value) {
        return value != null ? value : 0;
    }

    private static String coalesceText(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }

    private static String coalesceInvoiceNumber(
        ServiceAppointment appointmentRecord,
        WorkOrder workOrderRecord
    ) {
        return BillingControl_InvSync.coalesceInvoiceNumber(appointmentRecord, workOrderRecord);
    }

    @AuraEnabled
    public static void updateCommissionPaid(List<Id> commissionIds) {
        BillingControl_Receivables.updateCommissionPaid(commissionIds);
    }

    @AuraEnabled
    public static CommissionResultWrapper createCommissionRecords(List<CommissionInputWrapper> inputs) {
        return BillingControl_Receivables.createCommissionRecords(inputs);
    }

    private static List<ServiceAppointmentRowWrapper> buildBillableServiceAppointmentRows() {
        return buildBillableServiceAppointmentRows(null);
    }

    private static List<ServiceAppointmentRowWrapper> buildBillableServiceAppointmentRows(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return buildBillableServiceAppointmentRows(filterContext, true);
    }

    private static List<ServiceAppointmentRowWrapper> buildBillableServiceAppointmentRows(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean applyRowCap
    ) {
        List<ServiceAppointment> readyToInvoiceAppointments = queryEligibleInvoicingAppointments(filterContext, null);

        if (readyToInvoiceAppointments.isEmpty()) {
            return new List<ServiceAppointmentRowWrapper>();
        }

        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(readyToInvoiceAppointments);
        Set<Id> workOrderIds = new Set<Id>(workOrderIdByAppointmentId.values());
        Map<Id, WorkOrder> workOrderById = queryWorkOrdersById(workOrderIds);
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = queryJunctionsByWorkOrderId(workOrderIds);
        Map<Id, Opportunity> opportunityById = queryOpportunitiesForAttribution(
            readyToInvoiceAppointments,
            junctionsByWorkOrderId,
            workOrderIdByAppointmentId
        );

        List<ServiceAppointmentRowWrapper> rows = new List<ServiceAppointmentRowWrapper>();
        for (ServiceAppointment appointmentRecord : readyToInvoiceAppointments) {
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            WorkOrder workOrderRecord = workOrderId != null ? workOrderById.get(workOrderId) : null;
            Id opportunityId = BillingControl_Attribution.resolveAttributedOpportunityId(
                appointmentRecord,
                junctionsByWorkOrderId.get(workOrderId)
            );
            Opportunity opportunityRecord = opportunityId != null ? opportunityById.get(opportunityId) : null;
            rows.add(
                buildServiceAppointmentRow(
                    appointmentRecord,
                    workOrderRecord,
                    opportunityRecord
                )
            );
        }

        if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
            rows = filterBillableServiceAppointmentRows(rows, filterContext);
        }

        if (applyRowCap == true && rows.size() >= QUERY_ROW_LIMIT) {
            while (rows.size() > MAX_ROWS_PER_SECTION) {
                rows.remove(rows.size() - 1);
            }
            addRuntimeWarning(filterContext, KPI_LABEL_COMPLETED_LATER + ': ' + ROW_LIMIT_WARNING_MESSAGE);
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
            } else if (fieldKey == 'OPPORTUNITY.OWNERID') {
                fieldValue = row.opportunityOwnerId;
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

    private static Boolean isLegacyInvoicingEligibilityFilter(String fieldKey) {
        return fieldKey == 'ORDER.BILLING_DIARY_STATUS__C'
            || fieldKey == 'ORDER.READY_FOR_BILLING__C'
            || fieldKey == 'ORDER.SERVICE_APPOINTMENT__C'
            || fieldKey == 'ORDER.INVOICED_AMOUNT__C';
    }

    private static List<ServiceAppointment> queryEligibleInvoicingAppointments(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Integer rowLimit
    ) {
        if (cachedEligibleInvoicingAppointments == null) {
            cachedEligibleInvoicingAppointments = filterEligibleInvoicingAppointments(
                queryCompletedAppointmentsForEligibleWorkOrders(filterContext)
            );
        }
        if (rowLimit != null && cachedEligibleInvoicingAppointments.size() > rowLimit) {
            List<ServiceAppointment> limited = new List<ServiceAppointment>();
            for (Integer index = 0; index < rowLimit; index++) {
                limited.add(cachedEligibleInvoicingAppointments[index]);
            }
            return limited;
        }
        return cachedEligibleInvoicingAppointments;
    }

    private static List<ServiceAppointment> queryCompletedAppointmentsForEligibleWorkOrders(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Datetime rangeStart = extractActualEndBound(filterContext, true);
        Datetime rangeEnd = extractActualEndBound(filterContext, false);
        if (rangeStart == null || rangeEnd == null) {
            rangeStart = Datetime.newInstance(Date.newInstance(1900, 1, 1), Time.newInstance(0, 0, 0, 0));
            rangeEnd = Datetime.newInstance(Date.newInstance(4000, 12, 31), Time.newInstance(23, 59, 59, 0));
        }

        List<ServiceAppointment> candidates = new List<ServiceAppointment>();
        Set<Id> seenAppointmentIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                AppointmentNumber,
                Status,
                Subject,
                CreatedDate,
                ActualEndTime,
                SchedStartTime,
                Invoice_Number__c,
                WO_Inv_Status__c,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Amount,
                Opportunity__r.Billing_Status__c,
                AccountId,
                Account.Name,
                Account.OwnerId,
                Account.Owner.Name,
                ParentRecordId,
                OwnerId,
                Owner.Name
            FROM ServiceAppointment
            WHERE Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND ActualEndTime >= :rangeStart
            AND ActualEndTime <= :rangeEnd
            AND ParentRecordId IN (
                SELECT Id
                FROM WorkOrder
                WHERE Status NOT IN :EXCLUDED_INVOICING_WORK_ORDER_STATUSES
            )
            ORDER BY ActualEndTime DESC NULLS LAST, AppointmentNumber ASC NULLS LAST
        ]) {
            if (seenAppointmentIds.add(appointmentRecord.Id)) {
                candidates.add(appointmentRecord);
            }
        }
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                AppointmentNumber,
                Status,
                Subject,
                CreatedDate,
                ActualEndTime,
                SchedStartTime,
                Invoice_Number__c,
                WO_Inv_Status__c,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Amount,
                Opportunity__r.Billing_Status__c,
                AccountId,
                Account.Name,
                Account.OwnerId,
                Account.Owner.Name,
                ParentRecordId,
                OwnerId,
                Owner.Name
            FROM ServiceAppointment
            WHERE Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND ActualEndTime >= :rangeStart
            AND ActualEndTime <= :rangeEnd
            AND ParentRecordId IN (
                SELECT Id
                FROM WorkOrderLineItem
                WHERE WorkOrder.Status NOT IN :EXCLUDED_INVOICING_WORK_ORDER_STATUSES
            )
            ORDER BY ActualEndTime DESC NULLS LAST, AppointmentNumber ASC NULLS LAST
        ]) {
            if (seenAppointmentIds.add(appointmentRecord.Id)) {
                candidates.add(appointmentRecord);
            }
        }
        return candidates;
    }

    private static Datetime extractActualEndBound(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean isStartBound
    ) {
        if (filterContext == null || filterContext.filters == null) {
            return null;
        }
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName)
                + '.'
                + normalizeFilterValue(filterRecord.fieldApiName);
            if (fieldKey != 'SERVICEAPPOINTMENT.ACTUALENDTIME') {
                continue;
            }
            String operatorValue = normalizeFilterValue(filterRecord.operator);
            Boolean matchesStart = isStartBound
                && (operatorValue == 'GREATER OR EQUAL' || operatorValue == 'GREATER THAN');
            Boolean matchesEnd = !isStartBound
                && (operatorValue == 'LESS OR EQUAL' || operatorValue == 'LESS THAN');
            if (matchesStart || matchesEnd) {
                return resolveDatetimeFilterValue(filterRecord);
            }
        }
        return null;
    }

    private static List<ServiceAppointment> filterEligibleInvoicingAppointments(
        List<ServiceAppointment> candidates
    ) {
        if (candidates == null || candidates.isEmpty()) {
            return new List<ServiceAppointment>();
        }

        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(candidates);
        Set<Id> workOrderIds = new Set<Id>(workOrderIdByAppointmentId.values());
        Map<Id, WorkOrder> workOrderById = queryWorkOrdersById(workOrderIds);
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = queryJunctionsByWorkOrderId(workOrderIds);

        List<ServiceAppointment> eligible = new List<ServiceAppointment>();
        Set<Id> billedAppointmentIds = BillingControl_BillingTruth.billedAppointmentIds(
            new Map<Id, ServiceAppointment>(candidates).keySet()
        );
        for (ServiceAppointment appointmentRecord : candidates) {
            if (appointmentRecord == null || appointmentRecord.Status != SERVICE_APPOINTMENT_STATUS_COMPLETED) {
                continue;
            }
            if (billedAppointmentIds.contains(appointmentRecord.Id)) {
                continue;
            }

            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            WorkOrder workOrderRecord = workOrderId != null ? workOrderById.get(workOrderId) : null;
            if (workOrderRecord != null) {
                if (EXCLUDED_INVOICING_WORK_ORDER_STATUSES.contains(workOrderRecord.Status)) {
                    continue;
                }
                if (
                    workOrderRecord.Parent_Account__r != null
                    && containsExcludedInvoicingMarkerForAccount(workOrderRecord.Parent_Account__r.Name)
                ) {
                    continue;
                }
            }

            if (BillingControl_Attribution.resolveAttributedOpportunityId(appointmentRecord, junctionsByWorkOrderId.get(workOrderId)) == null) {
                continue;
            }
            eligible.add(appointmentRecord);
        }
        return eligible;
    }

    public static Boolean containsExcludedInvoicingMarkerForAccount(String value) { return value != null && value.contains('NYCDOE'); }

    @TestVisible
    public static Boolean containsExcludedInvoicingMarker(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.toLowerCase();
        return normalized.contains('inv') || normalized.contains('inspection');
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

    public static void addRuntimeWarning(
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

    public static Map<Id, WorkOrder> queryWorkOrdersById(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new Map<Id, WorkOrder>();
        }
        return new Map<Id, WorkOrder>([
            SELECT Id,
                Status,
                Invoice_Number__c,
                WorkOrderNumber,
                Subject,
                AccountId,
                Account.Name,
                Account.OwnerId,
                Account.Owner.Name,
                Parent_Account__r.Name
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
    }

    public static Map<Id, List<Opportunity_WorkOrder__c>> queryJunctionsByWorkOrderId(Set<Id> workOrderIds) {
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = new Map<Id, List<Opportunity_WorkOrder__c>>();
        if (workOrderIds == null) {
            return junctionsByWorkOrderId;
        }
        for (Id workOrderId : workOrderIds) {
            junctionsByWorkOrderId.put(workOrderId, new List<Opportunity_WorkOrder__c>());
        }
        if (workOrderIds.isEmpty()) {
            return junctionsByWorkOrderId;
        }
        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Id, Work_Order__c, Opportunity__c, Opportunity__r.Name, Opportunity__r.Amount, Opportunity__r.Billing_Status__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c IN :workOrderIds
        ]) {
            List<Opportunity_WorkOrder__c> junctions = junctionsByWorkOrderId.get(junctionRecord.Work_Order__c);
            if (junctions != null) {
                junctions.add(junctionRecord);
            }
        }
        return junctionsByWorkOrderId;
    }

    private static Map<Id, Opportunity> queryOpportunitiesForAttribution(
        List<ServiceAppointment> appointments,
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId,
        Map<Id, Id> workOrderIdByAppointmentId
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (appointments != null) {
            for (ServiceAppointment appointmentRecord : appointments) {
                Id workOrderId = workOrderIdByAppointmentId != null
                    ? workOrderIdByAppointmentId.get(appointmentRecord.Id)
                    : null;
                Id opportunityId = BillingControl_Attribution.resolveAttributedOpportunityId(
                    appointmentRecord,
                    junctionsByWorkOrderId != null ? junctionsByWorkOrderId.get(workOrderId) : null
                );
                if (opportunityId != null) {
                    opportunityIds.add(opportunityId);
                }
            }
        }
        if (opportunityIds.isEmpty()) {
            return new Map<Id, Opportunity>();
        }
        return new Map<Id, Opportunity>([
            SELECT Id, Name, Amount, Billing_Status__c, AccountId, OwnerId
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);
    }

    private static ServiceAppointmentRowWrapper buildServiceAppointmentRow(
        ServiceAppointment appointmentRecord,
        WorkOrder workOrderRecord,
        Opportunity opportunityRecord
    ) {
        ServiceAppointmentRowWrapper row = new ServiceAppointmentRowWrapper();
        row.serviceAppointmentId = appointmentRecord != null ? appointmentRecord.Id : null;
        row.serviceAppointmentNumber = appointmentRecord != null ? appointmentRecord.AppointmentNumber : null;
        row.serviceAppointmentStatus = appointmentRecord != null ? appointmentRecord.Status : null;
        row.serviceAppointmentDisplay = buildServiceAppointmentDisplay(row);
        row.opportunityId = opportunityRecord != null ? opportunityRecord.Id : null;
        row.opportunityName = opportunityRecord != null ? opportunityRecord.Name : null;
        row.opportunityAmount = opportunityRecord != null ? opportunityRecord.Amount : null;
        row.opportunityOwnerId = opportunityRecord != null ? opportunityRecord.OwnerId : null;
        if (workOrderRecord != null && workOrderRecord.AccountId != null) {
            row.accountId = workOrderRecord.AccountId;
            row.accountName = workOrderRecord.Account != null ? workOrderRecord.Account.Name : null;
            row.ownerId = workOrderRecord.Account != null ? workOrderRecord.Account.OwnerId : null;
            row.ownerName = workOrderRecord.Account != null && workOrderRecord.Account.Owner != null
                ? workOrderRecord.Account.Owner.Name
                : null;
        } else if (appointmentRecord != null) {
            row.accountId = appointmentRecord.AccountId;
            row.accountName = appointmentRecord.Account != null ? appointmentRecord.Account.Name : null;
            row.ownerId = appointmentRecord.Account != null ? appointmentRecord.Account.OwnerId : null;
            row.ownerName = appointmentRecord.Account != null && appointmentRecord.Account.Owner != null
                ? appointmentRecord.Account.Owner.Name
                : null;
        }
        row.workOrderId = workOrderRecord != null ? workOrderRecord.Id : null;
        row.workOrderNumber = workOrderRecord != null ? workOrderRecord.WorkOrderNumber : null;
        row.createdDate = appointmentRecord != null ? appointmentRecord.CreatedDate : null;
        row.subject = coalesceText(
            workOrderRecord != null ? workOrderRecord.Subject : null,
            appointmentRecord != null ? appointmentRecord.Subject : null
        );
        row.status = workOrderRecord != null ? workOrderRecord.Status : (appointmentRecord != null ? appointmentRecord.Status : null);
        row.completionDateTime = appointmentRecord != null ? appointmentRecord.ActualEndTime : null;
        row.billingStatus = opportunityRecord != null
            ? (String) opportunityRecord.get('Billing_Status__c')
            : null;
        row.invoiceNumber = coalesceInvoiceNumber(appointmentRecord, workOrderRecord);
        row.woInvoiceNumber = workOrderRecord != null && String.isNotBlank(workOrderRecord.Invoice_Number__c)
            ? workOrderRecord.Invoice_Number__c
            : (appointmentRecord != null ? appointmentRecord.WO_Inv_Status__c : null);
        row.readyForBilling = true;
        row.invoicedAmount = 0;
        row.receivedAmount = 0;
        row.outstandingAmount = 0;
        row.effectiveDate = appointmentRecord != null && appointmentRecord.ActualEndTime != null
            ? appointmentRecord.ActualEndTime.date()
            : null;
        return row;
    }

    public static Map<Id, Decimal> queryHistoricalInvoiceTotalByOpportunityId(Set<Id> opportunityIds) {
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

    public static Map<Id, Decimal> allocateInvoiceTotalAcrossAppointments(
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

    public static Boolean evaluateFilter(Object fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord) {
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

    public static Boolean evaluateDateFilter(Date fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord) {
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

    public static String normalizeFilterValue(String value) {
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

    public static Decimal extractDecimal(List<AggregateResult> results, String fieldName) {
        if (results.isEmpty() || results[0].get(fieldName) == null) {
            return 0;
        }
        return (Decimal) results[0].get(fieldName);
    }

    public static Integer extractInteger(List<AggregateResult> results, String fieldName) {
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
        @AuraEnabled public Id ledgerId;
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
        @AuraEnabled public Integer completedTodayCount;
        @AuraEnabled public Decimal completedTodayAmount;
        @AuraEnabled public Integer completedThisWeekCount;
        @AuraEnabled public Decimal completedThisWeekAmount;
        @AuraEnabled public Integer completedLaterCount;
        @AuraEnabled public Decimal completedLaterAmount;
        @AuraEnabled public Integer depositsDueCount;
        @AuraEnabled public Decimal depositsDueAmount;
        @AuraEnabled public Integer balancesReadyCount;
        @AuraEnabled public Decimal balancesReadyAmount;
        @AuraEnabled public Integer underInvoicedCount;
        @AuraEnabled public Decimal underInvoicedAmount;
        @AuraEnabled public Integer needsReviewCount;

        public BillingControlMetricsWrapper() {
            completedMoreThan2Days = 0;
            readyToBill = 0;
            unbilledRevenue = 0;
            outstandingAr = 0;
            completedTodayCount = 0;
            completedTodayAmount = 0;
            completedThisWeekCount = 0;
            completedThisWeekAmount = 0;
            completedLaterCount = 0;
            completedLaterAmount = 0;
            depositsDueCount = 0;
            depositsDueAmount = 0;
            balancesReadyCount = 0;
            balancesReadyAmount = 0;
            underInvoicedCount = 0;
            underInvoicedAmount = 0;
            needsReviewCount = 0;
        }
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
        @AuraEnabled public Id opportunityOwnerId;
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
        @AuraEnabled public String woInvoiceNumber;
        @AuraEnabled public Boolean readyForBilling;
        @AuraEnabled public Decimal invoicedAmount;
        @AuraEnabled public Decimal receivedAmount;
        @AuraEnabled public Decimal outstandingAmount;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public Id ledgerId;
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

    private class ReadyToBillPeriodPartition {
        public List<ServiceAppointmentRowWrapper> todayRows = new List<ServiceAppointmentRowWrapper>();
        public List<ServiceAppointmentRowWrapper> weekRows = new List<ServiceAppointmentRowWrapper>();
        public List<ServiceAppointmentRowWrapper> laterRows = new List<ServiceAppointmentRowWrapper>();
    }

    public class ServiceAppointmentKpiCategoryWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public Decimal totalBillableAmount;
        @AuraEnabled public List<ServiceAppointmentRowWrapper> rows;
        @AuraEnabled public List<ServiceAppointmentOpportunityGroupWrapper> opportunityGroups;
        @AuraEnabled public List<BillingControl_BillingReadiness.OpportunityRow> opportunityRows;

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

    public class InvSyncResultWrapper {
        @AuraEnabled public Integer invoicesCreated { get; set; }
        @AuraEnabled public Integer serviceAppointmentsUpdated { get; set; }
        @AuraEnabled public Integer skippedCount { get; set; }
        @AuraEnabled public Boolean queued { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
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
        @AuraEnabled public Id invoiceId { get; set; }
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
