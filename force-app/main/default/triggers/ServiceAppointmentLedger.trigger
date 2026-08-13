trigger ServiceAppointmentLedger on ServiceAppointment (after insert, after update) {
    if (!WorkOrderLedgerAutomationControl.shouldRunSyncAutomation()) {
        return;
    }

    if (Trigger.isInsert) {
        WorkOrderLedgerService.handleServiceAppointments(Trigger.new, null);
        return;
    }

    List<ServiceAppointment> changedRecords = new List<ServiceAppointment>();
    for (Integer indexValue = 0; indexValue < Trigger.new.size(); indexValue++) {
        if (WorkOrderLedgerService.hasRelevantServiceAppointmentChanges(Trigger.new[indexValue], Trigger.old[indexValue])) {
            changedRecords.add(Trigger.new[indexValue]);
        }
    }
    if (!changedRecords.isEmpty()) {
        WorkOrderLedgerService.handleServiceAppointments(changedRecords, Trigger.oldMap);
    }
}
