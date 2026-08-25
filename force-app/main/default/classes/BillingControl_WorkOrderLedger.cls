/**
 * Billing Control Center Work Order Ledger tab read model.
 * One compact row per Work_Order_Ledger__c. Ledger Entry history loads only on View Ledger.
 */
public with sharing class BillingControl_WorkOrderLedger {
    private static final String BUCKET_READY_TO_SCHEDULE = 'READY_TO_SCHEDULE';
    private static final String BUCKET_SCHEDULED_APPOINTMENTS = 'SCHEDULED_APPOINTMENTS';
    private static final String BUCKET_IN_PROGRESS = 'IN_PROGRESS';

    private static final String SA_STATUS_COMPLETED = 'Completed';
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer LEDGER_QUERY_LIMIT = 10000;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';
    private static final Set<String> CANCELLED_SA_STATUSES = new Set<String>{ 'Canceled', 'Cancelled' };

    @TestVisible
    private static Integer queryLimitOverride;

    private static final List<String> BUCKET_QUERY_ORDER = new List<String>{
        BUCKET_READY_TO_SCHEDULE,
        BUCKET_SCHEDULED_APPOINTMENTS,
        BUCKET_IN_PROGRESS
    };

    private static final Map<String, String> BUCKET_LABELS = new Map<String, String>{
        BUCKET_READY_TO_SCHEDULE => 'Ready to Schedule',
        BUCKET_SCHEDULED_APPOINTMENTS => 'Scheduled Appointments',
        BUCKET_IN_PROGRESS => 'In Progress'
    };

    private static final Map<String, String> EVENT_LABELS = new Map<String, String>{
        WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED => 'Work Order Created',
        WorkOrderLedgerService.EVENT_WORK_ORDER_STATUS_CHANGED => 'Work Order Status Changed',
        WorkOrderLedgerService.EVENT_SA_CREATED => 'Service Appointment Created',
        WorkOrderLedgerService.EVENT_SA_SCHEDULED => 'Service Appointment Scheduled',
        WorkOrderLedgerService.EVENT_SA_COMPLETED => 'Service Appointment Completed',
        WorkOrderLedgerService.EVENT_SA_CANCELLED => 'Service Appointment Cancelled',
        WorkOrderLedgerService.EVENT_SA_MOVED => 'Service Appointment Moved',
        WorkOrderLedgerService.EVENT_OPPORTUNITY_LINKED => 'Opportunity Linked',
        WorkOrderLedgerService.EVENT_OPPORTUNITY_UNLINKED => 'Opportunity Unlinked',
        WorkOrderLedgerService.EVENT_DEPOSIT_RECORDED => 'Deposit Recorded',
        WorkOrderLedgerService.EVENT_DEPOSIT_CHANGED => 'Deposit Changed',
        WorkOrderLedgerService.EVENT_DEPOSIT_STATUS => 'Deposit Status',
        WorkOrderLedgerService.EVENT_PARTS_STATUS => 'Parts Status',
        WorkOrderLedgerService.EVENT_INVOICE_NUMBER_CHANGED => 'Invoice Number Changed'
    };

    public class RuntimeBundle {
        public BillingControl_Orders.KpiWrapper kpis;
        public List<BillingControl_Orders.BucketSectionWrapper> sections;
    }


    public class LedgerDetailWrapper {
        @AuraEnabled public Id ledgerId;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String workOrderStatus;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountOwnerName;
        @AuraEnabled public String reconciliationStatus;
        @AuraEnabled public Boolean attentionRequired;
        @AuraEnabled public String attentionReason;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public String depositStatus;
        @AuraEnabled public String partsStatus;
        @AuraEnabled public String workOrderInvoiceNumber;
        @AuraEnabled public List<LedgerOpportunityWrapper> opportunities;
        @AuraEnabled public List<LedgerAppointmentWrapper> appointments;
        @AuraEnabled public List<BillingControl_Orders.TimelineEntryWrapper> timeline;
    }

    public class LedgerOpportunityWrapper {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String stageName;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
    }

    public class LedgerAppointmentWrapper {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String appointmentNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime actualStartTime;
        @AuraEnabled public Datetime actualEndTime;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String woInvStatus;
    }

    public class DateTimeRange {
        public Datetime rangeStart;
        public Datetime rangeEnd;

        public Boolean isComplete() {
            return rangeStart != null && rangeEnd != null;
        }
    }

    public class ValidationCountsWrapper {
        @AuraEnabled public Integer openWorkOrderCount;
        @AuraEnabled public Integer ledgerCount;
        @AuraEnabled public Integer unscheduledCount;
        @AuraEnabled public Integer scheduledTodayCount;
        @AuraEnabled public Integer completedThisWeekCount;
        @AuraEnabled public Integer noOpportunityCount;
        @AuraEnabled public Integer noServiceAppointmentCount;
        @AuraEnabled public Integer multipleOpportunityCount;
        @AuraEnabled public Integer openWorkOrdersWithoutLedger;
        @AuraEnabled public Integer openLedgerCount;
        @AuraEnabled public Integer listWindowLimit;
        @AuraEnabled public Boolean listTruncated;
    }

    public static BillingControl_Orders.KpiWrapper getKpis() {
        return getRuntime(null, null).kpis;
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Orders.KpiWrapper getKpis(Long refreshToken) {
        return getRuntime(refreshToken, null).kpis;
    }

    public static BillingControl_Orders.KpiWrapper getKpis(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return getRuntime(refreshToken, filterContext).kpis;
    }

    public static List<BillingControl_Orders.BucketSectionWrapper> getBucketWorkOrders() {
        return getRuntime(null, null).sections;
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Orders.BucketSectionWrapper> getBucketWorkOrders(Long refreshToken) {
        return getRuntime(refreshToken, null).sections;
    }

    public static List<BillingControl_Orders.BucketSectionWrapper> getBucketWorkOrders(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return getRuntime(refreshToken, filterContext).sections;
    }

    public static RuntimeBundle getRuntime(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        return getRuntime(refreshToken, filterContext, null);
    }

    public static RuntimeBundle getRuntime(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        BillingControl_DataProvider.DateRangeDTO dateWindow
    ) {
        DateTimeRange dateRange = toDateTimeRange(dateWindow);
        Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> rowsByBucket =
            loadRowsByBucket(filterContext, dateRange);
        RuntimeBundle bundle = new RuntimeBundle();
        bundle.kpis = buildKpis(rowsByBucket);
        bundle.sections = buildSections(rowsByBucket, filterContext);
        return bundle;
    }

    @AuraEnabled
    public static LedgerDetailWrapper getWorkOrderLedgerDetail(Id ledgerId) {
        LedgerDetailWrapper detail = new LedgerDetailWrapper();
        detail.opportunities = new List<LedgerOpportunityWrapper>();
        detail.appointments = new List<LedgerAppointmentWrapper>();
        detail.timeline = new List<BillingControl_Orders.TimelineEntryWrapper>();
        if (ledgerId == null) {
            return detail;
        }

        List<Work_Order_Ledger__c> ledgers = [
            SELECT Id,
                Work_Order__c,
                Account__c,
                Account__r.Name,
                Reconciliation_Status__c,
                Attention_Required__c,
                Attention_Reason__c,
                Work_Order__r.WorkOrderNumber,
                Work_Order__r.Subject,
                Work_Order__r.Status,
                Work_Order__r.AccountId,
                Work_Order__r.Account.Owner.Name,
                Work_Order__r.Deposit_Amount__c,
                Work_Order__r.Deposit_Payments__c,
                Work_Order__r.Parts_Hardware__c,
                Work_Order__r.Invoice_Number__c
            FROM Work_Order_Ledger__c
            WHERE Id = :ledgerId
            LIMIT 1
        ];
        if (ledgers.isEmpty()) {
            return detail;
        }

        Work_Order_Ledger__c ledgerRecord = ledgers[0];
        detail.ledgerId = ledgerRecord.Id;
        detail.workOrderId = ledgerRecord.Work_Order__c;
        detail.workOrderNumber = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.WorkOrderNumber;
        detail.subject = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Subject;
        detail.workOrderStatus = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Status;
        detail.accountId = ledgerRecord.Account__c != null
            ? ledgerRecord.Account__c
            : (ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.AccountId);
        detail.accountName = ledgerRecord.Account__r == null ? null : ledgerRecord.Account__r.Name;
        detail.accountOwnerName =
            ledgerRecord.Work_Order__r == null
            || ledgerRecord.Work_Order__r.Account == null
            || ledgerRecord.Work_Order__r.Account.Owner == null
                ? null
                : ledgerRecord.Work_Order__r.Account.Owner.Name;
        detail.reconciliationStatus = ledgerRecord.Reconciliation_Status__c;
        detail.attentionRequired = ledgerRecord.Attention_Required__c == true;
        detail.attentionReason = ledgerRecord.Attention_Reason__c;
        detail.depositAmount = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Deposit_Amount__c;
        detail.depositStatus = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Deposit_Payments__c;
        detail.partsStatus = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Parts_Hardware__c;
        detail.workOrderInvoiceNumber = ledgerRecord.Work_Order__r == null
            ? null
            : ledgerRecord.Work_Order__r.Invoice_Number__c;

        if (ledgerRecord.Work_Order__c != null) {
            Set<Id> workOrderIds = new Set<Id>{ ledgerRecord.Work_Order__c };
            List<Opportunity_WorkOrder__c> junctions = queryJunctionsByWorkOrderId(workOrderIds).get(ledgerRecord.Work_Order__c);
            if (junctions == null) {
                junctions = new List<Opportunity_WorkOrder__c>();
            }
            for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                if (junctionRecord.Opportunity__c == null) {
                    continue;
                }
                LedgerOpportunityWrapper opportunityRow = new LedgerOpportunityWrapper();
                opportunityRow.opportunityId = junctionRecord.Opportunity__c;
                opportunityRow.name = junctionRecord.Opportunity__r == null ? null : junctionRecord.Opportunity__r.Name;
                opportunityRow.amount = junctionRecord.Opportunity__r == null ? null : junctionRecord.Opportunity__r.Amount;
                opportunityRow.stageName = junctionRecord.Opportunity__r == null ? null : junctionRecord.Opportunity__r.StageName;
                opportunityRow.billingStatus = junctionRecord.Opportunity__r == null
                    ? null
                    : (String) junctionRecord.Opportunity__r.get('Billing_Status__c');
                opportunityRow.ownerId = junctionRecord.Opportunity__r == null
                    ? null
                    : junctionRecord.Opportunity__r.OwnerId;
                opportunityRow.ownerName = junctionRecord.Opportunity__r == null
                    || junctionRecord.Opportunity__r.Owner == null
                    ? null
                    : junctionRecord.Opportunity__r.Owner.Name;
                detail.opportunities.add(opportunityRow);
            }

            Map<Id, String> opportunityNameById = new Map<Id, String>();
            for (LedgerOpportunityWrapper opportunityRow : detail.opportunities) {
                opportunityNameById.put(opportunityRow.opportunityId, opportunityRow.name);
            }
            List<ServiceAppointment> appointments = queryDetailAppointments(workOrderIds).get(ledgerRecord.Work_Order__c);
            if (appointments == null) {
                appointments = new List<ServiceAppointment>();
            }
            for (ServiceAppointment appointmentRecord : appointments) {
                LedgerAppointmentWrapper appointmentRow = new LedgerAppointmentWrapper();
                appointmentRow.serviceAppointmentId = appointmentRecord.Id;
                appointmentRow.appointmentNumber = appointmentRecord.AppointmentNumber;
                appointmentRow.status = appointmentRecord.Status;
                appointmentRow.schedStartTime = appointmentRecord.SchedStartTime;
                appointmentRow.actualStartTime = appointmentRecord.ActualStartTime;
                appointmentRow.actualEndTime = appointmentRecord.ActualEndTime;
                appointmentRow.opportunityId = appointmentRecord.Opportunity__c;
                appointmentRow.opportunityName = opportunityNameById.get(appointmentRecord.Opportunity__c);
                if (appointmentRow.opportunityName == null && appointmentRecord.Opportunity__c != null && appointmentRecord.Opportunity__r != null) {
                    appointmentRow.opportunityName = appointmentRecord.Opportunity__r.Name;
                }
                appointmentRow.invoiceNumber = appointmentRecord.Invoice_Number__c;
                appointmentRow.woInvStatus = (String) appointmentRecord.get('WO_Inv_Status__c');
                detail.appointments.add(appointmentRow);
            }
        }

        for (Work_Order_Ledger_Entry__c entryRecord : [
            SELECT Event_Datetime__c,
                Event_Type__c,
                Description__c,
                Old_Value__c,
                New_Value__c,
                Changed_By__c,
                Changed_By__r.Name,
                Source_Object__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Work_Order_Ledger__c = :ledgerId
            ORDER BY Event_Datetime__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 500
        ]) {
            BillingControl_Orders.TimelineEntryWrapper wrapper = new BillingControl_Orders.TimelineEntryWrapper();
            wrapper.eventDatetime = entryRecord.Event_Datetime__c;
            wrapper.eventType = entryRecord.Event_Type__c;
            wrapper.eventLabel = EVENT_LABELS.containsKey(entryRecord.Event_Type__c)
                ? EVENT_LABELS.get(entryRecord.Event_Type__c)
                : entryRecord.Event_Type__c;
            wrapper.description = entryRecord.Description__c;
            wrapper.oldValue = entryRecord.Old_Value__c;
            wrapper.newValue = entryRecord.New_Value__c;
            wrapper.changedByName = entryRecord.Changed_By__r == null ? null : entryRecord.Changed_By__r.Name;
            wrapper.sourceObject = entryRecord.Source_Object__c;
            detail.timeline.add(wrapper);
        }
        return detail;
    }

    @AuraEnabled(cacheable=true)
    public static ValidationCountsWrapper getValidationCounts() {
        ValidationCountsWrapper result = new ValidationCountsWrapper();
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        if (closedStatuses.isEmpty()) {
            result.openWorkOrderCount = [SELECT COUNT() FROM WorkOrder];
        } else {
            result.openWorkOrderCount = [SELECT COUNT() FROM WorkOrder WHERE Status NOT IN :closedStatuses];
        }
        result.ledgerCount = [SELECT COUNT() FROM Work_Order_Ledger__c];
        Integer ledgersForOpenWorkOrders;
        if (closedStatuses.isEmpty()) {
            ledgersForOpenWorkOrders = [
                SELECT COUNT()
                FROM Work_Order_Ledger__c
                WHERE Work_Order__c != NULL
            ];
        } else {
            ledgersForOpenWorkOrders = [
                SELECT COUNT()
                FROM Work_Order_Ledger__c
                WHERE Work_Order__c != NULL
                AND Work_Order__r.Status NOT IN :closedStatuses
            ];
        }
        result.openWorkOrdersWithoutLedger = result.openWorkOrderCount - ledgersForOpenWorkOrders;
        if (result.openWorkOrdersWithoutLedger < 0) {
            result.openWorkOrdersWithoutLedger = 0;
        }
        result.openLedgerCount = ledgersForOpenWorkOrders;
        result.listWindowLimit = LEDGER_QUERY_LIMIT;
        result.listTruncated = ledgersForOpenWorkOrders > LEDGER_QUERY_LIMIT;

        RuntimeBundle bundle = getRuntime(null, null);
        result.unscheduledCount = bundle.kpis.unscheduledCount;
        result.scheduledTodayCount = bundle.kpis.scheduledCount;
        result.completedThisWeekCount = 0;
        result.noOpportunityCount = 0;
        result.noServiceAppointmentCount = 0;
        result.multipleOpportunityCount = 0;
        return result;
    }

    public static Map<Id, Id> getLedgerIdsByWorkOrderId(Set<Id> workOrderIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return result;
        }
        for (Work_Order_Ledger__c ledgerRecord : [
            SELECT Id, Work_Order__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c IN :workOrderIds
        ]) {
            if (ledgerRecord.Work_Order__c != null && !result.containsKey(ledgerRecord.Work_Order__c)) {
                result.put(ledgerRecord.Work_Order__c, ledgerRecord.Id);
            }
        }
        return result;
    }

    public static Map<Id, Id> getLedgerIdsByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return result;
        }

        Map<Id, Id> preferredWorkOrderByOpportunity = new Map<Id, Id>();
        Map<Id, Id> fallbackWorkOrderByOpportunity = new Map<Id, Id>();
        Set<Id> workOrderIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Opportunity__c, Work_Order__c, Work_Order__r.Invoice_Number__c
            FROM Opportunity_WorkOrder__c
            WHERE Opportunity__c IN :opportunityIds
            AND Work_Order__c != NULL
            ORDER BY LastModifiedDate DESC
        ]) {
            workOrderIds.add(junctionRecord.Work_Order__c);
            if (!fallbackWorkOrderByOpportunity.containsKey(junctionRecord.Opportunity__c)) {
                fallbackWorkOrderByOpportunity.put(junctionRecord.Opportunity__c, junctionRecord.Work_Order__c);
            }
            if (
                junctionRecord.Work_Order__r != null
                && String.isNotBlank(junctionRecord.Work_Order__r.Invoice_Number__c)
                && !preferredWorkOrderByOpportunity.containsKey(junctionRecord.Opportunity__c)
            ) {
                preferredWorkOrderByOpportunity.put(junctionRecord.Opportunity__c, junctionRecord.Work_Order__c);
            }
        }

        Map<Id, Id> ledgerByWorkOrderId = getLedgerIdsByWorkOrderId(workOrderIds);
        Set<Id> resolvedOpportunityIds = new Set<Id>();
        resolvedOpportunityIds.addAll(fallbackWorkOrderByOpportunity.keySet());
        resolvedOpportunityIds.addAll(preferredWorkOrderByOpportunity.keySet());
        for (Id opportunityId : resolvedOpportunityIds) {
            Id workOrderId = preferredWorkOrderByOpportunity.containsKey(opportunityId)
                ? preferredWorkOrderByOpportunity.get(opportunityId)
                : fallbackWorkOrderByOpportunity.get(opportunityId);
            Id ledgerId = ledgerByWorkOrderId.get(workOrderId);
            if (ledgerId != null) {
                result.put(opportunityId, ledgerId);
            }
        }
        return result;
    }

    private static BillingControl_Orders.KpiWrapper buildKpis(
        Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> rowsByBucket
    ) {
        BillingControl_Orders.KpiWrapper result = new BillingControl_Orders.KpiWrapper();
        applyKpi(result, rowsByBucket.get(BUCKET_READY_TO_SCHEDULE), 'unscheduled');
        applyKpi(result, rowsByBucket.get(BUCKET_SCHEDULED_APPOINTMENTS), 'scheduled');
        applyKpi(result, rowsByBucket.get(BUCKET_IN_PROGRESS), 'inProgress');
        result.scheduledTodayCount = 0;
        result.scheduledTodayRevenue = 0;
        result.completedThisWeekCount = 0;
        result.completedThisWeekRevenue = 0;
        result.completedThisMonthCount = 0;
        result.completedThisMonthRevenue = 0;
        result.completedNotBilledCount = 0;
        result.completedNotBilledRevenue = 0;
        result.noOpportunityCount = 0;
        result.noOpportunityRevenue = 0;
        result.noServiceAppointmentCount = 0;
        result.noServiceAppointmentRevenue = 0;
        result.multipleOpportunitiesCount = 0;
        result.multipleOpportunitiesRevenue = 0;
        result.relatedWorkCount = 0;
        result.relatedWorkRevenue = 0;
        result.completedTodayCount = 0;
        result.completedTodayRevenue = 0;
        return result;
    }

    private static List<BillingControl_Orders.BucketSectionWrapper> buildSections(
        Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> rowsByBucket,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<BillingControl_Orders.BucketSectionWrapper> sections = new List<BillingControl_Orders.BucketSectionWrapper>();
        for (String bucketKey : BUCKET_QUERY_ORDER) {
            List<BillingControl_Orders.WorkOrderRowWrapper> rows = rowsByBucket.get(bucketKey);
            if (rows == null) {
                rows = new List<BillingControl_Orders.WorkOrderRowWrapper>();
            }
            if (rows.size() > MAX_ROWS_PER_SECTION) {
                addRuntimeWarning(filterContext, BUCKET_LABELS.get(bucketKey) + ': ' + ROW_LIMIT_WARNING_MESSAGE);
                List<BillingControl_Orders.WorkOrderRowWrapper> truncated = new List<BillingControl_Orders.WorkOrderRowWrapper>();
                for (Integer indexValue = 0; indexValue < MAX_ROWS_PER_SECTION; indexValue++) {
                    truncated.add(rows[indexValue]);
                }
                rows = truncated;
            }
            BillingControl_Orders.BucketSectionWrapper sectionRecord = new BillingControl_Orders.BucketSectionWrapper(
                bucketKey,
                BUCKET_LABELS.get(bucketKey),
                rows
            );
            Integer appointmentCount = 0;
            for (BillingControl_Orders.WorkOrderRowWrapper row : rows) {
                appointmentCount += row.serviceAppointmentCount == null ? 0 : row.serviceAppointmentCount;
            }
            sectionRecord.serviceAppointmentCount = appointmentCount;
            sections.add(sectionRecord);
        }
        return sections;
    }

    private static void applyKpi(
        BillingControl_Orders.KpiWrapper result,
        List<BillingControl_Orders.WorkOrderRowWrapper> rows,
        String prefix
    ) {
        Integer recordCount = rows == null ? 0 : rows.size();
        Decimal totalAmount = 0;
        if (rows != null) {
            for (BillingControl_Orders.WorkOrderRowWrapper row : rows) {
                Decimal rowAmount = row.visitAmount != null ? row.visitAmount : row.opportunityAmount;
                if (rowAmount != null) {
                    totalAmount += rowAmount;
                }
            }
        }
        if (prefix == 'unscheduled') {
            result.unscheduledCount = recordCount;
            result.unscheduledRevenue = totalAmount;
        } else if (prefix == 'scheduled') {
            result.scheduledCount = recordCount;
            result.scheduledRevenue = totalAmount;
        } else if (prefix == 'inProgress') {
            result.inProgressCount = recordCount;
            result.inProgressRevenue = totalAmount;
        }
    }

    private static Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> loadRowsByBucket(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        DateTimeRange dateRange
    ) {
        Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> rowsByBucket =
            new Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>>();
        for (String bucketKey : BUCKET_QUERY_ORDER) {
            rowsByBucket.put(bucketKey, new List<BillingControl_Orders.WorkOrderRowWrapper>());
        }

        Id opportunityOwnerId = extractOpportunityOwnerId(filterContext);
        OperationalBucketSets bucketSets = null;
        Set<Id> includedWorkOrderIds = null;
        if (dateRange != null && dateRange.isComplete()) {
            bucketSets = queryOperationalBucketSets(dateRange, filterContext);
            includedWorkOrderIds = new Set<Id>(bucketSets.workOrderIds);
            if (opportunityOwnerId != null) {
                includedWorkOrderIds.retainAll(resolveWorkOrderIdsByOpportunityOwner(opportunityOwnerId));
            }
            if (includedWorkOrderIds.isEmpty()) {
                return rowsByBucket;
            }
        }

        List<Work_Order_Ledger__c> ledgers = queryLedgers(filterContext, includedWorkOrderIds);
        if (ledgers.size() >= ledgerQueryLimit()) {
            addRuntimeWarning(
                filterContext,
                'Work Order Ledger list is limited to the first ' + String.valueOf(ledgerQueryLimit())
                    + ' open Work Orders. Narrow the date filter for older records.'
            );
        }
        if (ledgers.isEmpty()) {
            return rowsByBucket;
        }

        Set<Id> workOrderIds = new Set<Id>();
        for (Work_Order_Ledger__c ledgerRecord : ledgers) {
            if (ledgerRecord.Work_Order__c != null) {
                workOrderIds.add(ledgerRecord.Work_Order__c);
            }
        }

        Map<Id, List<ServiceAppointment>> appointmentsByWorkOrderId;
        Set<Id> billedWorkOrderIds = new Set<Id>();
        if (bucketSets == null) {
            appointmentsByWorkOrderId = queryListAppointmentsByWorkOrderId(workOrderIds);
        } else {
            billedWorkOrderIds = queryBilledWorkOrderIds(workOrderIds);
        }
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = queryListJunctionsByWorkOrderId(workOrderIds);
        Map<Id, Integer> visitCountByOpportunityId = queryVisitCountByOpportunityId(junctionsByWorkOrderId);

        for (Work_Order_Ledger__c ledgerRecord : ledgers) {
            List<ServiceAppointment> classificationAppointments;
            if (bucketSets == null) {
                List<ServiceAppointment> appointments = appointmentsByWorkOrderId.get(ledgerRecord.Work_Order__c);
                if (isInvoicedWork(ledgerRecord, appointments)) {
                    continue;
                }
                classificationAppointments = appointments;
            } else {
                if (isInvoicedWork(ledgerRecord, billedWorkOrderIds)) {
                    continue;
                }
                classificationAppointments = bucketSets.classificationAppointments(ledgerRecord.Work_Order__c);
                if (classificationAppointments.isEmpty()) {
                    continue;
                }
            }
            String bucketKey = classifyWorkOrder(classificationAppointments);
            if (String.isBlank(bucketKey) || !rowsByBucket.containsKey(bucketKey)) {
                continue;
            }
            List<ServiceAppointment> relatedAppointments = bucketSets == null
                ? appointmentsByWorkOrderId.get(ledgerRecord.Work_Order__c)
                : bucketSets.appointmentsForBucket(ledgerRecord.Work_Order__c, bucketKey);
            BillingControl_Orders.WorkOrderRowWrapper row = buildRow(
                ledgerRecord,
                relatedAppointments,
                junctionsByWorkOrderId.get(ledgerRecord.Work_Order__c),
                opportunityOwnerId,
                visitCountByOpportunityId
            );
            if (opportunityOwnerId != null
                && (row.relatedOpportunities == null || row.relatedOpportunities.isEmpty())) {
                continue;
            }
            rowsByBucket.get(bucketKey).add(row);
        }
        return rowsByBucket;
    }

    private static List<Work_Order_Ledger__c> queryLedgers(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Set<Id> includedWorkOrderIds
    ) {
        Id opportunityOwnerId = extractOpportunityOwnerId(filterContext);

        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        Integer ledgerLimit = ledgerQueryLimit();
        Set<Id> workOrderIds = includedWorkOrderIds;
        String soql =
            'SELECT Id, Work_Order__c, Account__c, Account__r.Name, Account__r.Owner.Name,'
            + ' Reconciliation_Status__c, Attention_Required__c, Attention_Reason__c,'
            + ' Service_Appointment_Count__c, Opportunity_Count__c, Opportunity_Owner__c,'
            + ' Last_Material_Activity__c, Last_Service_Date__c,'
            + ' Work_Order__r.WorkOrderNumber, Work_Order__r.Subject, Work_Order__r.Status,'
            + ' Work_Order__r.WorkType.Name,'
            + ' Work_Order__r.AccountId, Work_Order__r.CreatedDate, Work_Order__r.EndDate,'
            + ' Work_Order__r.Invoice_Number__c'
            + ' FROM Work_Order_Ledger__c WHERE Work_Order__c != NULL';
        if (!closedStatuses.isEmpty()) {
            soql += ' AND Work_Order__r.Status NOT IN :closedStatuses';
        }
        if (workOrderIds != null) {
            if (workOrderIds.isEmpty()) {
                return new List<Work_Order_Ledger__c>();
            }
            soql += ' AND Work_Order__c IN :workOrderIds';
        } else if (opportunityOwnerId != null) {
            workOrderIds = resolveWorkOrderIdsByOpportunityOwner(opportunityOwnerId);
            if (workOrderIds.isEmpty()) {
                return new List<Work_Order_Ledger__c>();
            }
            soql += ' AND Work_Order__c IN :workOrderIds';
        }
        soql += ' ORDER BY Last_Service_Date__c DESC NULLS LAST, Work_Order__r.CreatedDate DESC NULLS LAST LIMIT :ledgerLimit';
        return Database.query(soql);
    }

    private static Integer ledgerQueryLimit() {
        return queryLimitOverride == null ? LEDGER_QUERY_LIMIT : queryLimitOverride;
    }

    private static DateTimeRange toDateTimeRange(BillingControl_DataProvider.DateRangeDTO dateWindow) {
        DateTimeRange dateRange = new DateTimeRange();
        if (dateWindow == null || dateWindow.startDate == null || dateWindow.endDate == null) {
            return dateRange;
        }
        dateRange.rangeStart = Datetime.newInstance(dateWindow.startDate, Time.newInstance(0, 0, 0, 0));
        dateRange.rangeEnd = Datetime.newInstance(dateWindow.endDate, Time.newInstance(23, 59, 59, 0));
        return dateRange;
    }

    private class OperationalBucketSets {
        Map<Id, List<ServiceAppointment>> readyByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        Map<Id, List<ServiceAppointment>> scheduledByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        Map<Id, List<ServiceAppointment>> inProgressByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        Set<Id> workOrderIds = new Set<Id>();

        List<ServiceAppointment> classificationAppointments(Id workOrderId) {
            List<ServiceAppointment> appointments = new List<ServiceAppointment>();
            appointments.addAll(listFor(readyByWorkOrderId, workOrderId));
            appointments.addAll(listFor(scheduledByWorkOrderId, workOrderId));
            appointments.addAll(listFor(inProgressByWorkOrderId, workOrderId));
            return appointments;
        }

        List<ServiceAppointment> appointmentsForBucket(Id workOrderId, String bucketKey) {
            if (bucketKey == BUCKET_READY_TO_SCHEDULE) {
                return listFor(readyByWorkOrderId, workOrderId);
            }
            if (bucketKey == BUCKET_SCHEDULED_APPOINTMENTS) {
                return listFor(scheduledByWorkOrderId, workOrderId);
            }
            if (bucketKey == BUCKET_IN_PROGRESS) {
                return listFor(inProgressByWorkOrderId, workOrderId);
            }
            return new List<ServiceAppointment>();
        }

        private List<ServiceAppointment> listFor(Map<Id, List<ServiceAppointment>> byWorkOrderId, Id workOrderId) {
            List<ServiceAppointment> appointments = byWorkOrderId.get(workOrderId);
            return appointments == null ? new List<ServiceAppointment>() : appointments;
        }
    }

    private static OperationalBucketSets queryOperationalBucketSets(
        DateTimeRange dateRange,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        OperationalBucketSets bucketSets = new OperationalBucketSets();
        queryBucketInto(
            BUCKET_READY_TO_SCHEDULE,
            dateRange,
            filterContext,
            bucketSets.readyByWorkOrderId,
            bucketSets.workOrderIds
        );
        queryBucketInto(
            BUCKET_SCHEDULED_APPOINTMENTS,
            dateRange,
            filterContext,
            bucketSets.scheduledByWorkOrderId,
            bucketSets.workOrderIds
        );
        queryBucketInto(
            BUCKET_IN_PROGRESS,
            dateRange,
            filterContext,
            bucketSets.inProgressByWorkOrderId,
            bucketSets.workOrderIds
        );
        return bucketSets;
    }

    private static void queryBucketInto(
        String bucketKey,
        DateTimeRange dateRange,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Map<Id, List<ServiceAppointment>> byWorkOrderId,
        Set<Id> workOrderIds
    ) {
        Integer queryLimit = ledgerQueryLimit();
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        Set<String> cancelledStatuses = CANCELLED_SA_STATUSES;
        Datetime rangeStart = dateRange.rangeStart;
        Datetime rangeEnd = dateRange.rangeEnd;
        String predicate = bucketPredicate(bucketKey);
        String selectClause =
            'SELECT Id, ParentRecordId, AppointmentNumber, Status, Subject, CreatedDate,'
            + ' EarliestStartTime, SchedStartTime, SchedEndTime, ActualStartTime, ActualEndTime,'
            + ' Invoice_Number__c, WO_Inv_Status__c, Opportunity__c'
            + ' FROM ServiceAppointment WHERE '
            + predicate
            + ' AND Status NOT IN :cancelledStatuses';
        String orderClause = ' ORDER BY ' + bucketOrderField(bucketKey) + ' DESC NULLS LAST LIMIT :queryLimit';

        String workOrderParent = closedStatuses.isEmpty()
            ? ' AND ParentRecordId IN (SELECT Id FROM WorkOrder)'
            : ' AND ParentRecordId IN (SELECT Id FROM WorkOrder WHERE Status NOT IN :closedStatuses)';
        String lineItemParent = closedStatuses.isEmpty()
            ? ' AND ParentRecordId IN (SELECT Id FROM WorkOrderLineItem)'
            : ' AND ParentRecordId IN (SELECT Id FROM WorkOrderLineItem WHERE WorkOrder.Status NOT IN :closedStatuses)';

        List<ServiceAppointment> workOrderParentAppointments = Database.query(selectClause + workOrderParent + orderClause);
        List<ServiceAppointment> lineItemParentAppointments = Database.query(selectClause + lineItemParent + orderClause);
        if (workOrderParentAppointments.size() >= queryLimit || lineItemParentAppointments.size() >= queryLimit) {
            addRuntimeWarning(
                filterContext,
                BUCKET_LABELS.get(bucketKey)
                    + ' Service Appointment query hit the '
                    + String.valueOf(queryLimit)
                    + ' record limit. Results are incomplete. Narrow the date filter.'
            );
        }

        addAppointmentsToBucket(workOrderParentAppointments, byWorkOrderId, workOrderIds);
        addAppointmentsToBucket(lineItemParentAppointments, byWorkOrderId, workOrderIds);
    }

    private static String bucketPredicate(String bucketKey) {
        if (bucketKey == BUCKET_READY_TO_SCHEDULE) {
            return 'SchedStartTime = NULL AND SchedEndTime = NULL AND ActualStartTime = NULL AND ActualEndTime = NULL'
                + ' AND EarliestStartTime >= :rangeStart AND EarliestStartTime <= :rangeEnd';
        }
        if (bucketKey == BUCKET_SCHEDULED_APPOINTMENTS) {
            return 'SchedStartTime != NULL AND SchedEndTime != NULL AND ActualStartTime = NULL AND ActualEndTime = NULL'
                + ' AND SchedStartTime >= :rangeStart AND SchedStartTime <= :rangeEnd';
        }
        return 'ActualStartTime != NULL AND ActualEndTime = NULL'
            + ' AND ActualStartTime >= :rangeStart AND ActualStartTime <= :rangeEnd';
    }

    private static String bucketOrderField(String bucketKey) {
        if (bucketKey == BUCKET_READY_TO_SCHEDULE) {
            return 'EarliestStartTime';
        }
        if (bucketKey == BUCKET_SCHEDULED_APPOINTMENTS) {
            return 'SchedStartTime';
        }
        return 'ActualStartTime';
    }

    private static void addAppointmentsToBucket(
        List<ServiceAppointment> appointments,
        Map<Id, List<ServiceAppointment>> byWorkOrderId,
        Set<Id> workOrderIds
    ) {
        Map<Id, Id> workOrderIdByAppointmentId =
            BillingControl_Attribution.resolveWorkOrderIdsForAppointments(appointments);
        Set<Id> seenAppointmentIds = new Set<Id>();
        for (List<ServiceAppointment> existing : byWorkOrderId.values()) {
            for (ServiceAppointment existingAppointment : existing) {
                seenAppointmentIds.add(existingAppointment.Id);
            }
        }
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord == null || !seenAppointmentIds.add(appointmentRecord.Id)) {
                continue;
            }
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            if (workOrderId == null) {
                continue;
            }
            workOrderIds.add(workOrderId);
            if (!byWorkOrderId.containsKey(workOrderId)) {
                byWorkOrderId.put(workOrderId, new List<ServiceAppointment>());
            }
            byWorkOrderId.get(workOrderId).add(appointmentRecord);
        }
    }

    private static Set<Id> queryBilledWorkOrderIds(Set<Id> workOrderIds) {
        Set<Id> billedWorkOrderIds = new Set<Id>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return billedWorkOrderIds;
        }
        Map<Id, Id> workOrderIdByParentId = new Map<Id, Id>();
        for (Id workOrderId : workOrderIds) {
            workOrderIdByParentId.put(workOrderId, workOrderId);
        }
        for (WorkOrderLineItem lineItem : [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
        ]) {
            workOrderIdByParentId.put(lineItem.Id, lineItem.WorkOrderId);
        }
        Set<Id> parentIds = workOrderIdByParentId.keySet();
        for (ServiceAppointment appointmentRecord : [
            SELECT ParentRecordId, Invoice_Number__c
            FROM ServiceAppointment
            WHERE ParentRecordId IN :parentIds
            AND Invoice_Number__c != NULL
        ]) {
            if (String.isBlank(appointmentRecord.Invoice_Number__c)) {
                continue;
            }
            Id workOrderId = workOrderIdByParentId.get(appointmentRecord.ParentRecordId);
            if (workOrderId != null) {
                billedWorkOrderIds.add(workOrderId);
            }
        }
        return billedWorkOrderIds;
    }

    private static Set<Id> resolveWorkOrderIdsByOpportunityOwner(Id opportunityOwnerId) {
        Set<Id> includedWorkOrderIds = new Set<Id>();
        if (opportunityOwnerId == null) {
            return includedWorkOrderIds;
        }
        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Work_Order__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c != NULL
            AND Opportunity__c != NULL
            AND Opportunity__r.OwnerId = :opportunityOwnerId
        ]) {
            includedWorkOrderIds.add(junctionRecord.Work_Order__c);
        }
        return includedWorkOrderIds;
    }

    private static Id extractOpportunityOwnerId(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null) {
            return null;
        }
        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeKey(filterRecord.objectApiName) + '.' + normalizeKey(filterRecord.fieldApiName);
            if (isOpportunityOwnerFilter(fieldKey) && normalizeKey(filterRecord.operator) == 'EQUALS') {
                return tryParseId(filterRecord.value);
            }
        }
        return null;
    }

    private static Boolean isBilledAppointment(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null) {
            return false;
        }
        return containsBilledMarker(appointmentRecord.Invoice_Number__c)
            || containsBilledMarker(appointmentRecord.WO_Inv_Status__c);
    }

    private static Boolean containsBilledMarker(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.toLowerCase();
        return normalized.contains('inv') || normalized.contains('inspection');
    }

    private static Boolean isOpportunityOwnerFilter(String fieldKey) {
        return fieldKey == 'OPPORTUNITY.OWNERID';
    }

    private static Id tryParseId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        try {
            return Id.valueOf(rawValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<Id, List<ServiceAppointment>> queryListAppointmentsByWorkOrderId(Set<Id> workOrderIds) {
        return queryAppointmentsByWorkOrderId(
            workOrderIds,
            new List<String>{
                'Id',
                'ParentRecordId',
                'AppointmentNumber',
                'Status',
                'Subject',
                'CreatedDate',
                'EarliestStartTime',
                'SchedStartTime',
                'SchedEndTime',
                'ActualStartTime',
                'ActualEndTime',
                'Invoice_Number__c',
                'WO_Inv_Status__c'
            }
        );
    }

    private static Map<Id, List<ServiceAppointment>> queryDetailAppointments(Set<Id> workOrderIds) {
        return queryAppointmentsByWorkOrderId(
            workOrderIds,
            new List<String>{
                'Id',
                'ParentRecordId',
                'AppointmentNumber',
                'Status',
                'SchedStartTime',
                'ActualStartTime',
                'ActualEndTime',
                'Opportunity__c',
                'Opportunity__r.Name',
                'Invoice_Number__c',
                'WO_Inv_Status__c'
            }
        );
    }

    private static Map<Id, List<ServiceAppointment>> queryAppointmentsByWorkOrderId(
        Set<Id> workOrderIds,
        List<String> selectFields
    ) {
        Map<Id, List<ServiceAppointment>> appointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        for (Id workOrderId : workOrderIds) {
            appointmentsByWorkOrderId.put(workOrderId, new List<ServiceAppointment>());
        }
        Map<Id, Id> workOrderIdByParentId = new Map<Id, Id>();
        for (Id workOrderId : workOrderIds) {
            workOrderIdByParentId.put(workOrderId, workOrderId);
        }
        for (WorkOrderLineItem lineItem : [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
        ]) {
            workOrderIdByParentId.put(lineItem.Id, lineItem.WorkOrderId);
        }
        Set<Id> parentIds = workOrderIdByParentId.keySet();
        if (parentIds.isEmpty()) {
            return appointmentsByWorkOrderId;
        }
        String soql =
            'SELECT ' + String.join(selectFields, ', ')
            + ' FROM ServiceAppointment WHERE ParentRecordId IN :parentIds'
            + ' ORDER BY SchedStartTime ASC NULLS LAST, CreatedDate ASC';
        for (ServiceAppointment appointmentRecord : Database.query(soql)) {
            Id workOrderId = workOrderIdByParentId.get(appointmentRecord.ParentRecordId);
            if (workOrderId == null || !appointmentsByWorkOrderId.containsKey(workOrderId)) {
                continue;
            }
            appointmentsByWorkOrderId.get(workOrderId).add(appointmentRecord);
        }
        return appointmentsByWorkOrderId;
    }

    private static Map<Id, List<Opportunity_WorkOrder__c>> queryListJunctionsByWorkOrderId(Set<Id> workOrderIds) {
        return queryJunctionsByWorkOrderId(
            workOrderIds,
            new List<String>{
                'Work_Order__c',
                'Opportunity__c',
                'Opportunity__r.Name',
                'Opportunity__r.Amount',
                'Opportunity__r.OwnerId',
                'Opportunity__r.Owner.Name'
            }
        );
    }

    private static Map<Id, List<Opportunity_WorkOrder__c>> queryJunctionsByWorkOrderId(Set<Id> workOrderIds) {
        return queryJunctionsByWorkOrderId(
            workOrderIds,
            new List<String>{
                'Work_Order__c',
                'Opportunity__c',
                'Opportunity__r.Name',
                'Opportunity__r.Amount',
                'Opportunity__r.StageName',
                'Opportunity__r.Billing_Status__c',
                'Opportunity__r.OwnerId',
                'Opportunity__r.Owner.Name'
            }
        );
    }

    private static Map<Id, List<Opportunity_WorkOrder__c>> queryJunctionsByWorkOrderId(
        Set<Id> workOrderIds,
        List<String> selectFields
    ) {
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = new Map<Id, List<Opportunity_WorkOrder__c>>();
        for (Id workOrderId : workOrderIds) {
            junctionsByWorkOrderId.put(workOrderId, new List<Opportunity_WorkOrder__c>());
        }
        if (workOrderIds.isEmpty()) {
            return junctionsByWorkOrderId;
        }
        String soql =
            'SELECT ' + String.join(selectFields, ', ')
            + ' FROM Opportunity_WorkOrder__c'
            + ' WHERE Work_Order__c IN :workOrderIds'
            + ' AND Opportunity__c != NULL';
        for (Opportunity_WorkOrder__c junctionRecord : Database.query(soql)) {
            junctionsByWorkOrderId.get(junctionRecord.Work_Order__c).add(junctionRecord);
        }
        return junctionsByWorkOrderId;
    }

    private static Map<Id, Integer> queryVisitCountByOpportunityId(
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId
    ) {
        Map<Id, Integer> visitCountByOpportunityId = new Map<Id, Integer>();
        Set<Id> opportunityIds = new Set<Id>();
        if (junctionsByWorkOrderId == null) {
            return visitCountByOpportunityId;
        }
        for (List<Opportunity_WorkOrder__c> junctions : junctionsByWorkOrderId.values()) {
            if (junctions == null) {
                continue;
            }
            for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                if (junctionRecord != null && junctionRecord.Opportunity__c != null) {
                    opportunityIds.add(junctionRecord.Opportunity__c);
                }
            }
        }
        if (opportunityIds.isEmpty()) {
            return visitCountByOpportunityId;
        }
        for (AggregateResult aggregateRow : [
            SELECT Opportunity__c opportunityId, COUNT_DISTINCT(Work_Order__c) visitCount
            FROM Opportunity_WorkOrder__c
            WHERE Opportunity__c IN :opportunityIds
            AND Work_Order__c != NULL
            GROUP BY Opportunity__c
        ]) {
            Id opportunityId = (Id) aggregateRow.get('opportunityId');
            Integer visitCount = aggregateRow.get('visitCount') == null
                ? 0
                : Integer.valueOf(String.valueOf(aggregateRow.get('visitCount')));
            if (opportunityId != null) {
                visitCountByOpportunityId.put(opportunityId, visitCount);
            }
        }
        return visitCountByOpportunityId;
    }

    private static BillingControl_Orders.WorkOrderRowWrapper buildRow(
        Work_Order_Ledger__c ledgerRecord,
        List<ServiceAppointment> appointments,
        List<Opportunity_WorkOrder__c> junctions,
        Id opportunityOwnerId,
        Map<Id, Integer> visitCountByOpportunityId
    ) {
        if (appointments == null) {
            appointments = new List<ServiceAppointment>();
        }
        if (junctions == null) {
            junctions = new List<Opportunity_WorkOrder__c>();
        }
        if (opportunityOwnerId != null) {
            List<Opportunity_WorkOrder__c> ownerJunctions = new List<Opportunity_WorkOrder__c>();
            for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                if (junctionRecord == null
                    || junctionRecord.Opportunity__r == null
                    || junctionRecord.Opportunity__r.OwnerId != opportunityOwnerId) {
                    continue;
                }
                ownerJunctions.add(junctionRecord);
            }
            junctions = ownerJunctions;
        }

        BillingControl_Orders.WorkOrderRowWrapper row = new BillingControl_Orders.WorkOrderRowWrapper();
        row.rowKey = 'LED-' + String.valueOf(ledgerRecord.Id);
        row.ledgerId = ledgerRecord.Id;
        row.workOrderId = ledgerRecord.Work_Order__c;
        row.workOrderNumber = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.WorkOrderNumber;
        row.workTypeName = ledgerRecord.Work_Order__r == null || ledgerRecord.Work_Order__r.WorkType == null
            ? null
            : ledgerRecord.Work_Order__r.WorkType.Name;
        row.subject = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Subject;
        row.workOrderStatus = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.Status;
        row.status = ledgerRecord.Reconciliation_Status__c;
        row.accountId = ledgerRecord.Account__c != null
            ? ledgerRecord.Account__c
            : (ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.AccountId);
        row.accountName = ledgerRecord.Account__r == null ? null : ledgerRecord.Account__r.Name;
        row.accountOwnerName = ledgerRecord.Account__r == null || ledgerRecord.Account__r.Owner == null
            ? null
            : ledgerRecord.Account__r.Owner.Name;
        row.reconciliationStatus = ledgerRecord.Reconciliation_Status__c;
        row.attentionRequired = ledgerRecord.Attention_Required__c == true;
        row.attentionReason = ledgerRecord.Attention_Reason__c;
        row.createdDate = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.CreatedDate;
        Datetime workOrderCompletedAt = ledgerRecord.Work_Order__r == null ? null : ledgerRecord.Work_Order__r.EndDate;
        row.completedDate = ledgerRecord.Last_Service_Date__c != null
            ? ledgerRecord.Last_Service_Date__c
            : (workOrderCompletedAt == null ? null : workOrderCompletedAt.date());
        row.lastServiceDate = ledgerRecord.Last_Service_Date__c;
        row.effectiveDate = ledgerRecord.Last_Service_Date__c != null
            ? ledgerRecord.Last_Service_Date__c
            : (ledgerRecord.Last_Material_Activity__c == null ? null : ledgerRecord.Last_Material_Activity__c.date());
        row.serviceAppointmentCount = appointments.size();
        row.opportunityCount = junctions.size();

        List<BillingControl_Orders.WorkOrderRowWrapper> relatedAppointments =
            new List<BillingControl_Orders.WorkOrderRowWrapper>();
        for (ServiceAppointment appointmentRecord : appointments) {
            BillingControl_Orders.WorkOrderRowWrapper appointmentRow = new BillingControl_Orders.WorkOrderRowWrapper();
            appointmentRow.rowKey = 'SA-' + String.valueOf(appointmentRecord.Id);
            appointmentRow.serviceAppointmentId = appointmentRecord.Id;
            appointmentRow.serviceAppointmentNumber = appointmentRecord.AppointmentNumber;
            appointmentRow.serviceAppointmentStatus = appointmentRecord.Status;
            appointmentRow.status = appointmentRecord.Status;
            appointmentRow.subject = appointmentRecord.Subject;
            appointmentRow.createdDate = appointmentRecord.CreatedDate;
            appointmentRow.earliestStartTime = appointmentRecord.EarliestStartTime;
            appointmentRow.schedStartTime = appointmentRecord.SchedStartTime;
            appointmentRow.actualStartTime = appointmentRecord.ActualStartTime;
            if (appointmentRecord.EarliestStartTime != null
                && (row.earliestStartTime == null || appointmentRecord.EarliestStartTime < row.earliestStartTime)
            ) {
                row.earliestStartTime = appointmentRecord.EarliestStartTime;
            }
            if (appointmentRecord.SchedStartTime != null
                && (row.schedStartTime == null || appointmentRecord.SchedStartTime < row.schedStartTime)
            ) {
                row.schedStartTime = appointmentRecord.SchedStartTime;
            }
            if (appointmentRecord.ActualStartTime != null
                && (row.actualStartTime == null || appointmentRecord.ActualStartTime < row.actualStartTime)
            ) {
                row.actualStartTime = appointmentRecord.ActualStartTime;
            }
            appointmentRow.actualEndTime = appointmentRecord.ActualEndTime;
            appointmentRow.billedBadge = isBilledAppointment(appointmentRecord);
            appointmentRow.serviceAppointmentDisplay = buildServiceAppointmentDisplay(appointmentRecord);
            relatedAppointments.add(appointmentRow);
        }
        row.relatedServiceAppointments = relatedAppointments;

        Decimal amountTotal = 0;
        Set<Id> seenOpportunityIds = new Set<Id>();
        List<BillingControl_Orders.WorkOrderRowWrapper> relatedOpportunities =
            new List<BillingControl_Orders.WorkOrderRowWrapper>();
        List<String> opportunityNames = new List<String>();
        List<String> opportunityOwnerNames = new List<String>();
        Set<Id> seenOwnerIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : junctions) {
            if (junctionRecord.Opportunity__c == null || seenOpportunityIds.contains(junctionRecord.Opportunity__c)) {
                continue;
            }
            seenOpportunityIds.add(junctionRecord.Opportunity__c);
            BillingControl_Orders.WorkOrderRowWrapper opportunityRow = new BillingControl_Orders.WorkOrderRowWrapper();
            opportunityRow.rowKey = 'OPP-' + String.valueOf(junctionRecord.Opportunity__c);
            opportunityRow.opportunityId = junctionRecord.Opportunity__c;
            opportunityRow.opportunityName = junctionRecord.Opportunity__r == null
                ? null
                : junctionRecord.Opportunity__r.Name;
            if (junctionRecord.Opportunity__r != null) {
                opportunityRow.ownerId = junctionRecord.Opportunity__r.OwnerId;
                opportunityRow.ownerName = junctionRecord.Opportunity__r.Owner == null
                    ? null
                    : junctionRecord.Opportunity__r.Owner.Name;
            }
            relatedOpportunities.add(opportunityRow);
            if (String.isNotBlank(opportunityRow.opportunityName)) {
                opportunityNames.add(opportunityRow.opportunityName);
            }
            if (opportunityRow.ownerId != null && seenOwnerIds.add(opportunityRow.ownerId)
                && String.isNotBlank(opportunityRow.ownerName)) {
                opportunityOwnerNames.add(opportunityRow.ownerName);
            }
            if (junctionRecord.Opportunity__r != null && junctionRecord.Opportunity__r.Amount != null) {
                amountTotal += junctionRecord.Opportunity__r.Amount;
            }
        }
        row.relatedOpportunities = relatedOpportunities;
        if (relatedOpportunities.size() == 1) {
            row.opportunityId = relatedOpportunities[0].opportunityId;
            row.opportunityName = relatedOpportunities[0].opportunityName;
            row.ownerId = relatedOpportunities[0].ownerId;
            row.ownerName = relatedOpportunities[0].ownerName;
        } else if (!relatedOpportunities.isEmpty()) {
            row.opportunityId = null;
            row.opportunityName = String.join(opportunityNames, ', ');
            row.ownerName = String.join(opportunityOwnerNames, ', ');
            if (seenOwnerIds.size() == 1) {
                row.ownerId = new List<Id>(seenOwnerIds)[0];
            }
        }
        row.opportunityCount = seenOpportunityIds.size();
        row.opportunityAmount = row.opportunityCount == 0 ? null : amountTotal;
        row.visitAmount = resolveVisitAmount(
            row,
            junctions,
            visitCountByOpportunityId,
            row.opportunityAmount
        );
        return row;
    }

    private static Decimal resolveVisitAmount(
        BillingControl_Orders.WorkOrderRowWrapper row,
        List<Opportunity_WorkOrder__c> junctions,
        Map<Id, Integer> visitCountByOpportunityId,
        Decimal amountTotal
    ) {
        if (amountTotal == null) {
            return null;
        }
        if (!isPitCleaningRow(row)) {
            return amountTotal;
        }

        Decimal visitTotal = 0;
        Set<Id> seenOpportunityIds = new Set<Id>();
        Boolean usedSplit = false;
        for (Opportunity_WorkOrder__c junctionRecord : junctions) {
            if (junctionRecord == null
                || junctionRecord.Opportunity__c == null
                || seenOpportunityIds.contains(junctionRecord.Opportunity__c)
            ) {
                continue;
            }
            seenOpportunityIds.add(junctionRecord.Opportunity__c);
            Decimal opportunityAmount = junctionRecord.Opportunity__r == null
                ? null
                : junctionRecord.Opportunity__r.Amount;
            if (opportunityAmount == null) {
                continue;
            }
            Integer visitCount = visitCountByOpportunityId == null
                ? null
                : visitCountByOpportunityId.get(junctionRecord.Opportunity__c);
            if (visitCount == null || visitCount < 1) {
                visitCount = 1;
            }
            if (visitCount > 1) {
                usedSplit = true;
            }
            visitTotal += opportunityAmount.divide(visitCount, 2, System.RoundingMode.HALF_UP);
        }
        return usedSplit ? visitTotal : amountTotal;
    }

    @TestVisible
    private static Boolean isPitCleaningRow(BillingControl_Orders.WorkOrderRowWrapper row) {
        if (row == null) {
            return false;
        }
        if (matchesPitCleaningText(row.workTypeName) || matchesPitCleaningText(row.subject)
            || matchesPitCleaningText(row.opportunityName)) {
            return true;
        }
        if (row.relatedOpportunities == null) {
            return false;
        }
        for (BillingControl_Orders.WorkOrderRowWrapper opportunityRow : row.relatedOpportunities) {
            if (opportunityRow != null && matchesPitCleaningText(opportunityRow.opportunityName)) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static Boolean matchesPitCleaningText(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String text = value.toLowerCase();
        return Pattern.matches('(?s).*pit\\s*clean.*', text)
            || Pattern.matches('(?s).*preventa?tive\\s+maintenance.*', text);
    }

    private static String classifyWorkOrder(List<ServiceAppointment> appointments) {
        if (appointments == null || appointments.isEmpty()) {
            return BUCKET_READY_TO_SCHEDULE;
        }

        Boolean hasInProgress = false;
        Boolean hasScheduled = false;
        Boolean hasReady = false;
        Boolean hasOther = false;
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord == null || isCancelled(appointmentRecord.Status)) {
                continue;
            }
            if (isInProgressAppointment(appointmentRecord)) {
                hasInProgress = true;
            } else if (isScheduledAppointment(appointmentRecord)) {
                hasScheduled = true;
            } else if (isReadyToScheduleAppointment(appointmentRecord)) {
                hasReady = true;
            } else {
                hasOther = true;
            }
        }

        if (hasInProgress) {
            return BUCKET_IN_PROGRESS;
        }
        if (hasScheduled) {
            return BUCKET_SCHEDULED_APPOINTMENTS;
        }
        if (hasReady && !hasOther) {
            return BUCKET_READY_TO_SCHEDULE;
        }
        return null;
    }

    private static Boolean isInProgressAppointment(ServiceAppointment appointmentRecord) {
        return appointmentRecord != null
            && appointmentRecord.ActualStartTime != null
            && appointmentRecord.ActualEndTime == null;
    }

    private static Boolean isScheduledAppointment(ServiceAppointment appointmentRecord) {
        return appointmentRecord != null
            && appointmentRecord.SchedStartTime != null
            && appointmentRecord.SchedEndTime != null
            && appointmentRecord.ActualStartTime == null
            && appointmentRecord.ActualEndTime == null;
    }

    private static Boolean isReadyToScheduleAppointment(ServiceAppointment appointmentRecord) {
        return appointmentRecord != null
            && appointmentRecord.SchedStartTime == null
            && appointmentRecord.SchedEndTime == null
            && appointmentRecord.ActualStartTime == null
            && appointmentRecord.ActualEndTime == null;
    }

    @TestVisible
    private static Integer operationalBucketCount(ServiceAppointment appointmentRecord) {
        Integer membershipCount = 0;
        if (isReadyToScheduleAppointment(appointmentRecord)) {
            membershipCount++;
        }
        if (isScheduledAppointment(appointmentRecord)) {
            membershipCount++;
        }
        if (isInProgressAppointment(appointmentRecord)) {
            membershipCount++;
        }
        return membershipCount;
    }

    private static Boolean isInvoicedWork(
        Work_Order_Ledger__c ledgerRecord,
        Set<Id> billedWorkOrderIds
    ) {
        if (hasWorkOrderInvoiceNumber(ledgerRecord)) {
            return true;
        }
        return ledgerRecord != null
            && ledgerRecord.Work_Order__c != null
            && billedWorkOrderIds != null
            && billedWorkOrderIds.contains(ledgerRecord.Work_Order__c);
    }

    private static Boolean isInvoicedWork(
        Work_Order_Ledger__c ledgerRecord,
        List<ServiceAppointment> appointments
    ) {
        if (hasWorkOrderInvoiceNumber(ledgerRecord)) {
            return true;
        }
        if (appointments == null) {
            return false;
        }
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord != null && String.isNotBlank(appointmentRecord.Invoice_Number__c)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasWorkOrderInvoiceNumber(Work_Order_Ledger__c ledgerRecord) {
        return ledgerRecord != null
            && ledgerRecord.Work_Order__r != null
            && String.isNotBlank(ledgerRecord.Work_Order__r.Invoice_Number__c);
    }

    private static String buildServiceAppointmentDisplay(ServiceAppointment appointmentRecord) {
        String appointmentNumber = String.isNotBlank(appointmentRecord.AppointmentNumber)
            ? appointmentRecord.AppointmentNumber
            : String.valueOf(appointmentRecord.Id);
        String statusLabel;
        Datetime statusDate;
        if (appointmentRecord.ActualEndTime != null) {
            statusLabel = 'Completed';
            statusDate = appointmentRecord.ActualEndTime;
        } else if (appointmentRecord.ActualStartTime != null) {
            statusLabel = 'In Progress';
            statusDate = appointmentRecord.ActualStartTime;
        } else if (appointmentRecord.SchedStartTime != null && appointmentRecord.SchedEndTime != null) {
            statusLabel = 'Scheduled';
            statusDate = appointmentRecord.SchedStartTime;
        } else {
            return appointmentNumber + ' (none)';
        }
        return appointmentNumber + ' (' + statusLabel + ' - ' + statusDate.format('M/d/yyyy') + ')';
    }

    private static Boolean isCancelled(String statusValue) {
        if (String.isBlank(statusValue)) {
            return false;
        }
        String normalized = statusValue.trim().toUpperCase();
        return normalized.contains('CANCEL');
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

    private static String normalizeKey(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }
}
