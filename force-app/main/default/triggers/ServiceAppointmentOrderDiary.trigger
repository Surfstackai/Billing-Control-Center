trigger ServiceAppointmentOrderDiary on ServiceAppointment (after insert, after update) {
    if (!OrderDiaryAutomationControl.shouldRunSyncAutomation()) {
        return;
    }

    Set<Id> serviceAppointmentIds = new Set<Id>();
    Boolean allowCreate = Trigger.isInsert;
    if (Trigger.isInsert) {
        for (ServiceAppointment appointmentRecord : Trigger.new) {
            serviceAppointmentIds.add(appointmentRecord.Id);
        }
    } else if (Trigger.isUpdate) {
        for (Integer indexValue = 0; indexValue < Trigger.new.size(); indexValue++) {
            ServiceAppointment newRecord = Trigger.new[indexValue];
            ServiceAppointment oldRecord = Trigger.old[indexValue];
            if (OrderDiarySyncService.hasRelevantServiceAppointmentChanges(newRecord, oldRecord)) {
                serviceAppointmentIds.add(newRecord.Id);
            }
        }
    }
    OrderDiarySyncService.syncServiceAppointmentIds(serviceAppointmentIds, allowCreate);
}