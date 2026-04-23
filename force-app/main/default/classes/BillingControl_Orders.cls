/**
 * Billing Control Center Orders tab KPIs and drilldown. Two pairs of tiles are exposed:
 * <ul>
 *   <li>Pair 1 (backlog, opportunity count and Amount): Unscheduled vs Scheduled backlog on Closed Won
 *       opportunities with CloseDate in the last 3 years (LAST_N_YEARS:3). Scheduled backlog is inclusive
 *       of opportunities whose service appointments are scheduled or in progress for today.</li>
 *   <li>Pair 2 (today, service appointment counts): SAs scheduled for today and SAs completed today,
 *       scoped to work orders linked to in-scope Closed Won opportunities.</li>
 * </ul>
 * Scheduled for today (KPIs and drilldown): work order must be Appointments Booked, then at least one
 * service appointment with Status = Scheduled or In Progress, with SchedStartTime on the user's today
 * (Date.today() in the running user context). "Completed today" uses SA Status = Completed and
 * ActualEndTime on today.
 */
public with sharing class BillingControl_Orders {
    private static final String OPPORTUNITY_STAGE_CLOSED_WON = 'Closed Won';

    private static final String WORK_ORDER_FOR_CLEARANCE = 'For Clearance';
    private static final String WORK_ORDER_FOR_APPOINTMENT_BOOKING = 'For Appointment Booking';
    private static final String WORK_ORDER_APPOINTMENTS_BOOKED = 'Appointments Booked';

    private static final String SERVICE_APPOINTMENT_STATUS_SCHEDULED = 'Scheduled';
    private static final String SERVICE_APPOINTMENT_STATUS_IN_PROGRESS = 'In Progress';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';

    private static final Set<String> WORK_ORDER_UNSCHEDULED_STATUSES = new Set<String>{
        WORK_ORDER_FOR_CLEARANCE,
        WORK_ORDER_FOR_APPOINTMENT_BOOKING
    };

    private static final String BUCKET_SCHEDULED = 'SCHEDULED';
    private static final String BUCKET_UNSCHEDULED = 'UNSCHEDULED';
    private static final String BUCKET_SCHEDULED_TODAY = 'SCHEDULED_TODAY';
    private static final String BUCKET_COMPLETED_TODAY = 'COMPLETED_TODAY';
    private static final String BUCKET_SCHEDULED_BACKLOG = 'SCHEDULED_BACKLOG';

    /** Service appointment is Completed and ActualEndTime falls on today (per running user's date). */
    private static Boolean isServiceAppointmentCompletedToday(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null || !SERVICE_APPOINTMENT_STATUS_COMPLETED.equals(appointmentRecord.Status)) {
            return false;
        }
        return appointmentRecord.ActualEndTime != null
            && appointmentRecord.ActualEndTime.date() == Date.today();
    }

    /** One line per SA; used in drilldown. Sorted by scheduled start. */
    private static String buildServiceAppointmentsDisplay(List<ServiceAppointment> appointmentRecords) {
        if (appointmentRecords == null || appointmentRecords.isEmpty()) {
            return '';
        }
        List<ServiceAppointment> ordered = new List<ServiceAppointment>(appointmentRecords);
        ordered.sort(new ServiceAppointmentSchedStartComparator());
        List<String> lines = new List<String>();
        for (ServiceAppointment sa : ordered) {
            String label = String.isNotBlank(sa.AppointmentNumber)
                ? sa.AppointmentNumber
                : (String.isNotBlank(sa.Subject) ? sa.Subject : String.valueOf(sa.Id).left(8));
            String statusText = String.isNotBlank(sa.Status) ? sa.Status : '';
            if (SERVICE_APPOINTMENT_STATUS_COMPLETED.equals(sa.Status) && sa.ActualEndTime != null) {
                statusText = statusText + ' · ' + sa.ActualEndTime.format('M/d/yyyy h:mm a');
            } else if (sa.SchedStartTime != null) {
                statusText = statusText + ' · ' + sa.SchedStartTime.format('M/d/yyyy h:mm a');
            }
            lines.add(String.isNotBlank(statusText) ? (label + ': ' + statusText) : label);
        }
        return String.join(lines, '\n');
    }

    private class ServiceAppointmentSchedStartComparator implements Comparator<ServiceAppointment> {
        public Integer compare(ServiceAppointment left, ServiceAppointment right) {
            if (left.SchedStartTime == null && right.SchedStartTime == null) {
                return 0;
            }
            if (left.SchedStartTime == null) {
                return 1;
            }
            if (right.SchedStartTime == null) {
                return -1;
            }
            if (left.SchedStartTime == right.SchedStartTime) {
                return 0;
            }
            return left.SchedStartTime < right.SchedStartTime ? -1 : 1;
        }
    }

    /**
     * "Scheduled for today" on an Appointments Booked work order: Status is Scheduled or In Progress,
     * and scheduled start date (SchedStartTime) equals today in the running user context.
     */
    private static Boolean isServiceAppointmentScheduledForToday(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null || appointmentRecord.SchedStartTime == null) {
            return false;
        }
        if (appointmentRecord.SchedStartTime.date() != Date.today()) {
            return false;
        }
        return SERVICE_APPOINTMENT_STATUS_SCHEDULED.equals(appointmentRecord.Status)
            || SERVICE_APPOINTMENT_STATUS_IN_PROGRESS.equals(appointmentRecord.Status);
    }

    /**
     * Pair 1 (backlog, opportunity-level): unscheduled and scheduled-backlog counts and Amount totals on
     * recent Closed Won wins. Scheduled backlog is inclusive of opportunities that also qualify as "today".
     * Pair 2 (today, SA-level): count of service appointments scheduled for today and completed today.
     * The mutually exclusive classifier outputs (`scheduledRevenue`, `scheduledToday*`, etc.) are retained
     * for internal use and tests; the Orders LWC renders the pair 1/2 fields described above.
     */
    @AuraEnabled
    public static KpiWrapper getKpis() {
        KpiWrapper result = new KpiWrapper();
        result.unscheduledRevenue = 0;
        result.unscheduledCount = 0;
        result.scheduledRevenue = 0;
        result.scheduledCount = 0;
        result.scheduledTodayRevenue = 0;
        result.scheduledTodayCount = 0;
        result.completedTodayRevenue = 0;
        result.completedTodayCount = 0;
        result.scheduledBacklogRevenue = 0;
        result.scheduledBacklogCount = 0;
        result.serviceAppointmentsScheduledTodayCount = 0;
        result.serviceAppointmentsCompletedTodayCount = 0;

        List<Opportunity> closedWonOpportunities = [
            SELECT Id, Amount
            FROM Opportunity
            WHERE StageName = :OPPORTUNITY_STAGE_CLOSED_WON
            AND CloseDate >= LAST_N_YEARS:3
        ];

        if (closedWonOpportunities.isEmpty()) {
            return result;
        }

        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opportunityRecord : closedWonOpportunities) {
            opportunityIds.add(opportunityRecord.Id);
        }

        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByOpportunityId = new Map<Id, List<Opportunity_WorkOrder__c>>();
        Set<Id> workOrderIds = new Set<Id>();

        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Opportunity__c, Work_Order__c, Work_Order__r.Status
            FROM Opportunity_WorkOrder__c
            WHERE Opportunity__c IN :opportunityIds
        ]) {
            if (!junctionsByOpportunityId.containsKey(junctionRecord.Opportunity__c)) {
                junctionsByOpportunityId.put(junctionRecord.Opportunity__c, new List<Opportunity_WorkOrder__c>());
            }
            junctionsByOpportunityId.get(junctionRecord.Opportunity__c).add(junctionRecord);
            if (junctionRecord.Work_Order__c != null) {
                workOrderIds.add(junctionRecord.Work_Order__c);
            }
        }

        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        if (!workOrderIds.isEmpty()) {
            for (ServiceAppointment appointmentRecord : [
                SELECT Id, ParentRecordId, Status, SchedStartTime, ActualEndTime
                FROM ServiceAppointment
                WHERE ParentRecordId IN :workOrderIds
            ]) {
                if (!serviceAppointmentsByWorkOrderId.containsKey(appointmentRecord.ParentRecordId)) {
                    serviceAppointmentsByWorkOrderId.put(appointmentRecord.ParentRecordId, new List<ServiceAppointment>());
                }
                serviceAppointmentsByWorkOrderId.get(appointmentRecord.ParentRecordId).add(appointmentRecord);
            }
        }

        Decimal unscheduledRevenue = 0;
        Decimal scheduledRevenue = 0;
        Decimal scheduledTodayRevenue = 0;
        Decimal completedTodayRevenue = 0;
        Integer unscheduledCount = 0;
        Integer scheduledCount = 0;
        Integer scheduledTodayCount = 0;
        Integer completedTodayCount = 0;
        Decimal scheduledBacklogRevenue = 0;
        Integer scheduledBacklogCount = 0;

        for (Opportunity opportunityRecord : closedWonOpportunities) {
            Decimal opportunityAmount = opportunityRecord.Amount != null ? opportunityRecord.Amount : 0;
            String bucket = classifyOpportunityBucket(
                junctionsByOpportunityId.get(opportunityRecord.Id),
                serviceAppointmentsByWorkOrderId
            );

            if (bucket == BUCKET_COMPLETED_TODAY) {
                completedTodayRevenue += opportunityAmount;
                completedTodayCount++;
            } else if (bucket == BUCKET_SCHEDULED_TODAY) {
                scheduledTodayRevenue += opportunityAmount;
                scheduledTodayCount++;
                scheduledBacklogRevenue += opportunityAmount;
                scheduledBacklogCount++;
            } else if (bucket == BUCKET_SCHEDULED) {
                scheduledRevenue += opportunityAmount;
                scheduledCount++;
                scheduledBacklogRevenue += opportunityAmount;
                scheduledBacklogCount++;
            } else if (bucket == BUCKET_UNSCHEDULED) {
                unscheduledRevenue += opportunityAmount;
                unscheduledCount++;
            }
        }

        Integer serviceAppointmentsScheduledTodayCount = 0;
        Integer serviceAppointmentsCompletedTodayCount = 0;
        for (List<ServiceAppointment> appointmentsForWorkOrder : serviceAppointmentsByWorkOrderId.values()) {
            for (ServiceAppointment appointmentRecord : appointmentsForWorkOrder) {
                if (isServiceAppointmentCompletedToday(appointmentRecord)) {
                    serviceAppointmentsCompletedTodayCount++;
                } else if (isServiceAppointmentScheduledForToday(appointmentRecord)) {
                    serviceAppointmentsScheduledTodayCount++;
                }
            }
        }

        result.unscheduledRevenue = unscheduledRevenue;
        result.unscheduledCount = unscheduledCount;
        result.scheduledRevenue = scheduledRevenue;
        result.scheduledCount = scheduledCount;
        result.scheduledTodayRevenue = scheduledTodayRevenue;
        result.scheduledTodayCount = scheduledTodayCount;
        result.completedTodayRevenue = completedTodayRevenue;
        result.completedTodayCount = completedTodayCount;
        result.scheduledBacklogRevenue = scheduledBacklogRevenue;
        result.scheduledBacklogCount = scheduledBacklogCount;
        result.serviceAppointmentsScheduledTodayCount = serviceAppointmentsScheduledTodayCount;
        result.serviceAppointmentsCompletedTodayCount = serviceAppointmentsCompletedTodayCount;

        return result;
    }

    /**
     * Classifies a Closed Won opportunity into one pipeline bucket (mutually exclusive).
     * Precedence: Completed today (SA) > Scheduled for today (Appointments Booked + SA Scheduled or In Progress + start today) >
     * General scheduled (Appointments Booked: In Progress or Scheduled with start not today) > Unscheduled WO.
     * Opportunities with no junction rows are excluded.
     */
    private static String classifyOpportunityBucket(
        List<Opportunity_WorkOrder__c> junctionRecords,
        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId
    ) {
        Boolean hasUnscheduled = false;
        Boolean hasCompletedToday = false;
        Boolean hasScheduledToday = false;
        Boolean hasGeneralScheduled = false;

        if (junctionRecords == null || junctionRecords.isEmpty()) {
            return null;
        }

        for (Opportunity_WorkOrder__c junctionRecord : junctionRecords) {
            String workOrderStatus = junctionRecord.Work_Order__r != null
                ? junctionRecord.Work_Order__r.Status
                : null;
            Id workOrderId = junctionRecord.Work_Order__c;

            if (String.isNotBlank(workOrderStatus) && WORK_ORDER_UNSCHEDULED_STATUSES.contains(workOrderStatus)) {
                hasUnscheduled = true;
            }

            if (
                workOrderId != null
                && WORK_ORDER_APPOINTMENTS_BOOKED.equals(workOrderStatus)
                && serviceAppointmentsByWorkOrderId.containsKey(workOrderId)
            ) {
                for (ServiceAppointment appointmentRecord : serviceAppointmentsByWorkOrderId.get(workOrderId)) {
                    if (isServiceAppointmentCompletedToday(appointmentRecord)) {
                        hasCompletedToday = true;
                    } else if (isServiceAppointmentScheduledForToday(appointmentRecord)) {
                        hasScheduledToday = true;
                    } else if (SERVICE_APPOINTMENT_STATUS_IN_PROGRESS.equals(appointmentRecord.Status)) {
                        hasGeneralScheduled = true;
                    } else if (SERVICE_APPOINTMENT_STATUS_SCHEDULED.equals(appointmentRecord.Status)) {
                        hasGeneralScheduled = true;
                    }
                }
            }
        }

        if (hasCompletedToday) {
            return BUCKET_COMPLETED_TODAY;
        }
        if (hasScheduledToday) {
            return BUCKET_SCHEDULED_TODAY;
        }
        if (hasGeneralScheduled) {
            return BUCKET_SCHEDULED;
        }
        if (hasUnscheduled) {
            return BUCKET_UNSCHEDULED;
        }
        return null;
    }

    /**
     * Work Order rows grouped into the same four KPI buckets (direct WO + SA classification).
     * Scope: junction rows for Closed Won opportunities with CloseDate in the last 3 years (same as getKpis).
     */
    @AuraEnabled
    public static List<BucketSectionWrapper> getBucketWorkOrders() {
        BucketSectionWrapper unscheduledSection = new BucketSectionWrapper(
            BUCKET_UNSCHEDULED, 'Unscheduled Backlog', new List<WorkOrderRowWrapper>()
        );
        BucketSectionWrapper backlogSection = new BucketSectionWrapper(
            BUCKET_SCHEDULED_BACKLOG, 'Scheduled Backlog', new List<WorkOrderRowWrapper>()
        );
        BucketSectionWrapper scheduledTodaySection = new BucketSectionWrapper(
            BUCKET_SCHEDULED_TODAY, 'Scheduled for Today', new List<WorkOrderRowWrapper>()
        );
        BucketSectionWrapper completedTodaySection = new BucketSectionWrapper(
            BUCKET_COMPLETED_TODAY, 'Completed Today', new List<WorkOrderRowWrapper>()
        );

        List<BucketSectionWrapper> sections = new List<BucketSectionWrapper>{
            unscheduledSection,
            backlogSection,
            scheduledTodaySection,
            completedTodaySection
        };

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
            ORDER BY Work_Order__r.WorkOrderNumber ASC NULLS LAST
        ];

        if (junctionRecords.isEmpty()) {
            return sections;
        }

        Set<Id> allJunctionWorkOrderIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : junctionRecords) {
            if (junctionRecord.Work_Order__c != null) {
                allJunctionWorkOrderIds.add(junctionRecord.Work_Order__c);
            }
        }

        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        if (!allJunctionWorkOrderIds.isEmpty()) {
            for (ServiceAppointment appointmentRecord : [
                SELECT
                    Id,
                    ParentRecordId,
                    Status,
                    SchedStartTime,
                    ActualEndTime,
                    AppointmentNumber,
                    Subject
                FROM ServiceAppointment
                WHERE ParentRecordId IN :allJunctionWorkOrderIds
            ]) {
                if (!serviceAppointmentsByWorkOrderId.containsKey(appointmentRecord.ParentRecordId)) {
                    serviceAppointmentsByWorkOrderId.put(
                        appointmentRecord.ParentRecordId,
                        new List<ServiceAppointment>()
                    );
                }
                serviceAppointmentsByWorkOrderId.get(appointmentRecord.ParentRecordId).add(appointmentRecord);
            }
        }

        Set<Id> seenWorkOrderIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : junctionRecords) {
            Id workOrderId = junctionRecord.Work_Order__c;
            if (workOrderId == null || seenWorkOrderIds.contains(workOrderId)) {
                continue;
            }

            String workOrderStatus = junctionRecord.Work_Order__r != null
                ? junctionRecord.Work_Order__r.Status
                : null;
            String bucket = classifyWorkOrderBucket(workOrderStatus, workOrderId, serviceAppointmentsByWorkOrderId);
            if (bucket == null) {
                continue;
            }

            seenWorkOrderIds.add(workOrderId);

            WorkOrderRowWrapper row = new WorkOrderRowWrapper();
            row.workOrderId = workOrderId;
            row.workOrderNumber = junctionRecord.Work_Order__r != null
                ? junctionRecord.Work_Order__r.WorkOrderNumber
                : null;
            row.subject = junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.Subject : null;
            row.status = workOrderStatus;
            row.accountId = junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.AccountId : null;
            row.accountName = junctionRecord.Work_Order__r != null && junctionRecord.Work_Order__r.Account != null
                ? junctionRecord.Work_Order__r.Account.Name
                : null;
            row.opportunityId = junctionRecord.Opportunity__c;
            row.opportunityName = junctionRecord.Opportunity__r != null ? junctionRecord.Opportunity__r.Name : null;
            row.opportunityAmount = junctionRecord.Opportunity__r != null ? junctionRecord.Opportunity__r.Amount : null;
            row.ownerId = junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.OwnerId : null;
            row.ownerName = junctionRecord.Work_Order__r != null && junctionRecord.Work_Order__r.Owner != null
                ? junctionRecord.Work_Order__r.Owner.Name
                : null;
            row.createdDate = junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.CreatedDate : null;
            List<ServiceAppointment> saForRow = serviceAppointmentsByWorkOrderId.containsKey(workOrderId)
                ? serviceAppointmentsByWorkOrderId.get(workOrderId)
                : new List<ServiceAppointment>();
            row.serviceAppointmentsSummary = buildServiceAppointmentsDisplay(saForRow);

            if (bucket == BUCKET_UNSCHEDULED) {
                unscheduledSection.rows.add(row);
            } else if (bucket == BUCKET_SCHEDULED) {
                backlogSection.rows.add(row);
            } else if (bucket == BUCKET_SCHEDULED_TODAY) {
                backlogSection.rows.add(row);
                scheduledTodaySection.rows.add(row);
            } else if (bucket == BUCKET_COMPLETED_TODAY) {
                completedTodaySection.rows.add(row);
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

    /**
     * Direct work-order bucket. Precedence when WO is Appointments Booked: Completed today (SA) >
     * Scheduled for today (SA Scheduled or In Progress, SchedStart on today) > General scheduled
     * (In Progress or Scheduled with start not today). Unscheduled: For Clearance / For Appointment Booking.
     */
    private static String classifyWorkOrderBucket(
        String workOrderStatus,
        Id workOrderId,
        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId
    ) {
        if (String.isNotBlank(workOrderStatus) && WORK_ORDER_UNSCHEDULED_STATUSES.contains(workOrderStatus)) {
            return BUCKET_UNSCHEDULED;
        }

        if (
            WORK_ORDER_APPOINTMENTS_BOOKED.equals(workOrderStatus)
            && workOrderId != null
            && serviceAppointmentsByWorkOrderId.containsKey(workOrderId)
        ) {
            Boolean hasCompletedToday = false;
            Boolean hasScheduledToday = false;
            Boolean hasGeneralScheduled = false;

            for (ServiceAppointment appointmentRecord : serviceAppointmentsByWorkOrderId.get(workOrderId)) {
                if (isServiceAppointmentCompletedToday(appointmentRecord)) {
                    hasCompletedToday = true;
                } else if (isServiceAppointmentScheduledForToday(appointmentRecord)) {
                    hasScheduledToday = true;
                } else if (SERVICE_APPOINTMENT_STATUS_IN_PROGRESS.equals(appointmentRecord.Status)) {
                    hasGeneralScheduled = true;
                } else if (SERVICE_APPOINTMENT_STATUS_SCHEDULED.equals(appointmentRecord.Status)) {
                    hasGeneralScheduled = true;
                }
            }
            if (hasCompletedToday) {
                return BUCKET_COMPLETED_TODAY;
            }
            if (hasScheduledToday) {
                return BUCKET_SCHEDULED_TODAY;
            }
            if (hasGeneralScheduled) {
                return BUCKET_SCHEDULED;
            }
        }

        return null;
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
            return leftSubject.compareTo(rightSubject);
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
        @AuraEnabled public Decimal scheduledBacklogRevenue;
        @AuraEnabled public Integer scheduledBacklogCount;
        @AuraEnabled public Integer serviceAppointmentsScheduledTodayCount;
        @AuraEnabled public Integer serviceAppointmentsCompletedTodayCount;
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
        @AuraEnabled public String serviceAppointmentsSummary;
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