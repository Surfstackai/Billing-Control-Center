public without sharing class WorkOrderLedgerService {
    public static final String EVENT_WORK_ORDER_CREATED = 'WORK_ORDER_CREATED';
    public static final String EVENT_WORK_ORDER_STATUS_CHANGED = 'WORK_ORDER_STATUS_CHANGED';
    public static final String EVENT_SA_CREATED = 'SERVICE_APPOINTMENT_CREATED';
    public static final String EVENT_SA_SCHEDULED = 'SERVICE_APPOINTMENT_SCHEDULED';
    public static final String EVENT_SA_COMPLETED = 'SERVICE_APPOINTMENT_COMPLETED';
    public static final String EVENT_SA_CANCELLED = 'SERVICE_APPOINTMENT_CANCELLED';
    public static final String EVENT_SA_MOVED = 'SERVICE_APPOINTMENT_MOVED';
    public static final String EVENT_OPPORTUNITY_LINKED = 'OPPORTUNITY_LINKED';
    public static final String EVENT_OPPORTUNITY_UNLINKED = 'OPPORTUNITY_UNLINKED';
    public static final String EVENT_DEPOSIT_RECORDED = 'DEPOSIT_RECORDED';
    public static final String EVENT_DEPOSIT_CHANGED = 'DEPOSIT_CHANGED';
    public static final String EVENT_DEPOSIT_STATUS = 'DEPOSIT_STATUS';
    public static final String EVENT_PARTS_STATUS = 'PARTS_STATUS';
    public static final String EVENT_INVOICE_NUMBER_CHANGED = 'INVOICE_NUMBER_CHANGED';

    public static final String SOURCE_WORK_ORDER = 'WorkOrder';
    public static final String SOURCE_SERVICE_APPOINTMENT = 'ServiceAppointment';
    public static final String SOURCE_OPPORTUNITY_WORK_ORDER = 'Opportunity_WorkOrder';

    public static final String STATUS_OPEN = 'Open';
    public static final String STATUS_NEEDS_REVIEW = 'Needs Review';
    public static final String STATUS_ON_HOLD = 'On Hold';
    public static final String STATUS_RECONCILED = 'Reconciled';
    public static final String STATUS_READY_FOR_BILLING_REVIEW = 'Ready for Billing Review';

    private static final String ATTENTION_NO_OPPORTUNITY = 'No Opportunity linked to this Work Order.';
    private static final String ATTENTION_UNATTRIBUTED =
        'Completed Service Appointment is not attributed on a Work Order with multiple Opportunities.';
    private static final String SA_STATUS_COMPLETED = 'Completed';

    public class LedgerEvent {
        public Id WorkOrderId;
        public Id SourceRecordId;
        public String EventType;
        public Datetime EventDatetime;
        public Id ChangedById;
        public String OldValue;
        public String NewValue;
        public Id OpportunityId;
        public Id ServiceAppointmentId;
        public Decimal Amount;
        public String SourceObject;
        public String Description;
        public String EventKey;
        public String FieldApiName;
        public Id InvoiceId;
        public Boolean IsBackfill;
        public Boolean SystemGenerated;
    }

    public static void handleWorkOrders(List<WorkOrder> newRecords, Map<Id, WorkOrder> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<LedgerEvent> events = new List<LedgerEvent>();
        Set<Id> silentRefreshIds = new Set<Id>();
        for (WorkOrder newRecord : newRecords) {
            WorkOrder oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            if (oldRecord == null) {
                events.add(
                    buildEvent(
                        newRecord.Id,
                        newRecord.Id,
                        EVENT_WORK_ORDER_CREATED,
                        newRecord.CreatedDate,
                        newRecord.CreatedById,
                        null,
                        toText(newRecord.Status),
                        SOURCE_WORK_ORDER,
                        'Work Order created.',
                        false
                    )
                );
                continue;
            }

            if (newRecord.AccountId != oldRecord.AccountId) {
                silentRefreshIds.add(newRecord.Id);
            }
            if (newRecord.Status != oldRecord.Status) {
                LedgerEvent statusEvent = buildEvent(
                    newRecord.Id,
                    newRecord.Id,
                    EVENT_WORK_ORDER_STATUS_CHANGED,
                    newRecord.LastModifiedDate,
                    newRecord.LastModifiedById,
                    toText(oldRecord.Status),
                    toText(newRecord.Status),
                    SOURCE_WORK_ORDER,
                    'Work Order Status changed from ' + nullSafe(oldRecord.Status) + ' to ' + nullSafe(newRecord.Status) + '.',
                    false
                );
                events.add(statusEvent);
            }
            if (!decimalEquals(newRecord.Deposit_Amount__c, oldRecord.Deposit_Amount__c)) {
                Boolean recorded = !hasDepositAmount(oldRecord.Deposit_Amount__c) && hasDepositAmount(newRecord.Deposit_Amount__c);
                LedgerEvent depositEvent = buildEvent(
                    newRecord.Id,
                    newRecord.Id,
                    recorded ? EVENT_DEPOSIT_RECORDED : EVENT_DEPOSIT_CHANGED,
                    newRecord.LastModifiedDate,
                    newRecord.LastModifiedById,
                    recorded ? null : toText(oldRecord.Deposit_Amount__c),
                    toText(newRecord.Deposit_Amount__c),
                    SOURCE_WORK_ORDER,
                    recorded ? 'Deposit Amount recorded.' : 'Deposit Amount changed.',
                    false
                );
                depositEvent.Amount = newRecord.Deposit_Amount__c;
                events.add(depositEvent);
            }
            if (newRecord.Deposit_Payments__c != oldRecord.Deposit_Payments__c) {
                events.add(
                    buildEvent(
                        newRecord.Id,
                        newRecord.Id,
                        EVENT_DEPOSIT_STATUS,
                        newRecord.LastModifiedDate,
                        newRecord.LastModifiedById,
                        toText(oldRecord.Deposit_Payments__c),
                        toText(newRecord.Deposit_Payments__c),
                        SOURCE_WORK_ORDER,
                        'Deposit / Payments changed from '
                            + nullSafe(oldRecord.Deposit_Payments__c)
                            + ' to '
                            + nullSafe(newRecord.Deposit_Payments__c)
                            + '.',
                        false
                    )
                );
            }
            if (newRecord.Parts_Hardware__c != oldRecord.Parts_Hardware__c) {
                events.add(
                    buildEvent(
                        newRecord.Id,
                        newRecord.Id,
                        EVENT_PARTS_STATUS,
                        newRecord.LastModifiedDate,
                        newRecord.LastModifiedById,
                        toText(oldRecord.Parts_Hardware__c),
                        toText(newRecord.Parts_Hardware__c),
                        SOURCE_WORK_ORDER,
                        'Parts / Hardware changed from '
                            + nullSafe(oldRecord.Parts_Hardware__c)
                            + ' to '
                            + nullSafe(newRecord.Parts_Hardware__c)
                            + '.',
                        false
                    )
                );
            }
            if (newRecord.Invoice_Number__c != oldRecord.Invoice_Number__c) {
                LedgerEvent invoiceEvent = buildEvent(
                    newRecord.Id,
                    newRecord.Id,
                    EVENT_INVOICE_NUMBER_CHANGED,
                    newRecord.LastModifiedDate,
                    newRecord.LastModifiedById,
                    toText(oldRecord.Invoice_Number__c),
                    toText(newRecord.Invoice_Number__c),
                    SOURCE_WORK_ORDER,
                    'Invoice Number changed.',
                    false
                );
                invoiceEvent.FieldApiName = 'Invoice_Number__c';
                events.add(invoiceEvent);
            }
        }

        persistEvents(events);
        silentRefreshIds.removeAll(collectWorkOrderIds(events));
        if (!silentRefreshIds.isEmpty()) {
            refreshLedgers(silentRefreshIds);
        }
    }

    public static void handleServiceAppointments(
        List<ServiceAppointment> newRecords,
        Map<Id, ServiceAppointment> oldMap
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Set<Id> parentIds = new Set<Id>();
        for (ServiceAppointment newRecord : newRecords) {
            if (newRecord.ParentRecordId != null) {
                parentIds.add(newRecord.ParentRecordId);
            }
            ServiceAppointment oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            if (oldRecord != null && oldRecord.ParentRecordId != null) {
                parentIds.add(oldRecord.ParentRecordId);
            }
        }
        Map<Id, Id> workOrderIdByParentId = resolveWorkOrderIds(parentIds);

        List<LedgerEvent> events = new List<LedgerEvent>();
        Set<Id> refreshOnlyIds = new Set<Id>();
        for (ServiceAppointment newRecord : newRecords) {
            ServiceAppointment oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            Id newWorkOrderId = workOrderIdByParentId.get(newRecord.ParentRecordId);
            if (newWorkOrderId == null) {
                if (newRecord.ParentRecordId != null) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Work Order Ledger skipped ServiceAppointment '
                            + newRecord.Id
                            + ' because parent '
                            + newRecord.ParentRecordId
                            + ' is not a Work Order or Work Order Line Item.'
                    );
                }
                continue;
            }

            if (oldRecord == null) {
                events.add(
                    buildServiceAppointmentEvent(
                        newWorkOrderId,
                        newRecord,
                        EVENT_SA_CREATED,
                        newRecord.CreatedDate,
                        newRecord.CreatedById,
                        null,
                        appointmentDisplayValue(newRecord),
                        'Service Appointment created.'
                    )
                );
                if (isCompletedAppointment(newRecord)) {
                    events.add(
                        buildServiceAppointmentEvent(
                            newWorkOrderId,
                            newRecord,
                            EVENT_SA_COMPLETED,
                            coalesce(newRecord.ActualEndTime, newRecord.CreatedDate),
                            newRecord.CreatedById,
                            null,
                            toText(newRecord.Status),
                            'Service Appointment completed.'
                        )
                    );
                } else if (isCancelledAppointment(newRecord)) {
                    events.add(
                        buildServiceAppointmentEvent(
                            newWorkOrderId,
                            newRecord,
                            EVENT_SA_CANCELLED,
                            newRecord.CreatedDate,
                            newRecord.CreatedById,
                            null,
                            toText(newRecord.Status),
                            'Service Appointment cancelled.'
                        )
                    );
                } else if (newRecord.SchedStartTime != null) {
                    events.add(
                        buildServiceAppointmentEvent(
                            newWorkOrderId,
                            newRecord,
                            EVENT_SA_SCHEDULED,
                            newRecord.CreatedDate,
                            newRecord.CreatedById,
                            null,
                            formatDatetime(newRecord.SchedStartTime),
                            'Service Appointment scheduled for ' + newRecord.SchedStartTime.date() + '.'
                        )
                    );
                }
                addInvoiceFieldEvents(events, newWorkOrderId, newRecord, null, false);
                continue;
            }

            Id oldWorkOrderId = workOrderIdByParentId.get(oldRecord.ParentRecordId);
            if (oldWorkOrderId != newWorkOrderId) {
                String oldParentText = toText(oldWorkOrderId);
                String newParentText = toText(newWorkOrderId);
                String movedDescription =
                    'Service Appointment moved from ' + nullSafe(oldParentText) + ' to ' + nullSafe(newParentText) + '.';
                if (oldWorkOrderId != null) {
                    LedgerEvent leftEvent = buildServiceAppointmentEvent(
                        oldWorkOrderId,
                        newRecord,
                        EVENT_SA_MOVED,
                        newRecord.LastModifiedDate,
                        newRecord.LastModifiedById,
                        oldParentText,
                        newParentText,
                        movedDescription
                    );
                    events.add(leftEvent);
                }
                LedgerEvent arrivedEvent = buildServiceAppointmentEvent(
                    newWorkOrderId,
                    newRecord,
                    EVENT_SA_MOVED,
                    newRecord.LastModifiedDate,
                    newRecord.LastModifiedById,
                    oldParentText,
                    newParentText,
                    movedDescription
                );
                events.add(arrivedEvent);
            } else if (!isCompletedAppointment(oldRecord) && isCompletedAppointment(newRecord)) {
                events.add(
                    buildServiceAppointmentEvent(
                        newWorkOrderId,
                        newRecord,
                        EVENT_SA_COMPLETED,
                        coalesce(newRecord.ActualEndTime, newRecord.LastModifiedDate),
                        newRecord.LastModifiedById,
                        toText(oldRecord.Status),
                        toText(newRecord.Status),
                        'Service Appointment completed.'
                    )
                );
            } else if (!isCancelledAppointment(oldRecord) && isCancelledAppointment(newRecord)) {
                events.add(
                    buildServiceAppointmentEvent(
                        newWorkOrderId,
                        newRecord,
                        EVENT_SA_CANCELLED,
                        newRecord.LastModifiedDate,
                        newRecord.LastModifiedById,
                        toText(oldRecord.Status),
                        toText(newRecord.Status),
                        'Service Appointment cancelled.'
                    )
                );
            } else if (newRecord.SchedStartTime != oldRecord.SchedStartTime) {
                events.add(
                    buildServiceAppointmentEvent(
                        newWorkOrderId,
                        newRecord,
                        EVENT_SA_SCHEDULED,
                        newRecord.LastModifiedDate,
                        newRecord.LastModifiedById,
                        toText(oldRecord.SchedStartTime) == null
                            ? null
                            : formatDatetime(oldRecord.SchedStartTime),
                        newRecord.SchedStartTime == null ? null : formatDatetime(newRecord.SchedStartTime),
                        newRecord.SchedStartTime == null
                            ? 'Service Appointment schedule cleared.'
                            : 'Service Appointment scheduled for ' + newRecord.SchedStartTime.date() + '.'
                    )
                );
            }

            addInvoiceFieldEvents(events, newWorkOrderId, newRecord, oldRecord, false);
            if (newRecord.Opportunity__c != oldRecord.Opportunity__c) {
                refreshOnlyIds.add(newWorkOrderId);
            }
        }

        persistEvents(events);
        refreshOnlyIds.removeAll(collectWorkOrderIds(events));
        if (!refreshOnlyIds.isEmpty()) {
            refreshLedgers(refreshOnlyIds);
        }
    }

    public static void handleOpportunityWorkOrders(
        List<Opportunity_WorkOrder__c> newRecords,
        Map<Id, Opportunity_WorkOrder__c> oldMap,
        Boolean isDelete
    ) {
        List<LedgerEvent> events = new List<LedgerEvent>();
        if (isDelete == true) {
            if (oldMap == null || oldMap.isEmpty()) {
                return;
            }
            Datetime deletedAt = System.now();
            for (Opportunity_WorkOrder__c oldRecord : oldMap.values()) {
                if (oldRecord.Work_Order__c == null) {
                    continue;
                }
                LedgerEvent unlinkEvent = buildEvent(
                    oldRecord.Work_Order__c,
                    oldRecord.Id,
                    EVENT_OPPORTUNITY_UNLINKED,
                    deletedAt,
                    oldRecord.LastModifiedById,
                    null,
                    null,
                    SOURCE_OPPORTUNITY_WORK_ORDER,
                    null,
                    false
                );
                unlinkEvent.OpportunityId = oldRecord.Opportunity__c;
                events.add(unlinkEvent);
            }
            persistEvents(events);
            return;
        }

        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        for (Opportunity_WorkOrder__c newRecord : newRecords) {
            Opportunity_WorkOrder__c oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            if (oldRecord == null) {
                if (newRecord.Work_Order__c == null) {
                    continue;
                }
                LedgerEvent linkEvent = buildEvent(
                    newRecord.Work_Order__c,
                    newRecord.Id,
                    EVENT_OPPORTUNITY_LINKED,
                    newRecord.CreatedDate,
                    newRecord.CreatedById,
                    null,
                    null,
                    SOURCE_OPPORTUNITY_WORK_ORDER,
                    null,
                    false
                );
                linkEvent.OpportunityId = newRecord.Opportunity__c;
                events.add(linkEvent);
                continue;
            }
            if (newRecord.Work_Order__c == oldRecord.Work_Order__c
                && newRecord.Opportunity__c == oldRecord.Opportunity__c) {
                continue;
            }
            Datetime changedAt = newRecord.LastModifiedDate;
            if (oldRecord.Work_Order__c != null) {
                LedgerEvent unlinkEvent = buildEvent(
                    oldRecord.Work_Order__c,
                    oldRecord.Id,
                    EVENT_OPPORTUNITY_UNLINKED,
                    changedAt,
                    newRecord.LastModifiedById,
                    null,
                    null,
                    SOURCE_OPPORTUNITY_WORK_ORDER,
                    null,
                    false
                );
                unlinkEvent.OpportunityId = oldRecord.Opportunity__c;
                events.add(unlinkEvent);
            }
            if (newRecord.Work_Order__c != null) {
                LedgerEvent linkEvent = buildEvent(
                    newRecord.Work_Order__c,
                    newRecord.Id,
                    EVENT_OPPORTUNITY_LINKED,
                    changedAt,
                    newRecord.LastModifiedById,
                    null,
                    null,
                    SOURCE_OPPORTUNITY_WORK_ORDER,
                    null,
                    false
                );
                linkEvent.OpportunityId = newRecord.Opportunity__c;
                events.add(linkEvent);
            }
        }
        persistEvents(events);
    }

    public static void persistEvents(List<LedgerEvent> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<LedgerEvent> validEvents = new List<LedgerEvent>();
        Set<Id> workOrderIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        for (LedgerEvent eventRecord : events) {
            if (eventRecord == null || eventRecord.WorkOrderId == null || String.isBlank(eventRecord.EventType)) {
                continue;
            }
            if (eventRecord.EventDatetime == null) {
                if (eventRecord.IsBackfill == true) {
                    continue;
                }
                eventRecord.EventDatetime = System.now();
            }
            if (eventRecord.SourceRecordId == null) {
                eventRecord.SourceRecordId = eventRecord.WorkOrderId;
            }
            if (String.isBlank(eventRecord.EventKey)) {
                eventRecord.EventKey = buildEventKey(eventRecord);
            }
            if (eventRecord.EventKey != null && eventRecord.EventKey.length() > 80) {
                eventRecord.EventKey = eventRecord.EventKey.substring(0, 80);
            }
            validEvents.add(eventRecord);
            workOrderIds.add(eventRecord.WorkOrderId);
            if (eventRecord.OpportunityId != null) {
                opportunityIds.add(eventRecord.OpportunityId);
            }
        }
        if (validEvents.isEmpty()) {
            return;
        }

        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId = ensureLedgers(workOrderIds);
        Map<Id, Integer> opportunityCountByWorkOrderId = queryOpportunityCounts(workOrderIds);
        Map<Id, String> opportunityNameById = queryOpportunityNames(opportunityIds);

        Set<String> eventKeys = new Set<String>();
        for (LedgerEvent eventRecord : validEvents) {
            eventKeys.add(eventRecord.EventKey);
        }
        Set<String> existingKeys = new Set<String>();
        for (Work_Order_Ledger_Entry__c existingEntry : [
            SELECT Event_Key__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Key__c IN :eventKeys
        ]) {
            existingKeys.add(existingEntry.Event_Key__c);
        }

        List<Work_Order_Ledger_Entry__c> entriesToInsert = new List<Work_Order_Ledger_Entry__c>();
        for (LedgerEvent eventRecord : validEvents) {
            if (existingKeys.contains(eventRecord.EventKey)) {
                continue;
            }
            existingKeys.add(eventRecord.EventKey);
            Work_Order_Ledger__c ledgerRecord = ledgerByWorkOrderId.get(eventRecord.WorkOrderId);
            if (ledgerRecord == null) {
                continue;
            }
            Id changedById = eventRecord.ChangedById;
            if (changedById == null && eventRecord.IsBackfill != true) {
                changedById = UserInfo.getUserId();
            }
            String opportunityName = opportunityNameById.get(eventRecord.OpportunityId);
            if (String.isBlank(eventRecord.NewValue)
                && eventRecord.EventType == EVENT_OPPORTUNITY_LINKED
                && String.isNotBlank(opportunityName)) {
                eventRecord.NewValue = opportunityName;
            }
            String description = eventRecord.Description;
            if (String.isBlank(description)) {
                description = buildDefaultDescription(
                    eventRecord,
                    opportunityName,
                    opportunityCountByWorkOrderId.get(eventRecord.WorkOrderId)
                );
            }
            entriesToInsert.add(
                new Work_Order_Ledger_Entry__c(
                    Work_Order_Ledger__c = ledgerRecord.Id,
                    Event_Datetime__c = eventRecord.EventDatetime,
                    Event_Type__c = eventRecord.EventType,
                    Description__c = description,
                    Changed_By__c = changedById,
                    Old_Value__c = clip(eventRecord.OldValue),
                    New_Value__c = clip(eventRecord.NewValue),
                    Source_Object__c = eventRecord.SourceObject,
                    Source_Record_Id__c = toText(eventRecord.SourceRecordId),
                    Service_Appointment__c = eventRecord.ServiceAppointmentId,
                    Opportunity__c = eventRecord.OpportunityId,
                    Invoice__c = eventRecord.InvoiceId,
                    Amount__c = eventRecord.Amount,
                    System_Generated__c = eventRecord.SystemGenerated == null ? true : eventRecord.SystemGenerated,
                    Event_Key__c = eventRecord.EventKey
                )
            );
        }
        if (!entriesToInsert.isEmpty()) {
            insert entriesToInsert;
        }
        refreshLedgers(workOrderIds, ledgerByWorkOrderId);
    }

    public static void refreshLedgers(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }
        refreshLedgers(workOrderIds, ensureLedgers(workOrderIds));
    }

    private static void refreshLedgers(Set<Id> workOrderIds, Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId) {
        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>([
            SELECT Id, AccountId
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
        Map<Id, List<ServiceAppointment>> appointmentsByWorkOrderId = queryAppointmentsByWorkOrderId(workOrderIds);
        Map<Id, Integer> opportunityCountByWorkOrderId = queryOpportunityCounts(workOrderIds);

        Set<Id> ledgerIds = new Set<Id>();
        for (Work_Order_Ledger__c ledgerRecord : ledgerByWorkOrderId.values()) {
            ledgerIds.add(ledgerRecord.Id);
        }
        Map<Id, Datetime> lastActivityByLedgerId = new Map<Id, Datetime>();
        if (!ledgerIds.isEmpty()) {
            for (AggregateResult aggregateRecord : [
                SELECT Work_Order_Ledger__c ledgerId, MAX(Event_Datetime__c) lastEvent
                FROM Work_Order_Ledger_Entry__c
                WHERE Work_Order_Ledger__c IN :ledgerIds
                GROUP BY Work_Order_Ledger__c
            ]) {
                lastActivityByLedgerId.put(
                    (Id) aggregateRecord.get('ledgerId'),
                    (Datetime) aggregateRecord.get('lastEvent')
                );
            }
        }

        List<Work_Order_Ledger__c> ledgersToUpdate = new List<Work_Order_Ledger__c>();
        for (Id workOrderId : workOrderIds) {
            Work_Order_Ledger__c existingLedger = ledgerByWorkOrderId.get(workOrderId);
            if (existingLedger == null) {
                continue;
            }
            List<ServiceAppointment> appointments = appointmentsByWorkOrderId.containsKey(workOrderId)
                ? appointmentsByWorkOrderId.get(workOrderId)
                : new List<ServiceAppointment>();
            Integer opportunityCount = opportunityCountByWorkOrderId.containsKey(workOrderId)
                ? opportunityCountByWorkOrderId.get(workOrderId)
                : 0;
            Date lastServiceDate;
            Date nextServiceDate;
            Integer completedCount = 0;
            Boolean hasUnattributedCompleted = false;
            for (ServiceAppointment appointmentRecord : appointments) {
                if (isCompletedAppointment(appointmentRecord)) {
                    completedCount++;
                    if (appointmentRecord.ActualEndTime != null) {
                        Date completedDate = appointmentRecord.ActualEndTime.date();
                        if (lastServiceDate == null || completedDate > lastServiceDate) {
                            lastServiceDate = completedDate;
                        }
                    }
                    if (opportunityCount > 1 && appointmentRecord.Opportunity__c == null) {
                        hasUnattributedCompleted = true;
                    }
                } else if (!isCancelledAppointment(appointmentRecord) && appointmentRecord.SchedStartTime != null) {
                    Date scheduledDate = appointmentRecord.SchedStartTime.date();
                    if (scheduledDate >= Date.today() && (nextServiceDate == null || scheduledDate < nextServiceDate)) {
                        nextServiceDate = scheduledDate;
                    }
                }
            }

            Boolean attentionRequired = (opportunityCount == 0 && completedCount > 0) || hasUnattributedCompleted;
            String attentionReason = null;
            if (opportunityCount == 0 && completedCount > 0) {
                attentionReason = ATTENTION_NO_OPPORTUNITY;
            } else if (hasUnattributedCompleted) {
                attentionReason = ATTENTION_UNATTRIBUTED;
            }

            String reconciliationStatus = existingLedger.Reconciliation_Status__c;
            if (String.isBlank(reconciliationStatus)) {
                reconciliationStatus = STATUS_OPEN;
            }
            Boolean preserveHoldOrClosed =
                reconciliationStatus == STATUS_ON_HOLD
                || reconciliationStatus == STATUS_RECONCILED
                || reconciliationStatus == STATUS_READY_FOR_BILLING_REVIEW;
            if (attentionRequired && !preserveHoldOrClosed) {
                reconciliationStatus = STATUS_NEEDS_REVIEW;
            } else if (!attentionRequired && reconciliationStatus == STATUS_NEEDS_REVIEW) {
                reconciliationStatus = STATUS_OPEN;
            }

            WorkOrder workOrderRecord = workOrderById.get(workOrderId);
            Work_Order_Ledger__c updateRecord = new Work_Order_Ledger__c(
                Id = existingLedger.Id,
                Account__c = workOrderRecord == null ? existingLedger.Account__c : workOrderRecord.AccountId,
                Service_Appointment_Count__c = appointments.size(),
                Opportunity_Count__c = opportunityCount,
                Last_Service_Date__c = lastServiceDate,
                Next_Service_Date__c = nextServiceDate,
                Last_Material_Activity__c = lastActivityByLedgerId.get(existingLedger.Id),
                Attention_Required__c = attentionRequired,
                Attention_Reason__c = attentionReason,
                Reconciliation_Status__c = reconciliationStatus
            );
            ledgersToUpdate.add(updateRecord);
        }
        if (!ledgersToUpdate.isEmpty()) {
            update ledgersToUpdate;
        }
    }

    public static void backfillWorkOrders(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }

        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>([
            SELECT Id,
                AccountId,
                Status,
                CreatedDate,
                CreatedById,
                LastModifiedDate,
                LastModifiedById,
                Deposit_Amount__c,
                Deposit_Payments__c,
                Parts_Hardware__c,
                Invoice_Number__c
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
        if (workOrderById.isEmpty()) {
            return;
        }

        Map<Id, List<ServiceAppointment>> appointmentsByWorkOrderId = queryAppointmentsByWorkOrderId(workOrderIds);
        List<LedgerEvent> events = new List<LedgerEvent>();
        for (WorkOrder workOrderRecord : workOrderById.values()) {
            events.add(
                buildEvent(
                    workOrderRecord.Id,
                    workOrderRecord.Id,
                    EVENT_WORK_ORDER_CREATED,
                    workOrderRecord.CreatedDate,
                    workOrderRecord.CreatedById,
                    null,
                    null,
                    SOURCE_WORK_ORDER,
                    'Work Order created.',
                    true
                )
            );
            if (hasDepositAmount(workOrderRecord.Deposit_Amount__c)) {
                LedgerEvent depositEvent = buildEvent(
                    workOrderRecord.Id,
                    workOrderRecord.Id,
                    EVENT_DEPOSIT_RECORDED,
                    workOrderRecord.CreatedDate,
                    workOrderRecord.LastModifiedById,
                    null,
                    toText(workOrderRecord.Deposit_Amount__c),
                    SOURCE_WORK_ORDER,
                    'Deposit Amount recorded.',
                    true
                );
                depositEvent.Amount = workOrderRecord.Deposit_Amount__c;
                events.add(depositEvent);
            }
            if (isMaterialDepositStatus(workOrderRecord.Deposit_Payments__c)) {
                events.add(
                    buildEvent(
                        workOrderRecord.Id,
                        workOrderRecord.Id,
                        EVENT_DEPOSIT_STATUS,
                        workOrderRecord.CreatedDate,
                        workOrderRecord.LastModifiedById,
                        null,
                        toText(workOrderRecord.Deposit_Payments__c),
                        SOURCE_WORK_ORDER,
                        'Deposit / Payments set to ' + workOrderRecord.Deposit_Payments__c + '.',
                        true
                    )
                );
            }
            if (isMaterialPartsStatus(workOrderRecord.Parts_Hardware__c)) {
                events.add(
                    buildEvent(
                        workOrderRecord.Id,
                        workOrderRecord.Id,
                        EVENT_PARTS_STATUS,
                        workOrderRecord.CreatedDate,
                        workOrderRecord.LastModifiedById,
                        null,
                        toText(workOrderRecord.Parts_Hardware__c),
                        SOURCE_WORK_ORDER,
                        'Parts / Hardware set to ' + workOrderRecord.Parts_Hardware__c + '.',
                        true
                    )
                );
            }
            if (String.isNotBlank(workOrderRecord.Invoice_Number__c)) {
                LedgerEvent invoiceEvent = buildEvent(
                    workOrderRecord.Id,
                    workOrderRecord.Id,
                    EVENT_INVOICE_NUMBER_CHANGED,
                    workOrderRecord.CreatedDate,
                    workOrderRecord.LastModifiedById,
                    null,
                    toText(workOrderRecord.Invoice_Number__c),
                    SOURCE_WORK_ORDER,
                    'Invoice Number changed.',
                    true
                );
                invoiceEvent.FieldApiName = 'Invoice_Number__c';
                events.add(invoiceEvent);
            }
        }

        for (Id workOrderId : appointmentsByWorkOrderId.keySet()) {
            for (ServiceAppointment appointmentRecord : appointmentsByWorkOrderId.get(workOrderId)) {
                events.add(
                    buildServiceAppointmentEvent(
                        workOrderId,
                        appointmentRecord,
                        EVENT_SA_CREATED,
                        appointmentRecord.CreatedDate,
                        appointmentRecord.CreatedById,
                        null,
                        appointmentDisplayValue(appointmentRecord),
                        'Service Appointment created.'
                    )
                );
                events.get(events.size() - 1).IsBackfill = true;
                if (isCompletedAppointment(appointmentRecord)) {
                    LedgerEvent completedEvent = buildServiceAppointmentEvent(
                        workOrderId,
                        appointmentRecord,
                        EVENT_SA_COMPLETED,
                        coalesce(appointmentRecord.ActualEndTime, appointmentRecord.CreatedDate),
                        appointmentRecord.LastModifiedById,
                        null,
                        toText(appointmentRecord.Status),
                        'Service Appointment completed.'
                    );
                    completedEvent.IsBackfill = true;
                    events.add(completedEvent);
                } else if (isCancelledAppointment(appointmentRecord)) {
                    LedgerEvent cancelledEvent = buildServiceAppointmentEvent(
                        workOrderId,
                        appointmentRecord,
                        EVENT_SA_CANCELLED,
                        appointmentRecord.CreatedDate,
                        appointmentRecord.LastModifiedById,
                        null,
                        toText(appointmentRecord.Status),
                        'Service Appointment cancelled.'
                    );
                    cancelledEvent.IsBackfill = true;
                    events.add(cancelledEvent);
                } else if (appointmentRecord.SchedStartTime != null) {
                    LedgerEvent scheduledEvent = buildServiceAppointmentEvent(
                        workOrderId,
                        appointmentRecord,
                        EVENT_SA_SCHEDULED,
                        appointmentRecord.CreatedDate,
                        appointmentRecord.CreatedById,
                        null,
                        formatDatetime(appointmentRecord.SchedStartTime),
                        'Service Appointment scheduled for ' + appointmentRecord.SchedStartTime.date() + '.'
                    );
                    scheduledEvent.IsBackfill = true;
                    events.add(scheduledEvent);
                }
                addInvoiceFieldEvents(events, workOrderId, appointmentRecord, null, true);
            }
        }

        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Id, Work_Order__c, Opportunity__c, CreatedDate, CreatedById
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c IN :workOrderIds
            AND Opportunity__c != null
        ]) {
            LedgerEvent linkEvent = buildEvent(
                junctionRecord.Work_Order__c,
                junctionRecord.Id,
                EVENT_OPPORTUNITY_LINKED,
                junctionRecord.CreatedDate,
                junctionRecord.CreatedById,
                null,
                null,
                SOURCE_OPPORTUNITY_WORK_ORDER,
                null,
                true
            );
            linkEvent.OpportunityId = junctionRecord.Opportunity__c;
            events.add(linkEvent);
        }

        for (LedgerEvent eventRecord : events) {
            eventRecord.IsBackfill = true;
        }
        persistEvents(events);
    }

    public static Set<String> getClosedWorkOrderStatusValues() {
        Set<String> intendedNormalized = new Set<String>{
            'CANCELED',
            'CANCELLED',
            'CLOSED',
            'BILLING COMPLETED',
            'WITHIN WARRANTY BILLING COMPLETED'
        };
        Set<String> result = new Set<String>();
        for (Schema.PicklistEntry entry : WorkOrder.Status.getDescribe().getPicklistValues()) {
            if (entry == null || !entry.isActive()) {
                continue;
            }
            String normalized = normalize(entry.getValue());
            if (normalized != null && intendedNormalized.contains(normalized)) {
                result.add(entry.getValue());
            }
        }
        return result;
    }

    public static Boolean hasRelevantWorkOrderChanges(WorkOrder newRecord, WorkOrder oldRecord) {
        if (newRecord == null || oldRecord == null) {
            return false;
        }
        return newRecord.AccountId != oldRecord.AccountId
            || newRecord.Status != oldRecord.Status
            || !decimalEquals(newRecord.Deposit_Amount__c, oldRecord.Deposit_Amount__c)
            || newRecord.Deposit_Payments__c != oldRecord.Deposit_Payments__c
            || newRecord.Parts_Hardware__c != oldRecord.Parts_Hardware__c
            || newRecord.Invoice_Number__c != oldRecord.Invoice_Number__c;
    }

    public static Boolean hasRelevantServiceAppointmentChanges(
        ServiceAppointment newRecord,
        ServiceAppointment oldRecord
    ) {
        if (newRecord == null || oldRecord == null) {
            return false;
        }
        return newRecord.ParentRecordId != oldRecord.ParentRecordId
            || newRecord.Status != oldRecord.Status
            || newRecord.SchedStartTime != oldRecord.SchedStartTime
            || newRecord.ActualEndTime != oldRecord.ActualEndTime
            || newRecord.Invoice_Number__c != oldRecord.Invoice_Number__c
            || newRecord.Opportunity__c != oldRecord.Opportunity__c;
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

    private static Map<Id, Work_Order_Ledger__c> ensureLedgers(Set<Id> workOrderIds) {
        Map<Id, Work_Order_Ledger__c> ledgerByWorkOrderId = new Map<Id, Work_Order_Ledger__c>();
        Map<String, Id> workOrderIdByKey = new Map<String, Id>();
        for (Id workOrderId : workOrderIds) {
            workOrderIdByKey.put(String.valueOf(workOrderId), workOrderId);
        }

        for (Work_Order_Ledger__c existingLedger : [
            SELECT Id,
                Work_Order__c,
                Work_Order_Key__c,
                Account__c,
                Reconciliation_Status__c,
                Attention_Required__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order_Key__c IN :workOrderIdByKey.keySet()
        ]) {
            ledgerByWorkOrderId.put(existingLedger.Work_Order__c, existingLedger);
        }

        Map<Id, WorkOrder> workOrderById = new Map<Id, WorkOrder>([
            SELECT Id, AccountId
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]);
        List<Work_Order_Ledger__c> ledgersToInsert = new List<Work_Order_Ledger__c>();
        List<Work_Order_Ledger__c> ledgersToUpdate = new List<Work_Order_Ledger__c>();
        for (Id workOrderId : workOrderIds) {
            Work_Order_Ledger__c existingLedger = ledgerByWorkOrderId.get(workOrderId);
            WorkOrder workOrderRecord = workOrderById.get(workOrderId);
            if (existingLedger == null) {
                ledgersToInsert.add(
                    new Work_Order_Ledger__c(
                        Work_Order__c = workOrderId,
                        Work_Order_Key__c = String.valueOf(workOrderId),
                        Account__c = workOrderRecord == null ? null : workOrderRecord.AccountId,
                        Reconciliation_Status__c = STATUS_OPEN
                    )
                );
            } else if (workOrderRecord != null && existingLedger.Account__c != workOrderRecord.AccountId) {
                ledgersToUpdate.add(
                    new Work_Order_Ledger__c(
                        Id = existingLedger.Id,
                        Account__c = workOrderRecord.AccountId
                    )
                );
            }
        }
        if (!ledgersToInsert.isEmpty()) {
            upsert ledgersToInsert Work_Order_Key__c;
        }
        if (!ledgersToUpdate.isEmpty()) {
            update ledgersToUpdate;
        }

        ledgerByWorkOrderId.clear();
        for (Work_Order_Ledger__c ledgerRecord : [
            SELECT Id,
                Work_Order__c,
                Work_Order_Key__c,
                Account__c,
                Reconciliation_Status__c,
                Attention_Required__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order_Key__c IN :workOrderIdByKey.keySet()
        ]) {
            ledgerByWorkOrderId.put(ledgerRecord.Work_Order__c, ledgerRecord);
        }
        return ledgerByWorkOrderId;
    }

    private static Map<Id, Id> resolveWorkOrderIds(Set<Id> parentIds) {
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

    private static Map<Id, List<ServiceAppointment>> queryAppointmentsByWorkOrderId(Set<Id> workOrderIds) {
        Map<Id, List<ServiceAppointment>> appointmentsByWorkOrderId = new Map<Id, List<ServiceAppointment>>();
        for (Id workOrderId : workOrderIds) {
            appointmentsByWorkOrderId.put(workOrderId, new List<ServiceAppointment>());
        }
        Map<Id, Id> workOrderIdByParentId = new Map<Id, Id>();
        for (Id workOrderId : workOrderIds) {
            workOrderIdByParentId.put(workOrderId, workOrderId);
        }
        for (WorkOrderLineItem lineItem : [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            WHERE WorkOrderId IN :workOrderIds
        ]) {
            workOrderIdByParentId.put(lineItem.Id, lineItem.WorkOrderId);
        }
        Set<Id> parentIds = workOrderIdByParentId.keySet();
        if (parentIds.isEmpty()) {
            return appointmentsByWorkOrderId;
        }
        for (ServiceAppointment appointmentRecord : [
            SELECT Id,
                ParentRecordId,
                Status,
                CreatedDate,
                CreatedById,
                LastModifiedDate,
                LastModifiedById,
                SchedStartTime,
                ActualEndTime,
                Opportunity__c,
                Invoice_Number__c,
                AppointmentNumber
            FROM ServiceAppointment
            WHERE ParentRecordId IN :parentIds
        ]) {
            Id workOrderId = workOrderIdByParentId.get(appointmentRecord.ParentRecordId);
            if (workOrderId == null || !appointmentsByWorkOrderId.containsKey(workOrderId)) {
                continue;
            }
            appointmentsByWorkOrderId.get(workOrderId).add(appointmentRecord);
        }
        return appointmentsByWorkOrderId;
    }

    private static Map<Id, Integer> queryOpportunityCounts(Set<Id> workOrderIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Id workOrderId : workOrderIds) {
            counts.put(workOrderId, 0);
        }
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
        for (Id workOrderId : opportunityIdsByWorkOrderId.keySet()) {
            counts.put(workOrderId, opportunityIdsByWorkOrderId.get(workOrderId).size());
        }
        return counts;
    }

    private static Map<Id, String> queryOpportunityNames(Set<Id> opportunityIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return names;
        }
        for (Opportunity opportunityRecord : [
            SELECT Id, Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]) {
            names.put(opportunityRecord.Id, opportunityRecord.Name);
        }
        return names;
    }

    private static void addInvoiceFieldEvents(
        List<LedgerEvent> events,
        Id workOrderId,
        ServiceAppointment newRecord,
        ServiceAppointment oldRecord,
        Boolean isBackfill
    ) {
        if (oldRecord == null) {
            if (String.isNotBlank(newRecord.Invoice_Number__c)) {
                LedgerEvent invoiceEvent = buildServiceAppointmentEvent(
                    workOrderId,
                    newRecord,
                    EVENT_INVOICE_NUMBER_CHANGED,
                    newRecord.CreatedDate == null ? newRecord.LastModifiedDate : newRecord.CreatedDate,
                    newRecord.CreatedById == null ? newRecord.LastModifiedById : newRecord.CreatedById,
                    null,
                    toText(newRecord.Invoice_Number__c),
                    'Invoice Number changed.'
                );
                invoiceEvent.FieldApiName = 'Invoice_Number__c';
                events.add(invoiceEvent);
            }
        } else {
            if (newRecord.Invoice_Number__c != oldRecord.Invoice_Number__c) {
                LedgerEvent invoiceEvent = buildServiceAppointmentEvent(
                    workOrderId,
                    newRecord,
                    EVENT_INVOICE_NUMBER_CHANGED,
                    newRecord.LastModifiedDate,
                    newRecord.LastModifiedById,
                    toText(oldRecord.Invoice_Number__c),
                    toText(newRecord.Invoice_Number__c),
                    'Invoice Number changed.'
                );
                invoiceEvent.FieldApiName = 'Invoice_Number__c';
                events.add(invoiceEvent);
            }
        }
        if (isBackfill == true) {
            for (Integer indexValue = 0; indexValue < events.size(); indexValue++) {
                if (events[indexValue].ServiceAppointmentId == newRecord.Id
                    && events[indexValue].EventType == EVENT_INVOICE_NUMBER_CHANGED) {
                    events[indexValue].IsBackfill = true;
                }
            }
        }
    }

    private static LedgerEvent buildServiceAppointmentEvent(
        Id workOrderId,
        ServiceAppointment appointmentRecord,
        String eventType,
        Datetime eventDatetime,
        Id changedById,
        String oldValue,
        String newValue,
        String description
    ) {
        LedgerEvent eventRecord = buildEvent(
            workOrderId,
            appointmentRecord.Id,
            eventType,
            eventDatetime,
            changedById,
            oldValue,
            newValue,
            SOURCE_SERVICE_APPOINTMENT,
            description,
            false
        );
        eventRecord.ServiceAppointmentId = appointmentRecord.Id;
        return eventRecord;
    }

    private static LedgerEvent buildEvent(
        Id workOrderId,
        Id sourceRecordId,
        String eventType,
        Datetime eventDatetime,
        Id changedById,
        String oldValue,
        String newValue,
        String sourceObject,
        String description,
        Boolean isBackfill
    ) {
        LedgerEvent eventRecord = new LedgerEvent();
        eventRecord.WorkOrderId = workOrderId;
        eventRecord.SourceRecordId = sourceRecordId;
        eventRecord.EventType = eventType;
        eventRecord.EventDatetime = eventDatetime;
        eventRecord.ChangedById = changedById;
        eventRecord.OldValue = oldValue;
        eventRecord.NewValue = newValue;
        eventRecord.SourceObject = sourceObject;
        eventRecord.Description = description;
        eventRecord.IsBackfill = isBackfill;
        eventRecord.SystemGenerated = true;
        return eventRecord;
    }

    private static String buildEventKey(LedgerEvent eventRecord) {
        Long timestampValue = eventRecord.EventDatetime.getTime();
        if (eventRecord.EventType == EVENT_INVOICE_NUMBER_CHANGED) {
            String fieldApiName = String.isBlank(eventRecord.FieldApiName) ? 'Invoice_Number__c' : eventRecord.FieldApiName;
            return eventRecord.EventType
                + ':'
                + String.valueOf(eventRecord.SourceRecordId)
                + ':'
                + fieldApiName
                + ':'
                + String.valueOf(timestampValue);
        }
        if (eventRecord.EventType == EVENT_OPPORTUNITY_UNLINKED) {
            return eventRecord.EventType
                + ':'
                + String.valueOf(eventRecord.WorkOrderId)
                + ':'
                + String.valueOf(eventRecord.OpportunityId)
                + ':'
                + String.valueOf(timestampValue);
        }
        return eventRecord.EventType
            + ':'
            + String.valueOf(eventRecord.SourceRecordId)
            + ':'
            + String.valueOf(timestampValue);
    }

    private static String buildDefaultDescription(
        LedgerEvent eventRecord,
        String opportunityName,
        Integer opportunityCount
    ) {
        if (eventRecord.EventType == EVENT_OPPORTUNITY_LINKED) {
            return 'Opportunity '
                + nullSafe(opportunityName)
                + ' linked to Work Order. Work Order now has '
                + String.valueOf(opportunityCount == null ? 0 : opportunityCount)
                + ' Opportunities.';
        }
        if (eventRecord.EventType == EVENT_OPPORTUNITY_UNLINKED) {
            return 'Opportunity '
                + nullSafe(opportunityName)
                + ' unlinked from Work Order. Work Order now has '
                + String.valueOf(opportunityCount == null ? 0 : opportunityCount)
                + ' Opportunities.';
        }
        return eventRecord.EventType.replace('_', ' ').toLowerCase() + '.';
    }

    private static Set<Id> collectWorkOrderIds(List<LedgerEvent> events) {
        Set<Id> workOrderIds = new Set<Id>();
        if (events == null) {
            return workOrderIds;
        }
        for (LedgerEvent eventRecord : events) {
            if (eventRecord != null && eventRecord.WorkOrderId != null) {
                workOrderIds.add(eventRecord.WorkOrderId);
            }
        }
        return workOrderIds;
    }

    private static Boolean isCompletedAppointment(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null) {
            return false;
        }
        return normalize(appointmentRecord.Status) == normalize(SA_STATUS_COMPLETED)
            || appointmentRecord.ActualEndTime != null;
    }

    private static Boolean isCancelledAppointment(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null) {
            return false;
        }
        String normalized = normalize(appointmentRecord.Status);
        return normalized == 'CANCELED' || normalized == 'CANCELLED';
    }

    private static Boolean hasDepositAmount(Decimal amount) {
        return amount != null && amount != 0;
    }

    private static Boolean decimalEquals(Decimal leftValue, Decimal rightValue) {
        if (leftValue == null && rightValue == null) {
            return true;
        }
        if (leftValue == null || rightValue == null) {
            return false;
        }
        return leftValue == rightValue;
    }

    private static String toText(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return clip(((Decimal) value).stripTrailingZeros().toPlainString());
        }
        return clip(String.valueOf(value));
    }

    private static String clip(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > 255 ? value.substring(0, 255) : value;
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? '' : value;
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim().toUpperCase();
    }

    private static String appointmentDisplayValue(ServiceAppointment appointmentRecord) {
        if (appointmentRecord == null) {
            return null;
        }
        if (String.isNotBlank(appointmentRecord.AppointmentNumber)) {
            return appointmentRecord.AppointmentNumber;
        }
        return toText(appointmentRecord.Id);
    }

    private static String formatDatetime(Datetime value) {
        return value == null ? null : value.format('MMM d h:mm a');
    }

    private static Boolean isMaterialDepositStatus(String value) {
        String normalized = normalize(value);
        return normalized != null && normalized != 'NO DEPOSIT REQUIRED';
    }

    private static Boolean isMaterialPartsStatus(String value) {
        String normalized = normalize(value);
        return normalized != null && normalized != 'NO PARTS REQUIRED';
    }

    private static Datetime coalesce(Datetime firstValue, Datetime secondValue) {
        return firstValue != null ? firstValue : secondValue;
    }
}
