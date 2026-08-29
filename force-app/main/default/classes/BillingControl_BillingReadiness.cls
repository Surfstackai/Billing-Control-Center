/**
 * Opportunity-grain billing worklist: readiness reasons, evidence tree, and KPIs.
 */
public inherited sharing class BillingControl_BillingReadiness {
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_VOID = 'Void';
    private static final String TYPE_DEPOSIT = 'Deposit';
    private static final String TIMING_NOT_REQUIRED = 'Not Required';
    private static final List<String> EXCLUDED_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Cannot Complete – Rescheduled'
    };

    public static final String REASON_DEPOSIT_DUE = 'Deposit Due';
    public static final String REASON_BALANCE_READY = 'Balance Ready';
    public static final String REASON_UNDER_INVOICED = 'Under-Invoiced';
    public static final String REASON_REVIEW = 'Review: Possible Extra Work';
    public static final String REASON_BLOCKED_ATTRIBUTION = 'Blocked: Attribution';
    public static final String REASON_BLOCKED_NO_AMOUNT = 'Blocked: No Amount';

    public static final String SECTION_DEPOSITS_DUE = 'DEPOSITS_DUE';
    public static final String SECTION_BALANCES_READY = 'BALANCES_READY';
    public static final String SECTION_UNDER_INVOICED = 'UNDER_INVOICED';
    public static final String SECTION_NEEDS_REVIEW = 'NEEDS_REVIEW';
    public static final String SECTION_BLOCKED = 'BLOCKED';

    public class InvoiceChip {
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String invoiceType;
        @AuraEnabled public String status;
    }

    public class AppointmentEvidence {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime actualEndTime;
        @AuraEnabled public String technicianName;
        @AuraEnabled public String description;
        @AuraEnabled public String serviceNote;
        @AuraEnabled public String internalServiceNote;
        @AuraEnabled public String invoiceNumberHint;
        @AuraEnabled public String woInvStatusHint;
        @AuraEnabled public Boolean billed;
        @AuraEnabled public String billedInvoiceNumber;
        @AuraEnabled public Boolean unattributed;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Boolean operationalUnassigned;
        @AuraEnabled public Boolean reviewFlag;
        @AuraEnabled public Boolean flaggedForReview;
    }

    public class WorkOrderEvidence {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String serviceNote;
        @AuraEnabled public String internalServiceNote;
        @AuraEnabled public String invoiceNumberHint;
        @AuraEnabled public String legacyDepositPayments;
        @AuraEnabled public Decimal legacyDepositAmount;
        @AuraEnabled public Id ledgerId;
        @AuraEnabled public List<AppointmentEvidence> appointments;
    }

    public class OpportunityRow {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String salespersonName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public Decimal amountQuoted;
        @AuraEnabled public Decimal invoicedTotal;
        @AuraEnabled public Decimal paidTotal;
        @AuraEnabled public Decimal remaining;
        @AuraEnabled public Decimal outstanding;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public List<String> readinessReasons;
        @AuraEnabled public List<InvoiceChip> invoices;
        @AuraEnabled public Integer completedEvidenceCount;
        @AuraEnabled public Integer billedEvidenceCount;
        @AuraEnabled public Boolean showReviewBanner;
        @AuraEnabled public List<WorkOrderEvidence> workOrders;
    }

    public class SectionWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<OpportunityRow> rows;
    }

    public class MetricsWrapper {
        @AuraEnabled public Integer depositsDueCount;
        @AuraEnabled public Decimal depositsDueAmount;
        @AuraEnabled public Integer balancesReadyCount;
        @AuraEnabled public Decimal balancesReadyAmount;
        @AuraEnabled public Integer underInvoicedCount;
        @AuraEnabled public Decimal underInvoicedAmount;
        @AuraEnabled public Integer needsReviewCount;
        @AuraEnabled public Integer blockedCount;
        @AuraEnabled public Integer readyToBill;

        public MetricsWrapper() {
            depositsDueCount = 0;
            depositsDueAmount = 0;
            balancesReadyCount = 0;
            balancesReadyAmount = 0;
            underInvoicedCount = 0;
            underInvoicedAmount = 0;
            needsReviewCount = 0;
            blockedCount = 0;
            readyToBill = 0;
        }
    }

    public class Runtime {
        public List<OpportunityRow> opportunities = new List<OpportunityRow>();
        public List<SectionWrapper> sections = new List<SectionWrapper>();
        public MetricsWrapper metrics = new MetricsWrapper();
    }

    public static Runtime load(BillingControl_DataProvider.BillingFilterContextDTO filterContext) {
        Runtime runtime = new Runtime();
        Id ownerId = extractOwnerId(filterContext);
        Datetime rangeStart = extractActualEndBound(filterContext, true);
        Datetime rangeEnd = extractActualEndBound(filterContext, false);
        if (rangeStart == null || rangeEnd == null) {
            rangeStart = Datetime.newInstance(Date.newInstance(1900, 1, 1), Time.newInstance(0, 0, 0, 0));
            rangeEnd = Datetime.newInstance(Date.newInstance(4000, 12, 31), Time.newInstance(23, 59, 59, 0));
        }

        List<ServiceAppointment> completedAppointments = queryCompletedAppointments(rangeStart, rangeEnd);
        Map<Id, Id> workOrderIdByAppointmentId =
            BillingControl_Attribution.resolveWorkOrderIdsForAppointments(completedAppointments);
        Set<Id> workOrderIds = new Set<Id>(workOrderIdByAppointmentId.values());
        workOrderIds.remove(null);
        Map<Id, WorkOrder> workOrderById = queryWorkOrders(workOrderIds);
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId =
            BillingControl_Invoicing.queryJunctionsByWorkOrderId(workOrderIds);
        Set<Id> billedAppointmentIds = BillingControl_BillingTruth.billedAppointmentIds(
            new Map<Id, ServiceAppointment>(completedAppointments).keySet()
        );
        Map<Id, String> billedInvoiceNumberByAppointmentId = billedInvoiceNumbers(
            billedAppointmentIds
        );
        Set<Id> flaggedForReviewAppointmentIds = flaggedAccountingNoteAppointmentIds(
            new Map<Id, ServiceAppointment>(completedAppointments).keySet()
        );

        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, List<ServiceAppointment>> appointmentsByOpportunityId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointmentRecord : completedAppointments) {
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            WorkOrder workOrderRecord = workOrderId == null ? null : workOrderById.get(workOrderId);
            if (workOrderRecord != null && EXCLUDED_WORK_ORDER_STATUSES.contains(workOrderRecord.Status)) {
                continue;
            }
            if (
                workOrderRecord != null
                && workOrderRecord.Parent_Account__r != null
                && BillingControl_Invoicing.containsExcludedInvoicingMarkerForAccount(
                    workOrderRecord.Parent_Account__r.Name
                )
            ) {
                continue;
            }
            Id attributedOpportunityId = BillingControl_Attribution.resolveAttributedOpportunityId(
                appointmentRecord,
                junctionsByWorkOrderId.get(workOrderId)
            );
            Set<Id> targetOpportunityIds = new Set<Id>();
            if (attributedOpportunityId != null) {
                targetOpportunityIds.add(attributedOpportunityId);
            } else {
                List<Opportunity_WorkOrder__c> junctions = junctionsByWorkOrderId.get(workOrderId);
                if (junctions != null) {
                    for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                        if (junctionRecord.Opportunity__c != null) {
                            targetOpportunityIds.add(junctionRecord.Opportunity__c);
                        }
                    }
                }
            }
            for (Id opportunityId : targetOpportunityIds) {
                opportunityIds.add(opportunityId);
                if (!appointmentsByOpportunityId.containsKey(opportunityId)) {
                    appointmentsByOpportunityId.put(opportunityId, new List<ServiceAppointment>());
                }
                appointmentsByOpportunityId.get(opportunityId).add(appointmentRecord);
            }
        }

        opportunityIds.addAll(queryDepositDueOpportunityIds(ownerId));
        if (opportunityIds.isEmpty()) {
            runtime.sections = emptySections();
            return runtime;
        }

        Map<Id, Opportunity> opportunityById = queryOpportunities(opportunityIds, ownerId);
        opportunityIds = opportunityById.keySet();
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> financialsByOpportunityId =
            BillingControl_OpportunityFinancials.load(opportunityIds);
        Map<Id, List<Invoice__c>> invoicesByOpportunityId = queryInvoices(opportunityIds);
        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId = queryLedgers(workOrderIds);
        Set<Id> opportunitiesWithDepositInvoice = opportunitiesWithDepositInvoice(invoicesByOpportunityId);

        List<OpportunityRow> rows = new List<OpportunityRow>();
        for (Id opportunityId : opportunityIds) {
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            if (opportunityRecord == null) {
                continue;
            }
            OpportunityRow row = buildOpportunityRow(
                opportunityRecord,
                appointmentsByOpportunityId.get(opportunityId),
                workOrderIdByAppointmentId,
                workOrderById,
                junctionsByWorkOrderId,
                billedAppointmentIds,
                billedInvoiceNumberByAppointmentId,
                flaggedForReviewAppointmentIds,
                financialsByOpportunityId.get(opportunityId),
                invoicesByOpportunityId.get(opportunityId),
                ledgerByWorkOrderId,
                opportunitiesWithDepositInvoice.contains(opportunityId)
            );
            if (row.readinessReasons.isEmpty()) {
                continue;
            }
            rows.add(row);
        }
        rows.sort(new OpportunityNameComparator());
        runtime.opportunities = rows;
        runtime.sections = buildSections(rows);
        runtime.metrics = buildMetrics(runtime.sections, rows.size());
        return runtime;
    }

    public class TabRuntime {
        @AuraEnabled public MetricsWrapper metrics;
        @AuraEnabled public List<SectionWrapper> groups;
        @AuraEnabled public List<String> warnings;
    }

    @AuraEnabled
    public static TabRuntime getTabRuntime(
        Long refreshToken,
        String filterKey,
        String startDate,
        String endDate,
        String opportunityOwnerId
    ) {
        Long ignoredRefreshToken = refreshToken;
        String ignoredFilterKey = filterKey;
        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.filters = new List<BillingControl_DataProvider.BillingFilterDTO>();
        if (String.isNotBlank(startDate)) {
            filterContext.filters.add(
                dateBoundFilter('Greater Or Equal', startDate + ' 00:00:00')
            );
        }
        if (String.isNotBlank(endDate)) {
            filterContext.filters.add(
                dateBoundFilter('Less Or Equal', endDate + ' 23:59:59')
            );
        }
        if (String.isNotBlank(opportunityOwnerId)) {
            BillingControl_DataProvider.BillingFilterDTO ownerFilter =
                new BillingControl_DataProvider.BillingFilterDTO();
            ownerFilter.objectApiName = 'Opportunity';
            ownerFilter.fieldApiName = 'OwnerId';
            ownerFilter.operator = 'Equals';
            ownerFilter.value = opportunityOwnerId;
            filterContext.filters.add(ownerFilter);
        }
        Runtime runtime = load(filterContext);
        TabRuntime tabRuntime = new TabRuntime();
        tabRuntime.metrics = runtime.metrics;
        tabRuntime.groups = runtime.sections;
        tabRuntime.warnings = new List<String>();
        if (runtime.metrics == null || runtime.metrics.readyToBill == 0) {
            tabRuntime.warnings.add('No billable Opportunities found.');
        }
        return tabRuntime;
    }

    @AuraEnabled
    public static void flagAppointmentForReview(Id serviceAppointmentId) {
        if (serviceAppointmentId == null) {
            throw new AuraHandledException('Select a Service Appointment.');
        }
        List<ServiceAppointment> appointments = [
            SELECT Id, ParentRecordId, AppointmentNumber, Opportunity__c
            FROM ServiceAppointment
            WHERE Id = :serviceAppointmentId
            LIMIT 1
        ];
        if (appointments.isEmpty()) {
            throw new AuraHandledException('Service Appointment not found.');
        }
        ServiceAppointment appointmentRecord = appointments[0];
        if (appointmentRecord.ParentRecordId == null) {
            throw new AuraHandledException('This visit is not linked to a Work Order.');
        }
        WorkOrderLedgerService.LedgerEvent eventRecord = new WorkOrderLedgerService.LedgerEvent();
        eventRecord.WorkOrderId = appointmentRecord.ParentRecordId;
        eventRecord.SourceRecordId = appointmentRecord.Id;
        eventRecord.EventType = 'ACCOUNTING_NOTE';
        eventRecord.EventDatetime = System.now();
        eventRecord.ChangedById = UserInfo.getUserId();
        eventRecord.ServiceAppointmentId = appointmentRecord.Id;
        eventRecord.OpportunityId = appointmentRecord.Opportunity__c;
        eventRecord.SourceObject = 'ServiceAppointment';
        eventRecord.Description = 'Flagged for billing review: ' + appointmentRecord.AppointmentNumber;
        eventRecord.SystemGenerated = false;
        String eventKey =
            'ACCOUNTING_NOTE|' + String.valueOf(appointmentRecord.Id) + '|' + String.valueOf(System.now().getTime());
        eventRecord.EventKey = eventKey.length() > 80 ? eventKey.substring(0, 80) : eventKey;
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>{ eventRecord });
    }

    private static BillingControl_DataProvider.BillingFilterDTO dateBoundFilter(
        String operatorValue,
        String datetimeValue
    ) {
        BillingControl_DataProvider.BillingFilterDTO filterRecord =
            new BillingControl_DataProvider.BillingFilterDTO();
        filterRecord.objectApiName = 'ServiceAppointment';
        filterRecord.fieldApiName = 'ActualEndTime';
        filterRecord.operator = operatorValue;
        filterRecord.value = datetimeValue;
        return filterRecord;
    }

    public static MetricsWrapper getMetrics(BillingControl_DataProvider.BillingFilterContextDTO filterContext) {
        return load(filterContext).metrics;
    }

    public static List<OpportunityRow> getOpportunities(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return load(filterContext).opportunities;
    }

    public static List<SectionWrapper> getSections(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return load(filterContext).sections;
    }

    private static OpportunityRow buildOpportunityRow(
        Opportunity opportunityRecord,
        List<ServiceAppointment> relatedAppointments,
        Map<Id, Id> workOrderIdByAppointmentId,
        Map<Id, WorkOrder> workOrderById,
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId,
        Set<Id> billedAppointmentIds,
        Map<Id, String> billedInvoiceNumberByAppointmentId,
        Set<Id> flaggedForReviewAppointmentIds,
        BillingControl_OpportunityFinancials.Snapshot snapshot,
        List<Invoice__c> invoices,
        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId,
        Boolean hasDepositInvoice
    ) {
        List<ServiceAppointment> appointments = relatedAppointments == null
            ? new List<ServiceAppointment>()
            : relatedAppointments;
        Decimal invoicedTotal = snapshot == null ? 0 : snapshot.invoicedTotal;
        Decimal paidTotal = snapshot == null ? 0 : snapshot.paidTotal;
        Decimal amountQuoted = opportunityRecord.Amount;
        Decimal remaining = amountQuoted == null ? null : amountQuoted - invoicedTotal;

        Integer completedCount = 0;
        Integer billedCount = 0;
        Integer attributedCompleted = 0;
        Integer attributedUnbilled = 0;
        Boolean hasUnattributedOnMultiOppWorkOrder = false;
        Boolean reviewFlag = false;
        Map<Id, WorkOrderEvidence> evidenceByWorkOrderId = new Map<Id, WorkOrderEvidence>();

        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord.Status != STATUS_COMPLETED) {
                continue;
            }
            completedCount++;
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            WorkOrder workOrderRecord = workOrderId == null ? null : workOrderById.get(workOrderId);
            List<Opportunity_WorkOrder__c> junctions = junctionsByWorkOrderId.get(workOrderId);
            Integer junctionCount = countJunctionOpportunities(junctions);
            Id attributedId = BillingControl_Attribution.resolveAttributedOpportunityId(
                appointmentRecord,
                junctions
            );
            Boolean unattributed = attributedId == null;
            if (unattributed && junctionCount > 1) {
                hasUnattributedOnMultiOppWorkOrder = true;
            }
            Boolean billed = billedAppointmentIds.contains(appointmentRecord.Id);
            if (billed) {
                billedCount++;
            }
            if (!unattributed) {
                attributedCompleted++;
                if (!billed) {
                    attributedUnbilled++;
                }
            }
            Boolean appointmentReview = isReviewToken(appointmentRecord.Invoice_Number__c)
                || String.isNotBlank(appointmentRecord.Description)
                || String.isNotBlank(appointmentRecord.ServiceNote)
                || String.isNotBlank((String) appointmentRecord.get('Internal_Service_Note__c'));
            if (appointmentReview) {
                reviewFlag = true;
            }

            if (workOrderId == null) {
                continue;
            }
            if (!evidenceByWorkOrderId.containsKey(workOrderId)) {
                WorkOrderEvidence workOrderEvidence = new WorkOrderEvidence();
                workOrderEvidence.workOrderId = workOrderId;
                workOrderEvidence.workOrderNumber = workOrderRecord == null ? null : workOrderRecord.WorkOrderNumber;
                workOrderEvidence.status = workOrderRecord == null ? null : workOrderRecord.Status;
                workOrderEvidence.description = workOrderRecord == null ? null : workOrderRecord.Description;
                workOrderEvidence.serviceNote = workOrderRecord == null
                    ? null
                    : (String) workOrderRecord.get('Service_Note__c');
                workOrderEvidence.internalServiceNote = workOrderRecord == null
                    ? null
                    : (String) workOrderRecord.get('Internal_Service_Note__c');
                workOrderEvidence.invoiceNumberHint = workOrderRecord == null ? null : workOrderRecord.Invoice_Number__c;
                workOrderEvidence.legacyDepositPayments = workOrderRecord == null
                    ? null
                    : workOrderRecord.Deposit_Payments__c;
                workOrderEvidence.legacyDepositAmount = workOrderRecord == null
                    ? null
                    : workOrderRecord.Deposit_Amount__c;
                Work_Order_Ledger__c ledgerRecord = ledgerByWorkOrderId.get(workOrderId);
                workOrderEvidence.ledgerId = ledgerRecord == null ? null : ledgerRecord.Id;
                workOrderEvidence.appointments = new List<AppointmentEvidence>();
                evidenceByWorkOrderId.put(workOrderId, workOrderEvidence);
            }
            AppointmentEvidence appointmentEvidence = new AppointmentEvidence();
            appointmentEvidence.serviceAppointmentId = appointmentRecord.Id;
            appointmentEvidence.serviceAppointmentNumber = appointmentRecord.AppointmentNumber;
            appointmentEvidence.status = appointmentRecord.Status;
            appointmentEvidence.actualEndTime = appointmentRecord.ActualEndTime;
            appointmentEvidence.technicianName = appointmentRecord.Owner == null ? null : appointmentRecord.Owner.Name;
            appointmentEvidence.description = appointmentRecord.Description;
            appointmentEvidence.serviceNote = appointmentRecord.ServiceNote;
            appointmentEvidence.internalServiceNote =
                (String) appointmentRecord.get('Internal_Service_Note__c');
            appointmentEvidence.invoiceNumberHint = appointmentRecord.Invoice_Number__c;
            appointmentEvidence.woInvStatusHint = appointmentRecord.WO_Inv_Status__c;
            appointmentEvidence.billed = billed;
            appointmentEvidence.billedInvoiceNumber = billedInvoiceNumberByAppointmentId.get(appointmentRecord.Id);
            appointmentEvidence.unattributed = unattributed;
            appointmentEvidence.opportunityId = appointmentRecord.Opportunity__c;
            appointmentEvidence.opportunityName = appointmentRecord.Opportunity__r == null
                ? null
                : appointmentRecord.Opportunity__r.Name;
            appointmentEvidence.operationalUnassigned = appointmentRecord.Opportunity__c == null;
            appointmentEvidence.reviewFlag = appointmentReview;
            appointmentEvidence.flaggedForReview =
                flaggedForReviewAppointmentIds != null
                && flaggedForReviewAppointmentIds.contains(appointmentRecord.Id);
            evidenceByWorkOrderId.get(workOrderId).appointments.add(appointmentEvidence);
        }

        List<String> reasons = new List<String>();
        Boolean depositRequired = opportunityRecord.Deposit_Required__c == true
            && opportunityRecord.Deposit_Timing__c != TIMING_NOT_REQUIRED
            && String.isNotBlank(opportunityRecord.Deposit_Timing__c);
        if (depositRequired && !hasDepositInvoice) {
            reasons.add(REASON_DEPOSIT_DUE);
        }
        Boolean invoicedBelowQuoted = amountQuoted != null && amountQuoted > 0 && invoicedTotal < amountQuoted;
        if (attributedUnbilled > 0 && invoicedBelowQuoted) {
            reasons.add(REASON_BALANCE_READY);
        }
        if (attributedCompleted > 0 && attributedUnbilled == 0 && invoicedBelowQuoted) {
            reasons.add(REASON_UNDER_INVOICED);
        }
        if (reviewFlag) {
            reasons.add(REASON_REVIEW);
        }
        if (hasUnattributedOnMultiOppWorkOrder) {
            reasons.add(REASON_BLOCKED_ATTRIBUTION);
        }
        if (amountQuoted == null || amountQuoted <= 0) {
            reasons.add(REASON_BLOCKED_NO_AMOUNT);
        }

        OpportunityRow row = new OpportunityRow();
        row.opportunityId = opportunityRecord.Id;
        row.quoteNumber = opportunityRecord.Quote_Number__c;
        row.opportunityName = opportunityRecord.Name;
        row.accountId = opportunityRecord.AccountId;
        row.accountName = opportunityRecord.Account == null ? null : opportunityRecord.Account.Name;
        row.ownerId = opportunityRecord.OwnerId;
        row.salespersonName = opportunityRecord.Owner == null ? null : opportunityRecord.Owner.Name;
        row.amountQuoted = amountQuoted;
        row.invoicedTotal = invoicedTotal;
        row.paidTotal = paidTotal;
        row.remaining = remaining;
        row.outstanding = invoicedTotal - paidTotal;
        row.billingStatus = opportunityRecord.Billing_Status__c;
        row.readinessReasons = reasons;
        row.invoices = toChips(invoices);
        row.completedEvidenceCount = completedCount;
        row.billedEvidenceCount = billedCount;
        row.showReviewBanner = reasons.contains(REASON_REVIEW);
        row.workOrders = evidenceByWorkOrderId.values();
        return row;
    }

    private static List<SectionWrapper> buildSections(List<OpportunityRow> rows) {
        List<SectionWrapper> sections = new List<SectionWrapper>{
            newSection(SECTION_DEPOSITS_DUE, 'Deposits Due', REASON_DEPOSIT_DUE, rows),
            newSection(SECTION_BALANCES_READY, 'Balances Ready', REASON_BALANCE_READY, rows),
            newSection(SECTION_UNDER_INVOICED, 'Under-Invoiced', REASON_UNDER_INVOICED, rows),
            newSection(SECTION_NEEDS_REVIEW, 'Needs Review', REASON_REVIEW, rows),
            newSection(SECTION_BLOCKED, 'Blocked', null, rows)
        };
        return sections;
    }

    private static List<SectionWrapper> emptySections() {
        return buildSections(new List<OpportunityRow>());
    }

    private static SectionWrapper newSection(
        String categoryKey,
        String categoryLabel,
        String reason,
        List<OpportunityRow> allRows
    ) {
        SectionWrapper section = new SectionWrapper();
        section.categoryKey = categoryKey;
        section.categoryLabel = categoryLabel;
        section.rows = new List<OpportunityRow>();
        Decimal totalAmount = 0;
        for (OpportunityRow row : allRows) {
            if (reason == null) {
                if (
                    row.readinessReasons.contains(REASON_BLOCKED_ATTRIBUTION)
                    || row.readinessReasons.contains(REASON_BLOCKED_NO_AMOUNT)
                ) {
                    section.rows.add(row);
                    totalAmount += row.amountQuoted == null ? 0 : row.amountQuoted;
                }
            } else if (row.readinessReasons.contains(reason)) {
                section.rows.add(row);
                totalAmount += amountForReason(row, reason);
            }
        }
        section.opportunityCount = section.rows.size();
        section.totalAmount = totalAmount;
        return section;
    }

    private static Decimal amountForReason(OpportunityRow row, String reason) {
        if (reason == REASON_DEPOSIT_DUE) {
            return row.remaining == null ? 0 : row.remaining;
        }
        if (row.remaining != null && row.remaining > 0) {
            return row.remaining;
        }
        return row.amountQuoted == null ? 0 : row.amountQuoted;
    }

    private static MetricsWrapper buildMetrics(List<SectionWrapper> sections, Integer uniqueCount) {
        MetricsWrapper metrics = new MetricsWrapper();
        metrics.readyToBill = uniqueCount;
        for (SectionWrapper section : sections) {
            if (section.categoryKey == SECTION_DEPOSITS_DUE) {
                metrics.depositsDueCount = section.opportunityCount;
                metrics.depositsDueAmount = section.totalAmount;
            } else if (section.categoryKey == SECTION_BALANCES_READY) {
                metrics.balancesReadyCount = section.opportunityCount;
                metrics.balancesReadyAmount = section.totalAmount;
            } else if (section.categoryKey == SECTION_UNDER_INVOICED) {
                metrics.underInvoicedCount = section.opportunityCount;
                metrics.underInvoicedAmount = section.totalAmount;
            } else if (section.categoryKey == SECTION_NEEDS_REVIEW) {
                metrics.needsReviewCount = section.opportunityCount;
            } else if (section.categoryKey == SECTION_BLOCKED) {
                metrics.blockedCount = section.opportunityCount;
            }
        }
        return metrics;
    }

    private static List<ServiceAppointment> queryCompletedAppointments(Datetime rangeStart, Datetime rangeEnd) {
        String soql =
            'SELECT Id, AppointmentNumber, Status, Description, ServiceNote, ActualEndTime, '
            + 'Invoice_Number__c, WO_Inv_Status__c, Opportunity__c, Opportunity__r.Name, ParentRecordId, Owner.Name';
        if (hasField(ServiceAppointment.SObjectType, 'Internal_Service_Note__c')) {
            soql += ', Internal_Service_Note__c';
        }
        soql +=
            ' FROM ServiceAppointment WHERE Status = :STATUS_COMPLETED '
            + 'AND ActualEndTime >= :rangeStart AND ActualEndTime <= :rangeEnd '
            + 'ORDER BY ActualEndTime DESC NULLS LAST, AppointmentNumber ASC NULLS LAST LIMIT 2000';
        return Database.query(soql);
    }

    private static Map<Id, WorkOrder> queryWorkOrders(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new Map<Id, WorkOrder>();
        }
        String soql =
            'SELECT Id, WorkOrderNumber, Status, Description, Invoice_Number__c, '
            + 'Deposit_Payments__c, Deposit_Amount__c, Parent_Account__r.Name';
        if (hasField(WorkOrder.SObjectType, 'Service_Note__c')) {
            soql += ', Service_Note__c';
        }
        if (hasField(WorkOrder.SObjectType, 'Internal_Service_Note__c')) {
            soql += ', Internal_Service_Note__c';
        }
        soql += ' FROM WorkOrder WHERE Id IN :workOrderIds';
        return new Map<Id, WorkOrder>((List<WorkOrder>) Database.query(soql));
    }

    private static Boolean hasField(Schema.SObjectType objectType, String fieldApiName) {
        return objectType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static Map<Id, Opportunity> queryOpportunities(Set<Id> opportunityIds, Id ownerId) {
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return opportunityById;
        }
        String soql =
            'SELECT Id, Name, AccountId, Account.Name, OwnerId, Owner.Name, Amount, Quote_Number__c, '
            + 'Billing_Status__c, Deposit_Required__c, Deposit_Percent__c, Deposit_Amount_Required__c, Deposit_Timing__c '
            + 'FROM Opportunity WHERE Id IN :opportunityIds';
        if (ownerId != null) {
            soql += ' AND OwnerId = :ownerId';
        }
        for (Opportunity opportunityRecord : Database.query(soql)) {
            opportunityById.put(opportunityRecord.Id, opportunityRecord);
        }
        return opportunityById;
    }

    private static Set<Id> queryDepositDueOpportunityIds(Id ownerId) {
        Set<Id> opportunityIds = new Set<Id>();
        String timingNotRequired = TIMING_NOT_REQUIRED;
        String soql =
            'SELECT Id FROM Opportunity WHERE Deposit_Required__c = true '
            + 'AND Deposit_Timing__c != null AND Deposit_Timing__c != :timingNotRequired';
        if (ownerId != null) {
            soql += ' AND OwnerId = :ownerId';
        }
        soql += ' LIMIT 500';
        for (Opportunity opportunityRecord : Database.query(soql)) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private static Map<Id, List<Invoice__c>> queryInvoices(Set<Id> opportunityIds) {
        Map<Id, List<Invoice__c>> invoicesByOpportunityId = new Map<Id, List<Invoice__c>>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return invoicesByOpportunityId;
        }
        for (Invoice__c invoiceRecord : [
            SELECT Id, Opportunity__c, Invoice_Number__c, Invoice_Type__c, Status__c
            FROM Invoice__c
            WHERE Opportunity__c IN :opportunityIds
            AND Status__c != :STATUS_VOID
            ORDER BY Invoice_Date__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            if (!invoicesByOpportunityId.containsKey(invoiceRecord.Opportunity__c)) {
                invoicesByOpportunityId.put(invoiceRecord.Opportunity__c, new List<Invoice__c>());
            }
            invoicesByOpportunityId.get(invoiceRecord.Opportunity__c).add(invoiceRecord);
        }
        return invoicesByOpportunityId;
    }

    private static Map<Id, Work_Order_Ledger__c> queryLedgers(Set<Id> workOrderIds) {
        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId = new Map<Id, Work_Order_Ledger__c>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return ledgerByWorkOrderId;
        }
        for (Work_Order_Ledger__c ledgerRecord : [
            SELECT Id, Work_Order__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c IN :workOrderIds
        ]) {
            ledgerByWorkOrderId.put(ledgerRecord.Work_Order__c, ledgerRecord);
        }
        return ledgerByWorkOrderId;
    }

    private static Map<Id, String> billedInvoiceNumbers(Set<Id> billedAppointmentIds) {
        Map<Id, String> invoiceNumberByAppointmentId = new Map<Id, String>();
        if (billedAppointmentIds == null || billedAppointmentIds.isEmpty()) {
            return invoiceNumberByAppointmentId;
        }
        for (Invoice_Line__c invoiceLineRecord : [
            SELECT Service_Appointment__c, Invoice__r.Invoice_Number__c
            FROM Invoice_Line__c
            WHERE Service_Appointment__c IN :billedAppointmentIds
            AND Invoice__r.Status__c != :STATUS_VOID
            ORDER BY CreatedDate DESC
        ]) {
            if (!invoiceNumberByAppointmentId.containsKey(invoiceLineRecord.Service_Appointment__c)) {
                invoiceNumberByAppointmentId.put(
                    invoiceLineRecord.Service_Appointment__c,
                    invoiceLineRecord.Invoice__r.Invoice_Number__c
                );
            }
        }
        return invoiceNumberByAppointmentId;
    }

    private static Set<Id> flaggedAccountingNoteAppointmentIds(Set<Id> appointmentIds) {
        Set<Id> flaggedIds = new Set<Id>();
        if (appointmentIds == null || appointmentIds.isEmpty()) {
            return flaggedIds;
        }
        for (Work_Order_Ledger_Entry__c entryRecord : [
            SELECT Service_Appointment__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = 'ACCOUNTING_NOTE'
            AND Service_Appointment__c IN :appointmentIds
        ]) {
            if (entryRecord.Service_Appointment__c != null) {
                flaggedIds.add(entryRecord.Service_Appointment__c);
            }
        }
        return flaggedIds;
    }

    private static Set<Id> opportunitiesWithDepositInvoice(Map<Id, List<Invoice__c>> invoicesByOpportunityId) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Id opportunityId : invoicesByOpportunityId.keySet()) {
            for (Invoice__c invoiceRecord : invoicesByOpportunityId.get(opportunityId)) {
                if (invoiceRecord.Invoice_Type__c == TYPE_DEPOSIT) {
                    opportunityIds.add(opportunityId);
                    break;
                }
            }
        }
        return opportunityIds;
    }

    private static List<InvoiceChip> toChips(List<Invoice__c> invoices) {
        List<InvoiceChip> chips = new List<InvoiceChip>();
        if (invoices == null) {
            return chips;
        }
        for (Invoice__c invoiceRecord : invoices) {
            InvoiceChip chip = new InvoiceChip();
            chip.invoiceNumber = invoiceRecord.Invoice_Number__c;
            chip.invoiceType = invoiceRecord.Invoice_Type__c;
            chip.status = invoiceRecord.Status__c;
            chips.add(chip);
        }
        return chips;
    }

    private static Integer countJunctionOpportunities(List<Opportunity_WorkOrder__c> junctions) {
        if (junctions == null) {
            return 0;
        }
        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : junctions) {
            if (junctionRecord.Opportunity__c != null) {
                opportunityIds.add(junctionRecord.Opportunity__c);
            }
        }
        return opportunityIds.size();
    }

    private static Boolean isReviewToken(String invoiceNumberText) {
        return BillingControl_InvoiceNumberParser.parse(invoiceNumberText).isEmpty()
            && String.isNotBlank(invoiceNumberText);
    }

    private static Id extractOwnerId(BillingControl_DataProvider.BillingFilterContextDTO filterContext) {
        if (filterContext == null || filterContext.filters == null) {
            return null;
        }
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            if (
                filterRecord != null
                && BillingControl_Invoicing.normalizeFilterValue(filterRecord.objectApiName) == 'OPPORTUNITY'
                && BillingControl_Invoicing.normalizeFilterValue(filterRecord.fieldApiName) == 'OWNERID'
            ) {
                return String.isBlank(filterRecord.value) ? null : (Id) filterRecord.value;
            }
        }
        return null;
    }

    private static Datetime extractActualEndBound(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean isStartBound
    ) {
        if (filterContext == null || filterContext.filters == null) {
            return null;
        }
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = BillingControl_Invoicing.normalizeFilterValue(filterRecord.objectApiName)
                + '.'
                + BillingControl_Invoicing.normalizeFilterValue(filterRecord.fieldApiName);
            if (fieldKey != 'SERVICEAPPOINTMENT.ACTUALENDTIME') {
                continue;
            }
            String operatorValue = BillingControl_Invoicing.normalizeFilterValue(filterRecord.operator);
            Boolean matchesStart = isStartBound
                && (operatorValue == 'GREATER OR EQUAL' || operatorValue == 'GREATER THAN');
            Boolean matchesEnd = !isStartBound
                && (operatorValue == 'LESS OR EQUAL' || operatorValue == 'LESS THAN');
            if (!matchesStart && !matchesEnd) {
                continue;
            }
            try {
                return Datetime.valueOf(filterRecord.value);
            } catch (Exception ex) {
                return null;
            }
        }
        return null;
    }

    private class OpportunityNameComparator implements Comparator<OpportunityRow> {
        public Integer compare(OpportunityRow left, OpportunityRow right) {
            String leftName = left == null || left.opportunityName == null ? '' : left.opportunityName;
            String rightName = right == null || right.opportunityName == null ? '' : right.opportunityName;
            return leftName.toLowerCase().compareTo(rightName.toLowerCase());
        }
    }
}
