/**
 * Billing Control Center: pipeline KPIs use Closed Won opportunities with CloseDate in the last 3 years
 * (LAST_N_YEARS:3). Adjust that literal in getKpis() if your org needs a different window.
 */
public with sharing class BillingControl_Orders {
    private static final String OPPORTUNITY_STAGE_CLOSED_WON = 'Closed Won';

    private static final String WORK_ORDER_FOR_CLEARANCE = 'For Clearance';
    private static final String WORK_ORDER_FOR_APPOINTMENT_BOOKING = 'For Appointment Booking';
    private static final String WORK_ORDER_APPOINTMENTS_BOOKED = 'Appointments Booked';

    private static final String SERVICE_APPOINTMENT_STATUS_SCHEDULED = 'Scheduled';
    private static final String SERVICE_APPOINTMENT_STATUS_IN_PROGRESS = 'In Progress';

    private static final Set<String> WORK_ORDER_UNSCHEDULED_STATUSES = new Set<String>{
        WORK_ORDER_FOR_CLEARANCE,
        WORK_ORDER_FOR_APPOINTMENT_BOOKING
    };

    private static final String BUCKET_IN_PROGRESS = 'IN_PROGRESS';
    private static final String BUCKET_SCHEDULED = 'SCHEDULED';
    private static final String BUCKET_UNSCHEDULED = 'UNSCHEDULED';

    /**
     * Sums Opportunity.Amount into unscheduled / scheduled / in-progress buckets for recent Closed Won wins.
     */
    @AuraEnabled(cacheable=true)
    public static KpiWrapper getKpis() {
        KpiWrapper result = new KpiWrapper();
        result.unscheduledRevenue = 0;
        result.unscheduledCount = 0;
        result.scheduledRevenue = 0;
        result.scheduledCount = 0;
        result.inProgressRevenue = 0;
        result.inProgressCount = 0;

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
                SELECT Id, ParentRecordId, Status
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
        Decimal inProgressRevenue = 0;
        Integer unscheduledCount = 0;
        Integer scheduledCount = 0;
        Integer inProgressCount = 0;

        for (Opportunity opportunityRecord : closedWonOpportunities) {
            Decimal opportunityAmount = opportunityRecord.Amount != null ? opportunityRecord.Amount : 0;
            String bucket = classifyOpportunityBucket(
                junctionsByOpportunityId.get(opportunityRecord.Id),
                serviceAppointmentsByWorkOrderId
            );

            if (bucket == BUCKET_IN_PROGRESS) {
                inProgressRevenue += opportunityAmount;
                inProgressCount++;
            } else if (bucket == BUCKET_SCHEDULED) {
                scheduledRevenue += opportunityAmount;
                scheduledCount++;
            } else if (bucket == BUCKET_UNSCHEDULED) {
                unscheduledRevenue += opportunityAmount;
                unscheduledCount++;
            }
        }

        result.unscheduledRevenue = unscheduledRevenue;
        result.unscheduledCount = unscheduledCount;
        result.scheduledRevenue = scheduledRevenue;
        result.scheduledCount = scheduledCount;
        result.inProgressRevenue = inProgressRevenue;
        result.inProgressCount = inProgressCount;

        return result;
    }

    /**
     * Classifies a Closed Won opportunity into a single pipeline bucket.
     * Precedence: In Progress > Scheduled > Unscheduled.
     * Opportunities with no junction rows are excluded (legacy pre–Field Service noise).
     * "Unscheduled" requires at least one linked work order in For Clearance or For Appointment Booking.
     */
    private static String classifyOpportunityBucket(
        List<Opportunity_WorkOrder__c> junctionRecords,
        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId
    ) {
        Boolean hasInProgress = false;
        Boolean hasScheduled = false;
        Boolean hasUnscheduled = false;

        if (junctionRecords == null || junctionRecords.isEmpty()) {
            return null;
        } else {
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
                    for (
                        ServiceAppointment appointmentRecord : serviceAppointmentsByWorkOrderId.get(workOrderId)
                    ) {
                        if (SERVICE_APPOINTMENT_STATUS_IN_PROGRESS.equals(appointmentRecord.Status)) {
                            hasInProgress = true;
                        }
                        if (SERVICE_APPOINTMENT_STATUS_SCHEDULED.equals(appointmentRecord.Status)) {
                            hasScheduled = true;
                        }
                    }
                }
            }
        }

        if (hasInProgress) {
            return BUCKET_IN_PROGRESS;
        }
        if (hasScheduled) {
            return BUCKET_SCHEDULED;
        }
        if (hasUnscheduled) {
            return BUCKET_UNSCHEDULED;
        }
        return null;
    }

    /**
     * Work Order rows grouped into the same three KPI buckets (direct WO + SA classification).
     * Scope: junction rows for Closed Won opportunities with CloseDate in the last 3 years (same as getKpis).
     */
    @AuraEnabled(cacheable=true)
    public static List<BucketSectionWrapper> getBucketWorkOrders() {
        List<BucketSectionWrapper> sections = new List<BucketSectionWrapper>();
        sections.add(
            new BucketSectionWrapper(BUCKET_UNSCHEDULED, 'Unscheduled Work Value', new List<WorkOrderRowWrapper>())
        );
        sections.add(new BucketSectionWrapper(BUCKET_SCHEDULED, 'Scheduled Work Value', new List<WorkOrderRowWrapper>()));
        sections.add(
            new BucketSectionWrapper(BUCKET_IN_PROGRESS, 'In Progress Work Value', new List<WorkOrderRowWrapper>())
        );

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
            ORDER BY Work_Order__r.WorkOrderNumber ASC NULLS LAST
        ];

        if (junctionRecords.isEmpty()) {
            return sections;
        }

        Set<Id> appointmentsBookedWorkOrderIds = new Set<Id>();
        for (Opportunity_WorkOrder__c junctionRecord : junctionRecords) {
            if (
                junctionRecord.Work_Order__c != null
                && WORK_ORDER_APPOINTMENTS_BOOKED.equals(
                    junctionRecord.Work_Order__r != null ? junctionRecord.Work_Order__r.Status : null
                )
            ) {
                appointmentsBookedWorkOrderIds.add(junctionRecord.Work_Order__c);
            }
        }

        Map<Id, List<ServiceAppointment>> serviceAppointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        if (!appointmentsBookedWorkOrderIds.isEmpty()) {
            for (ServiceAppointment appointmentRecord : [
                SELECT Id, ParentRecordId, Status
                FROM ServiceAppointment
                WHERE ParentRecordId IN :appointmentsBookedWorkOrderIds
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

            rowsByBucketKey.get(bucket).add(row);
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
     * Direct work-order bucket: In Progress SA > Scheduled SA > Unscheduled WO statuses.
     * Appointments Booked without qualifying service appointments is excluded.
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
            Boolean hasInProgress = false;
            Boolean hasScheduled = false;
            for (ServiceAppointment appointmentRecord : serviceAppointmentsByWorkOrderId.get(workOrderId)) {
                if (SERVICE_APPOINTMENT_STATUS_IN_PROGRESS.equals(appointmentRecord.Status)) {
                    hasInProgress = true;
                }
                if (SERVICE_APPOINTMENT_STATUS_SCHEDULED.equals(appointmentRecord.Status)) {
                    hasScheduled = true;
                }
            }
            if (hasInProgress) {
                return BUCKET_IN_PROGRESS;
            }
            if (hasScheduled) {
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