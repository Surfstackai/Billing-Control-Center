@IsTest
private class WorkOrderLedgerServiceTest {
    @IsTest
    static void persistEventsUpsertsOneLedgerAndIsIdempotent() {
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Idempotent WO');

        WorkOrderLedgerService.LedgerEvent createdEvent = newEvent(
            workOrderRecord.Id,
            WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED,
            workOrderRecord.CreatedDate,
            workOrderRecord.CreatedById,
            false
        );
        WorkOrderLedgerService.persistEvents(
            new List<WorkOrderLedgerService.LedgerEvent>{ createdEvent }
        );
        WorkOrderLedgerService.persistEvents(
            new List<WorkOrderLedgerService.LedgerEvent>{ createdEvent }
        );

        List<Work_Order_Ledger__c> ledgers = [
            SELECT Work_Order_Key__c, Account__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(1, ledgers.size());
        System.assertEquals(String.valueOf(workOrderRecord.Id), ledgers[0].Work_Order_Key__c);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Work_Order_Ledger_Entry__c
            WHERE Work_Order_Ledger__c = :ledgers[0].Id
        ]);
    }

    @IsTest
    static void accountChangeUpdatesLookupWithoutDiaryEntry() {
        WorkOrderLedgerAutomationControl.enableForTests();
        Account firstAccount = new Account(Name = 'Ledger Account A');
        Account secondAccount = new Account(Name = 'Ledger Account B');
        insert new List<Account>{ firstAccount, secondAccount };
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Account WO', firstAccount.Id);

        workOrderRecord.AccountId = secondAccount.Id;
        update workOrderRecord;

        Work_Order_Ledger__c ledgerRecord = [
            SELECT Account__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(secondAccount.Id, ledgerRecord.Account__c);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Work_Order_Ledger__c = :ledgerRecord.Id
                AND Event_Type__c != :WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED
            ]
        );
    }

    @IsTest
    static void woliParentedAppointmentAttachesToWorkOrderLedger() {
        WorkOrder workOrderRecord = insertWorkOrder('Ledger WOLI WO');
        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = workOrderRecord.Id);
        insert lineItem;
        ServiceAppointment appointmentRecord = insertAppointment(lineItem.Id, 'None', null, null);

        WorkOrderLedgerService.handleServiceAppointments(
            new List<ServiceAppointment>{ appointmentRecord },
            null
        );

        Work_Order_Ledger__c ledgerRecord = [
            SELECT Service_Appointment_Count__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(1, ledgerRecord.Service_Appointment_Count__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_SA_CREATED
                AND Service_Appointment__c = :appointmentRecord.Id
            ]
        );
    }

    @IsTest
    static void depositAndPartsEventsStoreOldNewAndCycleTwice() {
        WorkOrderLedgerAutomationControl.enableForTests();
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Deposit WO');

        List<String> partsValues = firstTwoPicklistValues(WorkOrder.Parts_Hardware__c);
        List<String> depositStatusValues = firstTwoPicklistValues(WorkOrder.Deposit_Payments__c);

        workOrderRecord.Deposit_Amount__c = 2500;
        update workOrderRecord;
        workOrderRecord.Deposit_Amount__c = 5000;
        update workOrderRecord;

        if (partsValues.size() >= 2) {
            Datetime firstChanged = System.now().addDays(-4);
            Datetime secondChanged = System.now().addDays(-3);
            Datetime thirdChanged = System.now().addDays(-2);
            Datetime fourthChanged = System.now().addDays(-1);
            WorkOrderLedgerService.persistEvents(
                new List<WorkOrderLedgerService.LedgerEvent>{
                    partsEvent(workOrderRecord.Id, firstChanged, null, partsValues[0]),
                    partsEvent(workOrderRecord.Id, secondChanged, partsValues[0], partsValues[1]),
                    partsEvent(workOrderRecord.Id, thirdChanged, partsValues[1], partsValues[0]),
                    partsEvent(workOrderRecord.Id, fourthChanged, partsValues[0], partsValues[1])
                }
            );
        }
        if (depositStatusValues.size() >= 2) {
            WorkOrderLedgerService.LedgerEvent statusEvent = newEvent(
                workOrderRecord.Id,
                WorkOrderLedgerService.EVENT_DEPOSIT_STATUS,
                System.now().addDays(-5),
                UserInfo.getUserId(),
                false
            );
            statusEvent.OldValue = depositStatusValues[0];
            statusEvent.NewValue = depositStatusValues[1];
            statusEvent.Description =
                'Deposit / Payments changed from '
                + depositStatusValues[0]
                + ' to '
                + depositStatusValues[1]
                + '.';
            WorkOrderLedgerService.persistEvents(
                new List<WorkOrderLedgerService.LedgerEvent>{ statusEvent }
            );
        }

        Work_Order_Ledger_Entry__c recorded = [
            SELECT Old_Value__c, New_Value__c, Amount__c, Description__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_DEPOSIT_RECORDED
            LIMIT 1
        ];
        System.assertEquals(null, recorded.Old_Value__c);
        System.assertEquals('2500', recorded.New_Value__c);
        System.assertEquals(2500, recorded.Amount__c);
        System.assertEquals(false, recorded.Description__c.contains(UserInfo.getName()));

        Work_Order_Ledger_Entry__c changed = [
            SELECT Old_Value__c, New_Value__c, Amount__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_DEPOSIT_CHANGED
            LIMIT 1
        ];
        System.assertEquals('2500', changed.Old_Value__c);
        System.assertEquals('5000', changed.New_Value__c);
        System.assertEquals(5000, changed.Amount__c);

        if (partsValues.size() >= 2) {
            System.assertEquals(
                4,
                [
                    SELECT COUNT()
                    FROM Work_Order_Ledger_Entry__c
                    WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_PARTS_STATUS
                ]
            );
        }
    }

    @IsTest
    static void changedByUsesEventPayloadAndBackfillDoesNotUseRunningUser() {
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Changed By WO');
        User otherUser = createUser('ldgr');

        WorkOrderLedgerService.LedgerEvent liveEvent = newEvent(
            workOrderRecord.Id,
            WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED,
            System.now().addDays(-10),
            otherUser.Id,
            false
        );
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>{ liveEvent });
        Work_Order_Ledger_Entry__c liveEntry = [
            SELECT Changed_By__c, Event_Datetime__c, Description__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED
            LIMIT 1
        ];
        System.assertEquals(otherUser.Id, liveEntry.Changed_By__c);
        System.assertEquals(false, liveEntry.Description__c.contains(UserInfo.getName()));

        WorkOrderLedgerService.LedgerEvent fallbackEvent = newEvent(
            workOrderRecord.Id,
            WorkOrderLedgerService.EVENT_WORK_ORDER_STATUS_CHANGED,
            System.now().addDays(-9),
            null,
            false
        );
        fallbackEvent.OldValue = 'Open';
        fallbackEvent.NewValue = 'Review';
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>{ fallbackEvent });
        System.assertEquals(
            UserInfo.getUserId(),
            [
                SELECT Changed_By__c
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_WORK_ORDER_STATUS_CHANGED
                LIMIT 1
            ]
            .Changed_By__c
        );

        WorkOrderLedgerService.LedgerEvent backfillEvent = newEvent(
            workOrderRecord.Id,
            'ACCOUNTING_NOTE',
            System.now().addDays(-8),
            null,
            true
        );
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>{ backfillEvent });
        System.assertEquals(
            null,
            [
                SELECT Changed_By__c
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = 'ACCOUNTING_NOTE'
                LIMIT 1
            ]
            .Changed_By__c
        );

        Work_Order_Ledger__c ledgerRecord = [
            SELECT Last_Material_Activity__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        Datetime maxEventTime = [
            SELECT Event_Datetime__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Work_Order_Ledger__c = :ledgerRecord.Id
            ORDER BY Event_Datetime__c DESC
            LIMIT 1
        ]
        .Event_Datetime__c;
        System.assertEquals(maxEventTime, ledgerRecord.Last_Material_Activity__c);
        System.assertEquals(liveEvent.EventDatetime, [
            SELECT Event_Datetime__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED
            LIMIT 1
        ]
        .Event_Datetime__c);
        System.assertEquals(
            true,
            ledgerRecord.Last_Material_Activity__c.date() < Date.today()
                || [
                    SELECT CreatedDate
                    FROM Work_Order_Ledger_Entry__c
                    WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED
                    LIMIT 1
                ]
                .CreatedDate != liveEvent.EventDatetime
        );
    }

    @IsTest
    static void opportunityLinkUnlinkAndUniqueKeyCoexist() {
        WorkOrderLedgerAutomationControl.enableForTests();
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Junction WO');
        Opportunity firstOpportunity = insertOpportunity('Ledger Opp One');
        Opportunity secondOpportunity = insertOpportunity('Ledger Opp Two');

        Opportunity_WorkOrder__c firstJunction = new Opportunity_WorkOrder__c(
            Work_Order__c = workOrderRecord.Id,
            Opportunity__c = firstOpportunity.Id
        );
        insert firstJunction;
        Opportunity_WorkOrder__c stamped = [
            SELECT Unique_Key__c
            FROM Opportunity_WorkOrder__c
            WHERE Id = :firstJunction.Id
        ];
        System.assertEquals(true, String.isNotBlank(stamped.Unique_Key__c));

        insert new Opportunity_WorkOrder__c(
            Work_Order__c = workOrderRecord.Id,
            Opportunity__c = secondOpportunity.Id
        );
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_OPPORTUNITY_LINKED
            ]
        );

        Work_Order_Ledger__c ledgerAfterLinks = [
            SELECT Opportunity_Count__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(2, ledgerAfterLinks.Opportunity_Count__c);

        Boolean sawLinkedDescription = false;
        for (Work_Order_Ledger_Entry__c linkEntry : [
            SELECT Description__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_OPPORTUNITY_LINKED
        ]) {
            System.assertEquals(
                false,
                linkEntry.Description__c != null && linkEntry.Description__c.contains(UserInfo.getName())
            );
            if (linkEntry.Description__c != null && linkEntry.Description__c.contains('linked to Work Order')) {
                sawLinkedDescription = true;
            }
        }
        System.assertEquals(true, sawLinkedDescription);

        Opportunity thirdOpportunity = insertOpportunity('Ledger Opp Three');
        firstJunction.Opportunity__c = thirdOpportunity.Id;
        update firstJunction;

        delete firstJunction;
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_OPPORTUNITY_UNLINKED
            ]
        );

        firstOpportunity.StageName = 'Prospecting';
        firstOpportunity.CloseDate = Date.today().addDays(10);
        update firstOpportunity;
        Set<String> expectedEventTypes = new Set<String>{
            WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED,
            WorkOrderLedgerService.EVENT_OPPORTUNITY_LINKED,
            WorkOrderLedgerService.EVENT_OPPORTUNITY_UNLINKED
        };
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c NOT IN :expectedEventTypes
            ]
        );
    }

    @IsTest
    static void unattributedCompletedAppointmentSetsAttention() {
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Attention WO');
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrderRecord.Id,
                Opportunity__c = insertOpportunity('Ledger Attn Opp 1').Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrderRecord.Id,
                Opportunity__c = insertOpportunity('Ledger Attn Opp 2').Id
            )
        };
        Datetime completedOn = System.now().addDays(-1);
        ServiceAppointment appointmentRecord = insertAppointment(
            workOrderRecord.Id,
            'Completed',
            completedOn.addHours(-1),
            completedOn
        );

        WorkOrderLedgerService.handleServiceAppointments(
            new List<ServiceAppointment>{ appointmentRecord },
            null
        );

        Work_Order_Ledger__c ledgerRecord = [
            SELECT Attention_Required__c, Attention_Reason__c, Reconciliation_Status__c, Opportunity_Count__c
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(2, ledgerRecord.Opportunity_Count__c);
        System.assertEquals(true, ledgerRecord.Attention_Required__c);
        System.assertEquals(WorkOrderLedgerService.STATUS_NEEDS_REVIEW, ledgerRecord.Reconciliation_Status__c);
        System.assertEquals(true, ledgerRecord.Attention_Reason__c.contains('not attributed'));
    }

    @IsTest
    static void invoiceNumberChangesDoNotInsertInvoice() {
        WorkOrderLedgerAutomationControl.enableForTests();
        WorkOrder workOrderRecord = insertWorkOrder('Ledger Invoice WO');
        Integer invoiceCountBefore = [SELECT COUNT() FROM Invoice__c];
        workOrderRecord.Invoice_Number__c = 'INV-1001';
        update workOrderRecord;

        ServiceAppointment appointmentRecord = insertAppointment(workOrderRecord.Id, 'None', null, null);
        appointmentRecord.Invoice_Number__c = 'INV-SA-1';
        update appointmentRecord;

        System.assertEquals(invoiceCountBefore, [SELECT COUNT() FROM Invoice__c]);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Work_Order_Ledger_Entry__c
                WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_INVOICE_NUMBER_CHANGED
                AND Source_Object__c = :WorkOrderLedgerService.SOURCE_WORK_ORDER
            ]
        );
        Integer saInvoiceEvents = [
            SELECT COUNT()
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_INVOICE_NUMBER_CHANGED
            AND Source_Object__c = :WorkOrderLedgerService.SOURCE_SERVICE_APPOINTMENT
        ];
        System.assertEquals(true, saInvoiceEvents >= 1);
    }

    @IsTest
    static void backfillUsesHistoricalUserAndRerunDoesNotDuplicate() {
        User sourceUser = createUser('lsrc');
        User batchUser = createUser('lbch');
        WorkOrder workOrderRecord;
        System.runAs(sourceUser) {
            workOrderRecord = insertWorkOrder('Ledger Backfill WO');
            workOrderRecord.Deposit_Amount__c = 150;
            workOrderRecord.Invoice_Number__c = 'INV-BF-1';
            update workOrderRecord;
        }

        System.runAs(batchUser) {
            Test.startTest();
            Database.executeBatch(new WorkOrderLedgerBackfillBatch(new Set<Id>{ workOrderRecord.Id }), 1);
            Test.stopTest();
        }

        Work_Order_Ledger_Entry__c createdEntry = [
            SELECT Changed_By__c, Event_Datetime__c, CreatedDate
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :WorkOrderLedgerService.EVENT_WORK_ORDER_CREATED
            AND Source_Record_Id__c = :String.valueOf(workOrderRecord.Id)
            LIMIT 1
        ];
        System.assertEquals(sourceUser.Id, createdEntry.Changed_By__c);
        System.assertNotEquals(batchUser.Id, createdEntry.Changed_By__c);

        Integer entryCount = [SELECT COUNT() FROM Work_Order_Ledger_Entry__c];
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });
        System.assertEquals(entryCount, [SELECT COUNT() FROM Work_Order_Ledger_Entry__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order_Ledger__c WHERE Work_Order__c = :workOrderRecord.Id]);
    }

    @IsTest
    static void triggersAndControlAndClosedStatuses() {
        WorkOrderLedgerAutomationControl.disableForTests();
        System.assertEquals(false, WorkOrderLedgerAutomationControl.shouldRunSyncAutomation());
        WorkOrderLedgerAutomationControl.enableForTests();
        System.assertEquals(true, WorkOrderLedgerAutomationControl.shouldRunSyncAutomation());
        System.assertEquals(true, WorkOrderLedgerAutomationControl.shouldRun());
        insert new Billing_Center_Global_Setting__c(
            Label__c = 'Ledger Automation Test',
            Developer_Key__c = 'ledger-auto-' + String.valueOf(Datetime.now().getTime()),
            Is_Active__c = true,
            Disable_Work_Order_Ledger_Automation__c = true
        );
        System.assertEquals(true, WorkOrderLedgerAutomationControl.isSyncAutomationDisabledBySetting());

        WorkOrder workOrderRecord = insertWorkOrder('Ledger Trigger WO');
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order_Ledger__c WHERE Work_Order__c = :workOrderRecord.Id]);
        String nextStatus = secondOpenWorkOrderStatus(workOrderRecord.Status);
        if (nextStatus != null) {
            workOrderRecord.Status = nextStatus;
            update workOrderRecord;
        }
        ServiceAppointment appointmentRecord = insertAppointment(workOrderRecord.Id, 'None', System.now().addDays(1), null);
        ServiceAppointment previousAppointment = new ServiceAppointment(
            Id = appointmentRecord.Id,
            ParentRecordId = appointmentRecord.ParentRecordId,
            Status = appointmentRecord.Status,
            SchedStartTime = appointmentRecord.SchedStartTime,
            ActualEndTime = appointmentRecord.ActualEndTime
        );
        appointmentRecord.Status = cancelledAppointmentStatus();
        WorkOrderLedgerService.handleServiceAppointments(
            new List<ServiceAppointment>{ appointmentRecord },
            new Map<Id, ServiceAppointment>{ appointmentRecord.Id => previousAppointment }
        );
        WorkOrder destinationWorkOrder = insertWorkOrder('Ledger Move Dest WO');
        previousAppointment.Status = appointmentRecord.Status;
        appointmentRecord.ParentRecordId = destinationWorkOrder.Id;
        WorkOrderLedgerService.handleServiceAppointments(
            new List<ServiceAppointment>{ appointmentRecord },
            new Map<Id, ServiceAppointment>{ appointmentRecord.Id => previousAppointment }
        );

        System.assertEquals(
            false,
            WorkOrderLedgerService.hasRelevantWorkOrderChanges(workOrderRecord, workOrderRecord)
        );
        System.assertEquals(
            false,
            WorkOrderLedgerService.hasRelevantServiceAppointmentChanges(null, null)
        );
        System.assertEquals(
            false,
            WorkOrderLedgerService.hasRelevantOpportunityWorkOrderChanges(
                new Opportunity_WorkOrder__c(),
                new Opportunity_WorkOrder__c()
            )
        );
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        System.assertEquals(true, closedStatuses.contains('Canceled') || closedStatuses.contains('Cancelled'));
        WorkOrderLedgerService.persistEvents(null);
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>());
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>());
        WorkOrderLedgerService.refreshLedgers(new Set<Id>());
        WorkOrderLedgerBackfillBatch dateRangeBatch = new WorkOrderLedgerBackfillBatch(
            System.now().addDays(-1),
            System.now().addDays(1)
        );
        System.assertNotEquals(null, dateRangeBatch);

        Test.startTest();
        Database.executeBatch(new WorkOrderLedgerBackfillBatch(), 50);
        Test.stopTest();
    }

    private static WorkOrderLedgerService.LedgerEvent newEvent(
        Id workOrderId,
        String eventType,
        Datetime eventDatetime,
        Id changedById,
        Boolean isBackfill
    ) {
        WorkOrderLedgerService.LedgerEvent eventRecord = new WorkOrderLedgerService.LedgerEvent();
        eventRecord.WorkOrderId = workOrderId;
        eventRecord.SourceRecordId = workOrderId;
        eventRecord.EventType = eventType;
        eventRecord.EventDatetime = eventDatetime;
        eventRecord.ChangedById = changedById;
        eventRecord.SourceObject = WorkOrderLedgerService.SOURCE_WORK_ORDER;
        eventRecord.Description = 'Work Order created.';
        eventRecord.IsBackfill = isBackfill;
        eventRecord.SystemGenerated = true;
        return eventRecord;
    }

    private static WorkOrderLedgerService.LedgerEvent partsEvent(
        Id workOrderId,
        Datetime eventDatetime,
        String oldValue,
        String newValue
    ) {
        WorkOrderLedgerService.LedgerEvent eventRecord = newEvent(
            workOrderId,
            WorkOrderLedgerService.EVENT_PARTS_STATUS,
            eventDatetime,
            UserInfo.getUserId(),
            false
        );
        eventRecord.OldValue = oldValue;
        eventRecord.NewValue = newValue;
        eventRecord.Description =
            'Parts / Hardware changed from ' + (oldValue == null ? '' : oldValue) + ' to ' + newValue + '.';
        return eventRecord;
    }

    private static WorkOrder insertWorkOrder(String subjectValue) {
        Account accountRecord = new Account(Name = subjectValue + ' Account');
        insert accountRecord;
        return insertWorkOrder(subjectValue, accountRecord.Id);
    }

    private static WorkOrder insertWorkOrder(String subjectValue, Id accountId) {
        WorkType workTypeRecord = TestDataFactory.createWorkType(subjectValue + ' Type', 1);
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = subjectValue,
            Status = openWorkOrderStatus(),
            AccountId = accountId,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        return [
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
            WHERE Id = :workOrderRecord.Id
        ];
    }

    private static ServiceAppointment insertAppointment(
        Id parentId,
        String statusValue,
        Datetime scheduledStart,
        Datetime actualEnd
    ) {
        Datetime dueDate = System.now().addDays(2);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = parentId,
            Status = String.isBlank(statusValue) || statusValue == 'None'
                ? defaultAppointmentStatus()
                : statusValue,
            Subject = 'Ledger SA',
            EarliestStartTime = scheduledStart == null ? System.now() : scheduledStart,
            DueDate = dueDate,
            SchedStartTime = scheduledStart,
            SchedEndTime = scheduledStart == null ? null : scheduledStart.addHours(1),
            ActualEndTime = actualEnd
        );
        insert appointmentRecord;
        return [
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
                WO_Inv_Status__c
            FROM ServiceAppointment
            WHERE Id = :appointmentRecord.Id
        ];
    }

    private static Opportunity insertOpportunity(String nameValue) {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        WorkType workTypeRecord = TestDataFactory.createWorkType(nameValue + ' WT', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = nameValue,
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 100,
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static User createUser(String aliasValue) {
        Profile administratorProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        String uniqueToken = String.valueOf(Datetime.now().getTime()) + aliasValue;
        User userRecord = new User(
            Alias = aliasValue,
            Email = aliasValue + uniqueToken + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Ledger' + aliasValue,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = administratorProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = aliasValue + uniqueToken + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }

    private static String openWorkOrderStatus() {
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        for (Schema.PicklistEntry entry : WorkOrder.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !closedStatuses.contains(entry.getValue())) {
                return entry.getValue();
            }
        }
        return 'For Appointment Booking';
    }

    private static String secondOpenWorkOrderStatus(String currentStatus) {
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        for (Schema.PicklistEntry entry : WorkOrder.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive()
                && !closedStatuses.contains(entry.getValue())
                && entry.getValue() != currentStatus) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String cancelledAppointmentStatus() {
        for (Schema.PicklistEntry entry : ServiceAppointment.Status.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String normalized = entry.getValue() == null ? null : entry.getValue().trim().toUpperCase();
            if (normalized == 'CANCELED' || normalized == 'CANCELLED') {
                return entry.getValue();
            }
        }
        return 'Canceled';
    }

    private static List<String> firstTwoPicklistValues(Schema.SObjectField fieldToken) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
            if (values.size() == 2) {
                break;
            }
        }
        return values;
    }

    private static String firstPicklistValue(Schema.SObjectField fieldToken, String fallbackValue) {
        List<String> values = firstTwoPicklistValues(fieldToken);
        return values.isEmpty() ? fallbackValue : values[0];
    }

    private static String defaultAppointmentStatus() {
        for (Schema.PicklistEntry entry : ServiceAppointment.Status.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String normalized = entry.getValue() == null ? null : entry.getValue().trim().toUpperCase();
            if (normalized != 'COMPLETED' && normalized != 'CANCELED' && normalized != 'CANCELLED') {
                return entry.getValue();
            }
        }
        return 'None';
    }
}
