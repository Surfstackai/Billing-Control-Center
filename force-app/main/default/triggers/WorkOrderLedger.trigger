trigger WorkOrderLedger on WorkOrder (before delete, after insert, after update) {
    if (Trigger.isDelete) {
        WorkOrderLedgerService.handleWorkOrderDeletes(Trigger.old);
        return;
    }

    if (!WorkOrderLedgerAutomationControl.shouldRunSyncAutomation()) {
        return;
    }

    if (Trigger.isInsert) {
        WorkOrderLedgerService.handleWorkOrders(Trigger.new, null);
        return;
    }

    List<WorkOrder> changedRecords = new List<WorkOrder>();
    for (Integer indexValue = 0; indexValue < Trigger.new.size(); indexValue++) {
        if (WorkOrderLedgerService.hasRelevantWorkOrderChanges(Trigger.new[indexValue], Trigger.old[indexValue])) {
            changedRecords.add(Trigger.new[indexValue]);
        }
    }
    if (!changedRecords.isEmpty()) {
        WorkOrderLedgerService.handleWorkOrders(changedRecords, Trigger.oldMap);
    }
}
