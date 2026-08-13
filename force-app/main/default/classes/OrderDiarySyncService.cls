public without sharing class OrderDiarySyncService {
    private static final String ORDER_DIARY_STATUS_DRAFT = 'Draft';
    private static final String ORDER_DIARY_STATUS_FOR_REVIEW = 'For Review';
    private static final String ORDER_DIARY_STATUS_READY_TO_BILL = 'Ready to Bill';
    private static final String ORDER_DIARY_STATUS_ON_HOLD = 'On Hold';
    private static final String REVIEW_STATUS_NEEDS_REVIEW = 'Needs Review';
    private static final String REVIEW_STATUS_REVIEWED = 'Reviewed';
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';

    private static String cachedOrderStatus;
    private static String cachedDraftStatus;
    private static String cachedForReviewStatus;
    private static String cachedReadyToBillStatus;
    private static String cachedOnHoldStatus;
    private static String cachedNeedsReviewStatus;
    private static String cachedReviewedStatus;
    private static Id cachedStandardPricebookId;

    public class ServiceAppointmentRequest {
        @InvocableVariable(required=true)
        public Id serviceAppointmentId;
    }

    public class WorkOrderRequest {
        @InvocableVariable(required=true)
        public Id workOrderId;
    }

    public class OpportunityWorkOrderRequest {
        @InvocableVariable(required=true)
        public Id workOrderId;
    }

    public class OrderDiaryOperationalState {
        public String billingDiaryStatus;
        public Boolean readyForBilling;
        public String reviewStatus;
    }

    public static void syncServiceAppointmentsInvocable(List<ServiceAppointmentRequest> requests) {
        Set<Id> serviceAppointmentIds = new Set<Id>();
        if (requests != null) {
            for (ServiceAppointmentRequest requestRecord : requests) {
                if (requestRecord != null && requestRecord.serviceAppointmentId != null) {
                    serviceAppointmentIds.add(requestRecord.serviceAppointmentId);
                }
            }
        }
        syncServiceAppointmentIds(serviceAppointmentIds, false);
    }

    public static void syncWorkOrdersInvocable(List<WorkOrderRequest> requests) {
        Set<Id> workOrderIds = new Set<Id>();
        if (requests != null) {
            for (WorkOrderRequest requestRecord : requests) {
                if (requestRecord != null && requestRecord.workOrderId != null) {
                    workOrderIds.add(requestRecord.workOrderId);
                }
            }
        }
        syncWorkOrderIds(workOrderIds);
    }

    public static void syncOpportunityWorkOrdersInvocable(List<OpportunityWorkOrderRequest> requests) {
        Set<Id> workOrderIds = new Set<Id>();
        if (requests != null) {
            for (OpportunityWorkOrderRequest requestRecord : requests) {
                if (requestRecord != null && requestRecord.workOrderId != null) {
                    workOrderIds.add(requestRecord.workOrderId);
                }
            }
        }
        syncWorkOrderIds(workOrderIds);
    }

    public static void syncServiceAppointmentIds(Set<Id> serviceAppointmentIds) {
        syncServiceAppointmentIds(serviceAppointmentIds, false);
    }

    public static void syncServiceAppointmentIds(Set<Id> serviceAppointmentIds, Boolean allowCreate) {
        if (serviceAppointmentIds == null || serviceAppointmentIds.isEmpty()) {
            return;
        }

        List<ServiceAppointment> appointments = [
            SELECT Id,
                ParentRecordId,
                OwnerId,
                Status,
                EarliestStartTime,
                SchedStartTime,
                ActualStartTime,
                ActualEndTime,
                Opportunity__c
            FROM ServiceAppointment
            WHERE Id IN :serviceAppointmentIds
        ];
        if (appointments.isEmpty()) {
            return;
        }

        Set<Id> workOrderIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> appointmentIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : appointments) {
            appointmentIds.add(appointmentRecord.Id);
            if (appointmentRecord.ParentRecordId != null && appointmentRecord.ParentRecordId.getSObjectType() == WorkOrder.SObjectType) {
                workOrderIds.add(appointmentRecord.ParentRecordId);
            }
            if (appointmentRecord.Opportunity__c != null) {
                opportunityIds.add(appointmentRecord.Opportunity__c);
            }
        }

        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>();
        if (!workOrderIds.isEmpty()) {
            workOrderById = new Map<Id, WorkOrder>([
                SELECT Id, AccountId, Pricebook2Id
                FROM WorkOrder
                WHERE Id IN :workOrderIds
            ]);
        }

        Map<Id, Id> singleOpportunityByWorkOrderId = buildSingleOpportunityByWorkOrderId(workOrderIds);
        opportunityIds.addAll(singleOpportunityByWorkOrderId.values());

        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
        if (!opportunityIds.isEmpty()) {
            opportunityById = new Map<Id, Opportunity>([
                SELECT Id, AccountId, Pricebook2Id
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);
        }

        Map<Id, Order> existingOrderByAppointmentId = new Map<Id, Order>();
        for (Order orderRecord : [
            SELECT Id,
                AccountId,
                OpportunityId,
                Work_Order__c,
                Service_Appointment__c,
                Billing_Diary_Status__c,
                Review_Status__c,
                Ready_For_Billing__c,
                Billing_Hold_Reason__c,
                Billable_Amount__c,
                Invoiced_Amount__c,
                Received_Amount__c,
                Billing_Diary_Key__c
            FROM Order
            WHERE Service_Appointment__c IN :appointmentIds
            ORDER BY CreatedDate ASC
        ]) {
            Id appointmentId = (Id) orderRecord.get('Service_Appointment__c');
            if (!existingOrderByAppointmentId.containsKey(appointmentId)) {
                existingOrderByAppointmentId.put(appointmentId, orderRecord);
            }
        }

        List<Order> ordersToUpsert = new List<Order>();
        Id defaultPricebookId = null;
        for (ServiceAppointment appointmentRecord : appointments) {
            Id workOrderId = appointmentRecord.ParentRecordId != null
                && appointmentRecord.ParentRecordId.getSObjectType() == WorkOrder.SObjectType
                    ? appointmentRecord.ParentRecordId
                    : null;
            WorkOrder workOrderRecord = workOrderId != null ? workOrderById.get(workOrderId) : null;

            Id resolvedOpportunityId = appointmentRecord.Opportunity__c;
            if (resolvedOpportunityId == null && workOrderId != null && singleOpportunityByWorkOrderId.containsKey(workOrderId)) {
                resolvedOpportunityId = singleOpportunityByWorkOrderId.get(workOrderId);
            }
            Opportunity opportunityRecord = resolvedOpportunityId != null ? opportunityById.get(resolvedOpportunityId) : null;

            Id accountId = workOrderRecord != null && workOrderRecord.AccountId != null
                ? workOrderRecord.AccountId
                : (opportunityRecord != null ? opportunityRecord.AccountId : null);

            Order existingOrder = existingOrderByAppointmentId.get(appointmentRecord.Id);
            if (existingOrder == null && !allowCreate) {
                continue;
            }
            if (existingOrder == null && accountId == null) {
                System.debug(LoggingLevel.WARN,
                    'Order diary sync skipped ServiceAppointment ' + appointmentRecord.Id + ' because no AccountId could be resolved.'
                );
                continue;
            }

            Order orderRecord = existingOrder != null ? new Order(Id = existingOrder.Id) : new Order();
            if (existingOrder == null) {
                Id pricebookId = workOrderRecord != null
                    ? workOrderRecord.Pricebook2Id
                    : null;
                if (pricebookId == null && opportunityRecord != null) {
                    pricebookId = opportunityRecord.Pricebook2Id;
                }
                if (pricebookId == null) {
                    if (defaultPricebookId == null) {
                        defaultPricebookId = getStandardPricebookId();
                    }
                    pricebookId = defaultPricebookId;
                }
                orderRecord.AccountId = accountId;
                orderRecord.EffectiveDate = appointmentRecord.ActualEndTime != null
                    ? appointmentRecord.ActualEndTime.date()
                    : Date.today();
                orderRecord.Status = getDefaultOrderStatus();
                orderRecord.Pricebook2Id = pricebookId;
            } else {
                if (accountId != null) {
                    orderRecord.AccountId = accountId;
                }
            }

            orderRecord.OpportunityId = resolvedOpportunityId;
            orderRecord.Work_Order__c = workOrderId;
            orderRecord.Service_Appointment__c = appointmentRecord.Id;
            orderRecord.Billing_Diary_Key__c = buildBillingDiaryKey(appointmentRecord.Id, resolvedOpportunityId);
            orderRecord.Last_Sync_From_Service_Appointment__c = System.now();
            if (existingOrder == null && appointmentRecord.OwnerId != null && appointmentRecord.OwnerId.getSObjectType() == User.SObjectType) {
                orderRecord.Technician__c = appointmentRecord.OwnerId;
            }

            String currentBillingStatus = existingOrder != null ? (String) existingOrder.get('Billing_Diary_Status__c') : null;
            String currentReviewStatus = existingOrder != null ? (String) existingOrder.get('Review_Status__c') : null;
            String holdReason = existingOrder != null ? (String) existingOrder.get('Billing_Hold_Reason__c') : null;
            Decimal invoicedAmount = existingOrder != null ? (Decimal) existingOrder.get('Invoiced_Amount__c') : null;
            Decimal receivedAmount = existingOrder != null ? (Decimal) existingOrder.get('Received_Amount__c') : null;

            OrderDiaryOperationalState state = deriveOperationalState(
                currentReviewStatus,
                holdReason,
                appointmentRecord.Status,
                appointmentRecord.ActualEndTime,
                appointmentRecord.SchedStartTime,
                invoicedAmount,
                receivedAmount
            );
            orderRecord.Billing_Diary_Status__c = state.billingDiaryStatus;
            orderRecord.Ready_For_Billing__c = state.readyForBilling;
            if (!String.isBlank(state.reviewStatus)) {
                orderRecord.Review_Status__c = state.reviewStatus;
            }

            ordersToUpsert.add(orderRecord);
        }

        if (!ordersToUpsert.isEmpty()) {
            upsert ordersToUpsert;
        }
    }

    public static void syncWorkOrderIds(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }

        Set<Id> serviceAppointmentIds = new Set<Id>();
        for (ServiceAppointment appointmentRecord : [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordId IN :workOrderIds
        ]) {
            serviceAppointmentIds.add(appointmentRecord.Id);
        }
        syncServiceAppointmentIds(serviceAppointmentIds, false);
    }

    public static Boolean hasRelevantServiceAppointmentChanges(ServiceAppointment newRecord, ServiceAppointment oldRecord) {
        if (newRecord == null || oldRecord == null) {
            return false;
        }
        return newRecord.ParentRecordId != oldRecord.ParentRecordId
            || newRecord.Status != oldRecord.Status
            || newRecord.ActualEndTime != oldRecord.ActualEndTime
            || newRecord.EarliestStartTime != oldRecord.EarliestStartTime
            || newRecord.SchedStartTime != oldRecord.SchedStartTime
            || newRecord.Opportunity__c != oldRecord.Opportunity__c;
    }

    public static Boolean hasRelevantWorkOrderChanges(WorkOrder newRecord, WorkOrder oldRecord) {
        if (newRecord == null || oldRecord == null) {
            return false;
        }
        return newRecord.AccountId != oldRecord.AccountId;
    }

    public static Boolean hasRelevantOpportunityWorkOrderChanges(
        Opportunity_WorkOrder__c newRecord,
        Opportunity_WorkOrder__c oldRecord
    ) {
        if (newRecord == null || oldRecord == null) {
            return false;
        }
        return newRecord.Work_Order__c != oldRecord.Work_Order__c
            || newRecord.Opportunity__c != oldRecord.Opportunity__c;
    }

    public static OrderDiaryOperationalState deriveOperationalState(
        String currentReviewStatus,
        String holdReason,
        String appointmentStatus,
        Datetime completedOn,
        Decimal invoicedAmount,
        Decimal receivedAmount
    ) {
        return deriveOperationalState(
            currentReviewStatus,
            holdReason,
            appointmentStatus,
            completedOn,
            null,
            invoicedAmount,
            receivedAmount
        );
    }

    public static OrderDiaryOperationalState deriveOperationalState(
        String currentReviewStatus,
        String holdReason,
        String appointmentStatus,
        Datetime completedOn,
        Datetime scheduledStartTime,
        Decimal invoicedAmount,
        Decimal receivedAmount
    ) {
        OrderDiaryOperationalState result = new OrderDiaryOperationalState();
        Decimal safeInvoicedAmount = invoicedAmount != null ? invoicedAmount : 0;
        Decimal safeReceivedAmount = receivedAmount != null ? receivedAmount : 0;

        if (safeInvoicedAmount > 0 || safeReceivedAmount > 0) {
            result.billingDiaryStatus = safeReceivedAmount >= safeInvoicedAmount && safeInvoicedAmount > 0
                ? OrderDiaryFinancialSyncService.getPaidStatusValue()
                : (
                    safeReceivedAmount > 0
                        ? OrderDiaryFinancialSyncService.getPartiallyPaidStatusValue()
                        : OrderDiaryFinancialSyncService.getInvoicedStatusValue()
                );
            result.readyForBilling = false;
            result.reviewStatus = currentReviewStatus;
            return result;
        }

        if (String.isNotBlank(holdReason)) {
            result.billingDiaryStatus = getOnHoldStatusValue();
            result.readyForBilling = false;
            result.reviewStatus = currentReviewStatus;
            return result;
        }

        if (isCompletedAppointment(appointmentStatus, completedOn)) {
            result.billingDiaryStatus = getReadyToBillStatusValue();
            result.readyForBilling = true;
            result.reviewStatus = currentReviewStatus;
            return result;
        }

        if (scheduledStartTime == null) {
            result.billingDiaryStatus = getDraftStatusValue();
            result.readyForBilling = false;
            result.reviewStatus = currentReviewStatus;
            return result;
        }

        result.billingDiaryStatus = getForReviewStatusValue();
        result.readyForBilling = false;
        result.reviewStatus = currentReviewStatus;
        return result;
    }

    public static String getDraftStatusValue() {
        if (cachedDraftStatus == null) {
            cachedDraftStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_DRAFT, ORDER_DIARY_STATUS_FOR_REVIEW, ORDER_DIARY_STATUS_READY_TO_BILL }
            );
        }
        return cachedDraftStatus;
    }

    public static String getForReviewStatusValue() {
        if (cachedForReviewStatus == null) {
            cachedForReviewStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_FOR_REVIEW, ORDER_DIARY_STATUS_DRAFT, ORDER_DIARY_STATUS_READY_TO_BILL }
            );
        }
        return cachedForReviewStatus;
    }

    public static String getReadyToBillStatusValue() {
        if (cachedReadyToBillStatus == null) {
            cachedReadyToBillStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_READY_TO_BILL, ORDER_DIARY_STATUS_FOR_REVIEW }
            );
        }
        return cachedReadyToBillStatus;
    }

    public static String getOnHoldStatusValue() {
        if (cachedOnHoldStatus == null) {
            cachedOnHoldStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_ON_HOLD, ORDER_DIARY_STATUS_FOR_REVIEW }
            );
        }
        return cachedOnHoldStatus;
    }

    public static String getNeedsReviewStatusValue() {
        if (cachedNeedsReviewStatus == null) {
            cachedNeedsReviewStatus = preferredPicklistValue(
                Order.Review_Status__c,
                new List<String>{ REVIEW_STATUS_NEEDS_REVIEW, REVIEW_STATUS_REVIEWED }
            );
        }
        return cachedNeedsReviewStatus;
    }

    public static String getReviewedStatusValue() {
        if (cachedReviewedStatus == null) {
            cachedReviewedStatus = preferredPicklistValue(
                Order.Review_Status__c,
                new List<String>{ REVIEW_STATUS_REVIEWED, REVIEW_STATUS_NEEDS_REVIEW }
            );
        }
        return cachedReviewedStatus;
    }

    private static String getDefaultOrderStatus() {
        if (cachedOrderStatus == null) {
            cachedOrderStatus = preferredPicklistValue(
                Order.Status,
                new List<String>{ 'Draft' }
            );
        }
        return cachedOrderStatus;
    }

    private static Id getStandardPricebookId() {
        if (cachedStandardPricebookId == null) {
            if (Test.isRunningTest()) {
                cachedStandardPricebookId = Test.getStandardPricebookId();
            } else {
                cachedStandardPricebookId = [
                    SELECT Id
                    FROM Pricebook2
                    WHERE IsStandard = true
                    LIMIT 1
                ].Id;
            }
        }
        return cachedStandardPricebookId;
    }

    private static Map<Id, Id> buildSingleOpportunityByWorkOrderId(Set<Id> workOrderIds) {
        Map<Id, Set<Id>> opportunityIdsByWorkOrderId = new Map<Id, Set<Id>>();
        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Work_Order__c, Opportunity__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c IN :workOrderIds
            AND Opportunity__c != null
        ]) {
            if (!opportunityIdsByWorkOrderId.containsKey(junctionRecord.Work_Order__c)) {
                opportunityIdsByWorkOrderId.put(junctionRecord.Work_Order__c, new Set<Id>());
            }
            opportunityIdsByWorkOrderId.get(junctionRecord.Work_Order__c).add(junctionRecord.Opportunity__c);
        }

        Map<Id, Id> results = new Map<Id, Id>();
        for (Id workOrderId : opportunityIdsByWorkOrderId.keySet()) {
            if (opportunityIdsByWorkOrderId.get(workOrderId).size() == 1) {
                for (Id opportunityId : opportunityIdsByWorkOrderId.get(workOrderId)) {
                    results.put(workOrderId, opportunityId);
                }
            }
        }
        return results;
    }

    private static String buildBillingDiaryKey(Id serviceAppointmentId, Id opportunityId) {
        return 'SA-' + String.valueOf(serviceAppointmentId) + '-OPP-' + (opportunityId == null ? 'NONE' : String.valueOf(opportunityId));
    }

    private static Boolean isCompletedAppointment(String appointmentStatus, Datetime completedOn) {
        return normalizeValue(appointmentStatus) == normalizeValue(SERVICE_APPOINTMENT_STATUS_COMPLETED) || completedOn != null;
    }

    private static String preferredPicklistValue(Schema.SObjectField fieldToken, List<String> preferredValues) {
        List<Schema.PicklistEntry> activeEntries = new List<Schema.PicklistEntry>();
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry != null && entry.isActive()) {
                activeEntries.add(entry);
            }
        }
        for (String preferredValue : preferredValues) {
            for (Schema.PicklistEntry entry : activeEntries) {
                if (normalizeValue(entry.getValue()) == normalizeValue(preferredValue)) {
                    return entry.getValue();
                }
            }
        }
        return activeEntries.isEmpty() ? null : activeEntries[0].getValue();
    }

    private static String normalizeValue(String value) {
        return String.isBlank(value) ? null : value.trim().toUpperCase();
    }
}