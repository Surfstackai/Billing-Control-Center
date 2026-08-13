trigger WorkOrderOrderDiary on WorkOrder (after update) {
    if (!OrderDiaryAutomationControl.shouldRunSyncAutomation()) {
        return;
    }

    Set<Id> workOrderIds = new Set<Id>();
    for (Integer indexValue = 0; indexValue < Trigger.new.size(); indexValue++) {
        WorkOrder newRecord = Trigger.new[indexValue];
        WorkOrder oldRecord = Trigger.old[indexValue];
        if (OrderDiarySyncService.hasRelevantWorkOrderChanges(newRecord, oldRecord)) {
            workOrderIds.add(newRecord.Id);
        }
    }
    OrderDiarySyncService.syncWorkOrderIds(workOrderIds);
}