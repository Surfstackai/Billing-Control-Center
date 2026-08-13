trigger OpportunityWorkOrderLedger on Opportunity_WorkOrder__c (after insert, after update, after delete) {
    if (!WorkOrderLedgerAutomationControl.shouldRunSyncAutomation()) {
        return;
    }

    if (Trigger.isDelete) {
        WorkOrderLedgerService.handleOpportunityWorkOrders(null, Trigger.oldMap, true);
        return;
    }
    if (Trigger.isInsert) {
        WorkOrderLedgerService.handleOpportunityWorkOrders(Trigger.new, null, false);
        return;
    }

    List<Opportunity_WorkOrder__c> changedRecords = new List<Opportunity_WorkOrder__c>();
    for (Integer indexValue = 0; indexValue < Trigger.new.size(); indexValue++) {
        if (WorkOrderLedgerService.hasRelevantOpportunityWorkOrderChanges(Trigger.new[indexValue], Trigger.old[indexValue])) {
            changedRecords.add(Trigger.new[indexValue]);
        }
    }
    if (!changedRecords.isEmpty()) {
        WorkOrderLedgerService.handleOpportunityWorkOrders(changedRecords, Trigger.oldMap, false);
    }
}
