/**
 * Billing Control Center Orders tab:
 * - Base scope: Closed Won opportunities in the last 3 years.
 * - KPI buckets:
 *   1) Unscheduled Work (WorkOrder status driven)
 *   2) Scheduled Work (WorkOrder has at least one Scheduled/In Progress ServiceAppointment)
 *   3) Scheduled for Today (ServiceAppointment status/date driven)
 *   4) Completed Today (ServiceAppointment status/date driven)
 *   5) Completed This Week (ServiceAppointment status/date driven, Sunday-Saturday)
 */
public with sharing class BillingControl_Orders {
    private static final String OPPORTUNITY_STAGE_CLOSED_WON = 'Closed Won';

    private static final String WORK_ORDER_FOR_CLEARANCE = 'For Clearance';
    private static final String WORK_ORDER_FOR_APPOINTMENT_BOOKING = 'For Appointment Booking';

    private static final String SERVICE_APPOINTMENT_STATUS_SCHEDULED = 'Scheduled';
    private static final String SERVICE_APPOINTMENT_STATUS_IN_PROGRESS = 'In Progress';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';

    private static final Set<String> WORK_ORDER_UNSCHEDULED_STATUSES = new Set<String>{
        WORK_ORDER_FOR_CLEARANCE,
        WORK_ORDER_FOR_APPOINTMENT_BOOKING
    };

    private static final Set<String> SERVICE_APPOINTMENT_SCHEDULED_WORK_STATUSES = new Set<String>{
        SERVICE_APPOINTMENT_STATUS_SCHEDULED,
        SERVICE_APPOINTMENT_STATUS_IN_PROGRESS
    };

    private static final String BUCKET_UNSCHEDULED = 'UNSCHEDULED';
    private static final String BUCKET_SCHEDULED = 'SCHEDULED';
    private static final String BUCKET_SCHEDULED_TODAY = 'SCHEDULED_TODAY';
    private static final String BUCKET_COMPLETED_TODAY = 'COMPLETED_TODAY';
    private static final String BUCKET_COMPLETED_THIS_WEEK = 'COMPLETED_THIS_WEEK';

    private static final String BUCKET_LABEL_UNSCHEDULED = 'Unscheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED = 'Scheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED_TODAY = 'Scheduled for Today';
    private static final String BUCKET_LABEL_COMPLETED_TODAY = 'Completed Today';
    private static final String BUCKET_LABEL_COMPLETED_THIS_WEEK = 'Completed This Week';

    /**
     * Returns KPI totals/counts for the five Orders tab buckets.
     */
    public static KpiWrapper getKpis() {
        return getKpis(null);
    }

    /**
     * Returns KPI totals/counts for the five Orders tab buckets.
     * refreshToken is intentionally ignored and exists only to bypass client cache when needed.
     */
    @AuraEnabled(cacheable=true)
    public static KpiWrapper getKpis(Long refreshToken) {
        List<BucketSectionWrapper> sections = getBucketWorkOrders(refreshToken);
        KpiWrapper result = new KpiWrapper();

        BucketSectionWrapper unscheduled = findSectionByKey(sections, BUCKET_UNSCHEDULED);
        BucketSectionWrapper scheduled = findSectionByKey(sections, BUCKET_SCHEDULED);
        BucketSectionWrapper scheduledToday = findSectionByKey(sections, BUCKET_SCHEDULED_TODAY);
        BucketSectionWrapper completedToday = findSectionByKey(sections, BUCKET_COMPLETED_TODAY);
        BucketSectionWrapper completedThisWeek = findSectionByKey(sections, BUCKET_COMPLETED_THIS_WEEK);

        result.unscheduledCount = unscheduled != null ? unscheduled.rows.size() : 0;
        result.unscheduledRevenue = sumOpportunityAmount(unscheduled != null ? unscheduled.rows : null);

        result.scheduledCount = scheduled != null ? scheduled.rows.size() : 0;
        result.scheduledRevenue = sumOpportunityAmount(scheduled != null ? scheduled.rows : null);

        result.scheduledTodayCount = scheduledToday != null ? scheduledToday.rows.size() : 0;
        result.scheduledTodayRevenue = sumOpportunityAmount(scheduledToday != null ? scheduledToday.rows : null);

        result.completedTodayCount = completedToday != null ? completedToday.rows.size() : 0;
        result.completedTodayRevenue = sumOpportunityAmount(completedToday != null ? completedToday.rows : null);

        result.completedThisWeekCount = completedThisWeek != null ? completedThisWeek.rows.size() : 0;
        result.completedThisWeekRevenue = sumOpportunityAmount(completedThisWeek != null ? completedThisWeek.rows : null);

        // Legacy compatibility fields.
        result.inProgressCount = 0;
        result.inProgressRevenue = 0;

        return result;
    }

    /**
     * Backward-compatible alias for legacy LWC imports still calling getOrdersKpiData.
     */
    @AuraEnabled(cacheable=true)
    public static KpiWrapper getOrdersKpiData() {
        return getKpis();
    }

    /**
     * Returns the five fixed bucket sections for Orders tab accordion.
     * Sections are always returned in this order:
     * UNSCHEDULED, SCHEDULED, SCHEDULED_TODAY, COMPLETED_TODAY, COMPLETED_THIS_WEEK.
     */
    public static List<BucketSectionWrapper> getBucketWorkOrders() {
        return getBucketWorkOrders(null);
    }

    /**
     * Returns the five fixed bucket sections for Orders tab accordion.
     * Sections are always returned in this order:
     * UNSCHEDULED, SCHEDULED, SCHEDULED_TODAY, COMPLETED_TODAY, COMPLETED_THIS_WEEK.
     * refreshToken is intentionally ignored and exists only to bypass client cache when needed.
     */
    @AuraEnabled(cacheable=true)
    public static List<BucketSectionWrapper> getBucketWorkOrders(Long refreshToken) {
        List<BucketSectionWrapper> sections = buildDefaultBucketSections();
        Map<String, List<WorkOrderRowWrapper>> rowsByBucketKey = new Map<String, List<WorkOrderRowWrapper>>();
        for (BucketSectionWrapper sectionRecord : sections) {
            rowsByBucketKey.put(sectionRecord.bucketKey, sectionRecord.rows);
        }

        List<Opportunity_WorkOrder__c> junctionRecords = [
            SELECT Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Amount,
                Work_Order__c,
                Work_Order__r.WorkOrderNumber,
                Work_Order__r.Status,
                Work_Order__r.Subject,
                Work_Order__r.AccountId,
                Work_Order__r.Account.Name,
                Work_Order__r.OwnerId,
                Work_Order__r.Owner.Name,
                Work_Order__r.CreatedDate
            FROM Opportunity_WorkOrder__c
            WHERE
                Opportunity__c IN (
                    SELECT Id
                    FROM Opportunity
                    WHERE StageName = :OPPORTUNITY_STAGE_CLOSED_WON AND CloseDate >= LAST_N_YEARS:3
                )
            ORDER BY Work_Order__r.WorkOrderNumber ASC NULLS LAST, Opportunity__r.Name ASC NULLS LAST
        ];

        if (junctionRecords.isEmpty()) {
            return sections;
        }

        Map<Id, Opportunity_WorkOrder__c> primaryJunctionByWorkOrderId = new Map<Id, Opportunity_WorkOrder__c>();
        Map<Id, Opportunity_WorkOrder__c> primaryJunctionByOpportunityId = new Map<Id, Opportunity_WorkOrder__c>();
        Set<Id> workOrderIds = new Set<Id>();

        for (Opportunity_WorkOrder__c junctionRecord : junctionRecords) {
            if (junctionRecord.Work_Order__c == null) {
                continue;
            }
            workOrderIds.add(junctionRecord.Work_Order__c);
            if (!primaryJunctionByWorkOrderId.containsKey(junctionRecord.Work_Order__c)) {
                primaryJunctionByWorkOrderId.put(junctionRecord.Work_Order__c, junctionRecord);
            }
            if (
                junctionRecord.Opportunity__c != null
                && !primaryJunctionByOpportunityId.containsKey(junctionRecord.Opportunity__c)
            ) {
                primaryJunctionByOpportunityId.put(junctionRecord.Opportunity__c, junctionRecord);
            }
        }

        if (workOrderIds.isEmpty()) {
            return sections;
        }

        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                AppointmentNumber,
                ParentRecordId,
                Opportunity__c,
                Status,
                Subject,
                SchedStartTime,
                ActualEndTime,
                OwnerId,
                Owner.Name
            FROM ServiceAppointment
            WHERE ParentRecordId IN :workOrderIds
            ORDER BY ParentRecordId ASC NULLS LAST, SchedStartTime ASC NULLS LAST, AppointmentNumber ASC NULLS LAST
        ]) {
            if (!serviceAppointmentsByWorkOrderId.containsKey(appointmentRecord.ParentRecordId)) {
                serviceAppointmentsByWorkOrderId.put(appointmentRecord.ParentRecordId, new List<ServiceAppointment>());
            }
            serviceAppointmentsByWorkOrderId.get(appointmentRecord.ParentRecordId).add(appointmentRecord);
        }

        Map<Id, String> serviceAppointmentDisplayByWorkOrderId = new Map<Id, String>();
        for (Id workOrderId : serviceAppointmentsByWorkOrderId.keySet()) {
            serviceAppointmentDisplayByWorkOrderId.put(
                workOrderId,
                buildServiceAppointmentDisplay(serviceAppointmentsByWorkOrderId.get(workOrderId))
            );
        }

        Date todayDate = Date.today();
        Set<Id> seenUnscheduledWorkOrderIds = new Set<Id>();
        Set<Id> seenScheduledWorkOrderIds = new Set<Id>();
        Set<Id> seenScheduledTodayAppointmentIds = new Set<Id>();
        Set<Id> seenCompletedTodayWorkOrderIds = new Set<Id>();
        Set<Id> seenCompletedThisWeekWorkOrderIds = new Set<Id>();

        for (Id workOrderId : primaryJunctionByWorkOrderId.keySet()) {
            Opportunity_WorkOrder__c workOrderContext = primaryJunctionByWorkOrderId.get(workOrderId);
            String workOrderStatus = workOrderContext.Work_Order__r != null
                ? workOrderContext.Work_Order__r.Status
                : null;
            List<ServiceAppointment> workOrderAppointments = serviceAppointmentsByWorkOrderId.containsKey(workOrderId)
                ? serviceAppointmentsByWorkOrderId.get(workOrderId)
                : new List<ServiceAppointment>();
            String serviceAppointmentDisplay = serviceAppointmentDisplayByWorkOrderId.get(workOrderId);

            if (
                String.isNotBlank(workOrderStatus)
                && WORK_ORDER_UNSCHEDULED_STATUSES.contains(workOrderStatus)
                && seenUnscheduledWorkOrderIds.add(workOrderId)
            ) {
                rowsByBucketKey.get(BUCKET_UNSCHEDULED).add(
                    buildWorkOrderBucketRow(workOrderContext, serviceAppointmentDisplay)
                );
            }

            if (hasScheduledOrInProgressAppointment(workOrderAppointments) && seenScheduledWorkOrderIds.add(workOrderId)) {
                rowsByBucketKey.get(BUCKET_SCHEDULED).add(
                    buildWorkOrderBucketRow(workOrderContext, serviceAppointmentDisplay)
                );
            }

            for (ServiceAppointment appointmentRecord : workOrderAppointments) {
                Opportunity_WorkOrder__c opportunityContext = (
                    appointmentRecord.Opportunity__c != null
                    && primaryJunctionByOpportunityId.containsKey(appointmentRecord.Opportunity__c)
                )
                    ? primaryJunctionByOpportunityId.get(appointmentRecord.Opportunity__c)
                    : workOrderContext;

                if (
                    isScheduledOrInProgressStatus(appointmentRecord.Status)
                    && isSameDay(appointmentRecord.SchedStartTime, todayDate)
                    && seenScheduledTodayAppointmentIds.add(appointmentRecord.Id)
                ) {
                    rowsByBucketKey.get(BUCKET_SCHEDULED_TODAY).add(
                        buildServiceAppointmentBucketRow(
                            appointmentRecord,
                            opportunityContext,
                            workOrderContext,
                            serviceAppointmentDisplay
                        )
                    );
                }

                if (
                    SERVICE_APPOINTMENT_STATUS_COMPLETED.equals(appointmentRecord.Status)
                    && isSameDay(appointmentRecord.ActualEndTime, todayDate)
                    && seenCompletedTodayWorkOrderIds.add(workOrderId)
                ) {
                    rowsByBucketKey.get(BUCKET_COMPLETED_TODAY).add(
                        buildServiceAppointmentBucketRow(
                            appointmentRecord,
                            opportunityContext,
                            workOrderContext,
                            serviceAppointmentDisplay
                        )
                    );
                }

                if (
                    SERVICE_APPOINTMENT_STATUS_COMPLETED.equals(appointmentRecord.Status)
                    && isInSundayThroughTodayWeek(appointmentRecord.ActualEndTime, todayDate)
                    && seenCompletedThisWeekWorkOrderIds.add(workOrderId)
                ) {
                    rowsByBucketKey.get(BUCKET_COMPLETED_THIS_WEEK).add(
                        buildServiceAppointmentBucketRow(
                            appointmentRecord,
                            opportunityContext,
                            workOrderContext,
                            serviceAppointmentDisplay
                        )
                    );
                }
            }
        }

        for (BucketSectionWrapper sectionRecord : sections) {
            sectionRecord.rows.sort(new WorkOrderRowNumberComparator());
        }

        return sections;
    }

    /**
     * Legacy entry point for the old Orders table. Returns an empty list.
     * The Billing Control Center UI uses getBucketWorkOrders() instead; this remains so cached
     * or partially deployed clients that still reference getOrders do not throw "no apex action available".
     */
    @AuraEnabled(cacheable=true)
    public static List<OrderRowWrapper> getOrders() {
        return new List<OrderRowWrapper>();
    }

    private static List<BucketSectionWrapper> buildDefaultBucketSections() {
        return new List<BucketSectionWrapper>{
            new BucketSectionWrapper(BUCKET_UNSCHEDULED, BUCKET_LABEL_UNSCHEDULED, new List<WorkOrderRowWrapper>()),
            new BucketSectionWrapper(BUCKET_SCHEDULED, BUCKET_LABEL_SCHEDULED, new List<WorkOrderRowWrapper>()),
            new BucketSectionWrapper(
                BUCKET_SCHEDULED_TODAY,
                BUCKET_LABEL_SCHEDULED_TODAY,
                new List<WorkOrderRowWrapper>()
            ),
            new BucketSectionWrapper(
                BUCKET_COMPLETED_TODAY,
                BUCKET_LABEL_COMPLETED_TODAY,
                new List<WorkOrderRowWrapper>()
            ),
            new BucketSectionWrapper(
                BUCKET_COMPLETED_THIS_WEEK,
                BUCKET_LABEL_COMPLETED_THIS_WEEK,
                new List<WorkOrderRowWrapper>()
            )
        };
    }

    private static BucketSectionWrapper findSectionByKey(List<BucketSectionWrapper> sections, String sectionKey) {
        if (sections == null || String.isBlank(sectionKey)) {
            return null;
        }
        for (BucketSectionWrapper sectionRecord : sections) {
            if (sectionRecord.bucketKey == sectionKey) {
                return sectionRecord;
            }
        }
        return null;
    }

    private static Boolean hasScheduledOrInProgressAppointment(List<ServiceAppointment> appointments) {
        if (appointments == null || appointments.isEmpty()) {
            return false;
        }
        for (ServiceAppointment appointmentRecord : appointments) {
            if (isScheduledOrInProgressStatus(appointmentRecord.Status)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isScheduledOrInProgressStatus(String statusValue) {
        return String.isNotBlank(statusValue) && SERVICE_APPOINTMENT_SCHEDULED_WORK_STATUSES.contains(statusValue);
    }

    private static Boolean isSameDay(Datetime value, Date targetDate) {
        return value != null && targetDate != null && value.date() == targetDate;
    }

    private static Boolean isInSundayThroughTodayWeek(Datetime value, Date targetDate) {
        if (value == null || targetDate == null) {
            return false;
        }
        Date weekStart = getSundayWeekStart(targetDate);
        Date valueDate = value.date();
        return valueDate >= weekStart && valueDate <= targetDate;
    }

    private static Date getSundayWeekStart(Date targetDate) {
        Integer daysSinceAnchorSunday = Date.newInstance(1900, 1, 7).daysBetween(targetDate);
        Integer daysAfterSunday = Math.mod(daysSinceAnchorSunday, 7);
        if (daysAfterSunday < 0) {
            daysAfterSunday += 7;
        }
        return targetDate.addDays(-daysAfterSunday);
    }

    private static Decimal sumOpportunityAmount(List<WorkOrderRowWrapper> rows) {
        Decimal total = 0;
        if (rows == null) {
            return total;
        }
        for (WorkOrderRowWrapper row : rows) {
            total += row.opportunityAmount != null ? row.opportunityAmount : 0;
        }
        return total;
    }

    private static String buildServiceAppointmentDisplay(List<ServiceAppointment> appointments) {
        if (appointments == null || appointments.isEmpty()) {
            return null;
        }

        List<String> lines = new List<String>();
        for (ServiceAppointment appointmentRecord : appointments) {
            String appointmentName = String.isNotBlank(appointmentRecord.AppointmentNumber)
                ? appointmentRecord.AppointmentNumber
                : appointmentRecord.Subject;
            if (String.isBlank(appointmentName) && appointmentRecord.Id != null) {
                appointmentName = String.valueOf(appointmentRecord.Id);
            }

            String appointmentStatus = String.isNotBlank(appointmentRecord.Status) ? appointmentRecord.Status : '';
            String scheduledDate = appointmentRecord.SchedStartTime != null
                ? formatDateAsIso(appointmentRecord.SchedStartTime.date())
                : '';
            lines.add(String.join(new List<String>{ appointmentName, appointmentStatus, scheduledDate }, ': '));
        }
        return String.join(lines, '\n');
    }

    private static String formatDateAsIso(Date value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.year())
            + '-'
            + String.valueOf(value.month()).leftPad(2, '0')
            + '-'
            + String.valueOf(value.day()).leftPad(2, '0');
    }

    private static WorkOrderRowWrapper buildWorkOrderBucketRow(
        Opportunity_WorkOrder__c context,
        String serviceAppointmentDisplay
    ) {
        WorkOrderRowWrapper row = new WorkOrderRowWrapper();
        Id workOrderId = context != null ? context.Work_Order__c : null;
        row.rowKey = workOrderId != null ? 'WO-' + String.valueOf(workOrderId) : null;
        row.workOrderId = workOrderId;
        row.workOrderNumber = context != null && context.Work_Order__r != null
            ? context.Work_Order__r.WorkOrderNumber
            : null;
        row.subject = context != null && context.Work_Order__r != null ? context.Work_Order__r.Subject : null;
        row.status = context != null && context.Work_Order__r != null ? context.Work_Order__r.Status : null;
        row.accountId = context != null && context.Work_Order__r != null ? context.Work_Order__r.AccountId : null;
        row.accountName = context != null && context.Work_Order__r != null && context.Work_Order__r.Account != null
            ? context.Work_Order__r.Account.Name
            : null;
        row.opportunityId = context != null ? context.Opportunity__c : null;
        row.opportunityName = context != null && context.Opportunity__r != null ? context.Opportunity__r.Name : null;
        row.opportunityAmount = context != null && context.Opportunity__r != null ? context.Opportunity__r.Amount : null;
        row.ownerId = context != null && context.Work_Order__r != null ? context.Work_Order__r.OwnerId : null;
        row.ownerName = context != null && context.Work_Order__r != null && context.Work_Order__r.Owner != null
            ? context.Work_Order__r.Owner.Name
            : null;
        row.createdDate = context != null && context.Work_Order__r != null ? context.Work_Order__r.CreatedDate : null;
        row.serviceAppointmentId = null;
        row.serviceAppointmentNumber = null;
        row.serviceAppointmentDisplay = serviceAppointmentDisplay;
        return row;
    }

    private static WorkOrderRowWrapper buildServiceAppointmentBucketRow(
        ServiceAppointment appointmentRecord,
        Opportunity_WorkOrder__c opportunityContext,
        Opportunity_WorkOrder__c workOrderContext,
        String serviceAppointmentDisplay
    ) {
        WorkOrderRowWrapper row = new WorkOrderRowWrapper();
        row.rowKey = appointmentRecord != null ? 'SA-' + String.valueOf(appointmentRecord.Id) : null;
        row.serviceAppointmentId = appointmentRecord != null ? appointmentRecord.Id : null;
        row.serviceAppointmentNumber = appointmentRecord != null ? appointmentRecord.AppointmentNumber : null;

        row.workOrderId = workOrderContext != null ? workOrderContext.Work_Order__c : null;
        row.workOrderNumber = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.WorkOrderNumber
            : null;
        row.accountId = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.AccountId
            : null;
        row.accountName = workOrderContext != null
            && workOrderContext.Work_Order__r != null
            && workOrderContext.Work_Order__r.Account != null
                ? workOrderContext.Work_Order__r.Account.Name
                : null;

        row.opportunityId = opportunityContext != null ? opportunityContext.Opportunity__c : null;
        row.opportunityName = opportunityContext != null && opportunityContext.Opportunity__r != null
            ? opportunityContext.Opportunity__r.Name
            : null;
        row.opportunityAmount = opportunityContext != null && opportunityContext.Opportunity__r != null
            ? opportunityContext.Opportunity__r.Amount
            : null;

        row.subject = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.Subject
            : null;
        row.status = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.Status
            : null;
        row.ownerId = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.OwnerId
            : null;
        row.ownerName = workOrderContext != null
            && workOrderContext.Work_Order__r != null
            && workOrderContext.Work_Order__r.Owner != null
                ? workOrderContext.Work_Order__r.Owner.Name
                : null;
        row.createdDate = workOrderContext != null && workOrderContext.Work_Order__r != null
            ? workOrderContext.Work_Order__r.CreatedDate
            : null;
        row.serviceAppointmentDisplay = serviceAppointmentDisplay;
        return row;
    }

    private class WorkOrderRowNumberComparator implements Comparator<WorkOrderRowWrapper> {
        public Integer compare(WorkOrderRowWrapper left, WorkOrderRowWrapper right) {
            String leftNumber = String.isNotBlank(left.workOrderNumber) ? left.workOrderNumber : '';
            String rightNumber = String.isNotBlank(right.workOrderNumber) ? right.workOrderNumber : '';
            Integer numberCompare = leftNumber.compareTo(rightNumber);
            if (numberCompare != 0) {
                return numberCompare;
            }
            String leftSubject = String.isNotBlank(left.subject) ? left.subject : '';
            String rightSubject = String.isNotBlank(right.subject) ? right.subject : '';
            Integer subjectCompare = leftSubject.compareTo(rightSubject);
            if (subjectCompare != 0) {
                return subjectCompare;
            }
            String leftKey = String.isNotBlank(left.rowKey) ? left.rowKey : '';
            String rightKey = String.isNotBlank(right.rowKey) ? right.rowKey : '';
            return leftKey.compareTo(rightKey);
        }
    }

    public class KpiWrapper {
        @AuraEnabled public Decimal unscheduledRevenue;
        @AuraEnabled public Integer unscheduledCount;
        @AuraEnabled public Decimal scheduledRevenue;
        @AuraEnabled public Integer scheduledCount;
        @AuraEnabled public Decimal scheduledTodayRevenue;
        @AuraEnabled public Integer scheduledTodayCount;
        @AuraEnabled public Decimal completedTodayRevenue;
        @AuraEnabled public Integer completedTodayCount;
        @AuraEnabled public Decimal completedThisWeekRevenue;
        @AuraEnabled public Integer completedThisWeekCount;
        // Legacy compatibility fields retained to avoid breaking stale clients.
        @AuraEnabled public Decimal inProgressRevenue;
        @AuraEnabled public Integer inProgressCount;
    }

    public class BucketSectionWrapper {
        @AuraEnabled public String bucketKey;
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public List<WorkOrderRowWrapper> rows;

        public BucketSectionWrapper(String bucketKeyValue, String sectionLabelValue, List<WorkOrderRowWrapper> rowValues) {
            bucketKey = bucketKeyValue;
            sectionLabel = sectionLabelValue;
            rows = rowValues;
        }
    }

    public class WorkOrderRowWrapper {
        @AuraEnabled public String rowKey;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public String serviceAppointmentDisplay;
    }

    /** Shape retained for legacy getOrders() consumers only. */
    public class OrderRowWrapper {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public String opportunityStageName;
        @AuraEnabled public Date opportunityCloseDate;
        @AuraEnabled public String workOrderLabel;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Datetime activatedDate;
    }
}