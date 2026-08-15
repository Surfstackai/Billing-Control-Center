/**
 * Shared Work Order parent and Opportunity attribution for billing and ledger read models.
 * Callers keep their own junction queries and eligibility rules.
 */
public inherited sharing class BillingControl_Attribution {
    public static Id resolveAttributedOpportunityId(
        ServiceAppointment appointmentRecord,
        List<Opportunity_WorkOrder__c> junctions
    ) {
        if (appointmentRecord != null && appointmentRecord.Opportunity__c != null) {
            return appointmentRecord.Opportunity__c;
        }
        Set<Id> uniqueOpportunityIds = new Set<Id>();
        if (junctions != null) {
            for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                if (junctionRecord != null && junctionRecord.Opportunity__c != null) {
                    uniqueOpportunityIds.add(junctionRecord.Opportunity__c);
                }
            }
        }
        if (uniqueOpportunityIds.size() == 1) {
            return new List<Id>(uniqueOpportunityIds)[0];
        }
        return null;
    }

    public static Map<Id, Id> resolveWorkOrderIdsForAppointments(List<ServiceAppointment> appointments) {
        Set<Id> parentIds = new Set<Id>();
        if (appointments != null) {
            for (ServiceAppointment appointmentRecord : appointments) {
                if (appointmentRecord != null && appointmentRecord.ParentRecordId != null) {
                    parentIds.add(appointmentRecord.ParentRecordId);
                }
            }
        }
        Map<Id, Id> workOrderIdByParentId = resolveWorkOrderIds(parentIds);
        Map<Id, Id> workOrderIdByAppointmentId = new Map<Id, Id>();
        if (appointments == null) {
            return workOrderIdByAppointmentId;
        }
        for (ServiceAppointment appointmentRecord : appointments) {
            if (appointmentRecord == null) {
                continue;
            }
            workOrderIdByAppointmentId.put(
                appointmentRecord.Id,
                workOrderIdByParentId.get(appointmentRecord.ParentRecordId)
            );
        }
        return workOrderIdByAppointmentId;
    }

    public static Map<Id, Id> resolveWorkOrderIds(Set<Id> parentIds) {
        Map<Id, Id> workOrderIdByParentId = new Map<Id, Id>();
        if (parentIds == null || parentIds.isEmpty()) {
            return workOrderIdByParentId;
        }
        Set<Id> lineItemIds = new Set<Id>();
        for (Id parentId : parentIds) {
            if (parentId == null) {
                continue;
            }
            if (parentId.getSObjectType() == WorkOrder.SObjectType) {
                workOrderIdByParentId.put(parentId, parentId);
            } else if (parentId.getSObjectType() == WorkOrderLineItem.SObjectType) {
                lineItemIds.add(parentId);
            }
        }
        if (!lineItemIds.isEmpty()) {
            for (WorkOrderLineItem lineItem : [
                SELECT Id, WorkOrderId
                FROM WorkOrderLineItem
                WHERE Id IN :lineItemIds
            ]) {
                if (lineItem.WorkOrderId != null) {
                    workOrderIdByParentId.put(lineItem.Id, lineItem.WorkOrderId);
                }
            }
        }
        return workOrderIdByParentId;
    }
}
