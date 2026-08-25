/**
 * Shared Billing Control Center DTO types for the Work Order Ledger tab.
 * Order diary query methods were removed in Phase 6.
 */
public with sharing class BillingControl_Orders {
    public class KpiWrapper {
        @AuraEnabled public Decimal unscheduledRevenue;
        @AuraEnabled public Integer unscheduledCount;
        @AuraEnabled public Decimal scheduledRevenue;
        @AuraEnabled public Integer scheduledCount;
        @AuraEnabled public Decimal scheduledTodayRevenue;
        @AuraEnabled public Integer scheduledTodayCount;
        @AuraEnabled public Decimal completedThisWeekRevenue;
        @AuraEnabled public Integer completedThisWeekCount;
        @AuraEnabled public Decimal completedThisMonthRevenue;
        @AuraEnabled public Integer completedThisMonthCount;
        @AuraEnabled public Decimal noOpportunityRevenue;
        @AuraEnabled public Integer noOpportunityCount;
        @AuraEnabled public Decimal noServiceAppointmentRevenue;
        @AuraEnabled public Integer noServiceAppointmentCount;
        @AuraEnabled public Decimal multipleOpportunitiesRevenue;
        @AuraEnabled public Integer multipleOpportunitiesCount;
        @AuraEnabled public Decimal relatedWorkRevenue;
        @AuraEnabled public Integer relatedWorkCount;
        @AuraEnabled public Decimal completedTodayRevenue;
        @AuraEnabled public Integer completedTodayCount;
        @AuraEnabled public Decimal inProgressRevenue;
        @AuraEnabled public Integer inProgressCount;
        @AuraEnabled public Decimal completedNotBilledRevenue;
        @AuraEnabled public Integer completedNotBilledCount;
    }

    public class BucketSectionWrapper {
        @AuraEnabled public String bucketKey;
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public List<WorkOrderRowWrapper> rows;

        public BucketSectionWrapper(String bucketKeyValue, String sectionLabelValue, List<WorkOrderRowWrapper> rowValues) {
            bucketKey = bucketKeyValue;
            sectionLabel = sectionLabelValue;
            serviceAppointmentCount = 0;
            rows = rowValues;
        }
    }

    public class WorkOrderRowWrapper {
        @AuraEnabled public String rowKey;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String workTypeName;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public Decimal visitAmount;
        @AuraEnabled public String opportunityStageName;
        @AuraEnabled public Date opportunityCloseDate;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Date completedDate;
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public String serviceAppointmentStatus;
        @AuraEnabled public Datetime earliestStartTime;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime actualStartTime;
        @AuraEnabled public Datetime actualEndTime;
        @AuraEnabled public String serviceAppointmentDisplay;
        @AuraEnabled public Boolean readyForBilling;
        @AuraEnabled public Decimal invoicedAmount;
        @AuraEnabled public Decimal receivedAmount;
        @AuraEnabled public Decimal outstandingAmount;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public List<WorkOrderRowWrapper> relatedServiceAppointments;
        @AuraEnabled public Id ledgerId;
        @AuraEnabled public String workOrderStatus;
        @AuraEnabled public String reconciliationStatus;
        @AuraEnabled public Boolean attentionRequired;
        @AuraEnabled public String attentionReason;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public String depositStatus;
        @AuraEnabled public String partsStatus;
        @AuraEnabled public String invoiceNumbers;
        @AuraEnabled public Boolean billedBadge;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Date lastServiceDate;
        @AuraEnabled public Date nextServiceDate;
        @AuraEnabled public String accountOwnerName;
        @AuraEnabled public List<WorkOrderRowWrapper> relatedOpportunities;
    }

    public class TimelineEntryWrapper {
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public String eventType;
        @AuraEnabled public String eventLabel;
        @AuraEnabled public String oldValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public String changedByName;
        @AuraEnabled public String sourceObject;
        @AuraEnabled public String description;
    }
}
