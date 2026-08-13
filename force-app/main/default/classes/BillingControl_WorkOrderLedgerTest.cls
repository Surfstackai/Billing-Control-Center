@IsTest
private class BillingControl_WorkOrderLedgerTest {
    @IsTest
    static void compactListUsesWorkOrderGrainWithoutOrders() {
        WorkOrderLedgerAutomationControl.disableForTests();
        OrderDiaryAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Tab Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Tab Type', 1);

        Opportunity firstOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Ledger Tab Opp One', 1000);
        Opportunity secondOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Ledger Tab Opp Two', 500);

        WorkOrder multiSaWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Multi SA Ledger WO');
        WorkOrder multiOppWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Multi Opp Ledger WO');
        WorkOrder noAppointmentWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'No SA Ledger WO');
        WorkOrder noOpportunityWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'No Opp Ledger WO');
        WorkOrder scheduledTodayWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Scheduled Today Ledger WO');
        WorkOrder woliWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'WOLI Parent Ledger WO');
        WorkOrder completedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Completed Week Ledger WO');

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = multiSaWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = multiOppWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = multiOppWorkOrder.Id, Opportunity__c = secondOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = noAppointmentWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = scheduledTodayWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = woliWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = completedWorkOrder.Id, Opportunity__c = firstOpportunity.Id)
        };

        Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        Datetime futureStart = Datetime.newInstance(Date.today().addDays(3), Time.newInstance(10, 0, 0, 0));
        Datetime weekEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));

        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = woliWorkOrder.Id);
        insert lineItem;

        insert new List<ServiceAppointment>{
            buildAppointment(multiSaWorkOrder.Id, 'None', null, null, 'Unscheduled SA One'),
            buildAppointment(multiSaWorkOrder.Id, 'Scheduled', futureStart, null, 'Future SA Two'),
            buildAppointment(multiOppWorkOrder.Id, 'None', null, null, 'Multi Opp SA'),
            buildAppointment(noOpportunityWorkOrder.Id, 'None', null, null, 'No Opp SA'),
            buildAppointment(scheduledTodayWorkOrder.Id, 'Scheduled', todayStart, null, 'Today SA'),
            buildAppointment(lineItem.Id, 'None', null, null, 'WOLI SA'),
            buildAppointment(completedWorkOrder.Id, 'Completed', weekEnd.addHours(-2), weekEnd, 'Completed SA')
        };

        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{
                multiSaWorkOrder.Id,
                multiOppWorkOrder.Id,
                noAppointmentWorkOrder.Id,
                noOpportunityWorkOrder.Id,
                scheduledTodayWorkOrder.Id,
                woliWorkOrder.Id,
                completedWorkOrder.Id
            }
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime = BillingControl_WorkOrderLedger.getRuntime(null, null);
        Test.stopTest();

        System.assertEquals(true, runtime.kpis.unscheduledCount >= 1);
        System.assertEquals(true, runtime.kpis.scheduledTodayCount >= 1);
        System.assertEquals(true, runtime.kpis.completedThisWeekCount >= 1);
        System.assertEquals(true, runtime.kpis.noOpportunityCount >= 1);
        System.assertEquals(true, runtime.kpis.noServiceAppointmentCount >= 1);
        System.assertEquals(true, runtime.kpis.multipleOpportunitiesCount >= 1);

        BillingControl_Orders.WorkOrderRowWrapper multiSaRow = findRow(
            findSection(runtime.sections, 'UNSCHEDULED').rows,
            multiSaWorkOrder.Id
        );
        System.assertNotEquals(null, multiSaRow);
        System.assertEquals(1, countRows(findSection(runtime.sections, 'UNSCHEDULED').rows, multiSaWorkOrder.Id));
        System.assertEquals(1, countRows(findSection(runtime.sections, 'SCHEDULED').rows, multiSaWorkOrder.Id));
        System.assertEquals(2, multiSaRow.relatedServiceAppointments.size());
        System.assertEquals(1000, multiSaRow.opportunityAmount);
        System.assertEquals(firstOpportunity.Name, multiSaRow.opportunityName);
        System.assertEquals(firstOpportunity.Id, multiSaRow.opportunityId);
        System.assertEquals(null, multiSaRow.depositAmount);
        System.assertEquals(null, multiSaRow.depositStatus);
        System.assertEquals(null, multiSaRow.partsStatus);
        System.assertEquals(null, multiSaRow.invoiceNumbers);
        System.assertNotEquals(null, multiSaRow.ledgerId);
        System.assertEquals(multiSaRow.reconciliationStatus, multiSaRow.status);
        System.assertNotEquals(null, multiSaRow.createdDate);
        System.assertEquals('Multi SA Ledger WO', multiSaRow.subject);

        BillingControl_Orders.WorkOrderRowWrapper multiOppRow = findRow(
            findSection(runtime.sections, 'MULTIPLE_OPPORTUNITIES').rows,
            multiOppWorkOrder.Id
        );
        System.assertNotEquals(null, multiOppRow);
        System.assertEquals(1, countRows(findSection(runtime.sections, 'MULTIPLE_OPPORTUNITIES').rows, multiOppWorkOrder.Id));
        System.assertEquals(null, multiOppRow.opportunityId);
        System.assertEquals(2, multiOppRow.relatedOpportunities.size());
        System.assertEquals(true, multiOppRow.opportunityName.contains(firstOpportunity.Name));
        System.assertEquals(true, multiOppRow.opportunityName.contains(secondOpportunity.Name));
        System.assertEquals(1500, multiOppRow.opportunityAmount);

        BillingControl_Orders.WorkOrderRowWrapper noSaRow = findRow(
            findSection(runtime.sections, 'NO_SERVICE_APPOINTMENT').rows,
            noAppointmentWorkOrder.Id
        );
        System.assertNotEquals(null, noSaRow);
        System.assertEquals(0, noSaRow.serviceAppointmentCount);

        BillingControl_Orders.WorkOrderRowWrapper noOppRow = findRow(
            findSection(runtime.sections, 'NO_OPPORTUNITY').rows,
            noOpportunityWorkOrder.Id
        );
        System.assertNotEquals(null, noOppRow);
        System.assertEquals(null, noOppRow.opportunityAmount);

        BillingControl_Orders.WorkOrderRowWrapper todayRow = findRow(
            findSection(runtime.sections, 'SCHEDULED_TODAY').rows,
            scheduledTodayWorkOrder.Id
        );
        System.assertNotEquals(null, todayRow);
        System.assertEquals(
            Date.today(),
            todayRow.relatedServiceAppointments[0].schedStartTime.date(),
            'Scheduled today must honor the running user timezone.'
        );

        BillingControl_Orders.WorkOrderRowWrapper woliRow = findRow(
            findSection(runtime.sections, 'UNSCHEDULED').rows,
            woliWorkOrder.Id
        );
        System.assertNotEquals(null, woliRow);
        System.assertEquals(1, woliRow.relatedServiceAppointments.size());

        System.assertNotEquals(
            null,
            findRow(findSection(runtime.sections, 'COMPLETED_THIS_WEEK').rows, completedWorkOrder.Id)
        );
    }

    @IsTest
    static void dateFilterUsesCompletedServiceDate() {
        WorkOrderLedgerAutomationControl.disableForTests();
        OrderDiaryAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Date Filter Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Date Filter Type', 1);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Completed Today Ledger WO');
        Datetime completedEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        insert buildAppointment(
            workOrderRecord.Id,
            'Completed',
            completedEnd.addHours(-2),
            completedEnd,
            'Completed Today SA'
        );
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Date todayDate = Date.today();
        BillingControl_DataProvider.BillingFilterContextDTO thisYearContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        thisYearContext.filters.add(
            dateBoundFilter(
                'DATE_FILTER_START',
                'Work_Order_Ledger__c',
                'Last_Service_Date__c',
                'Greater Or Equal',
                Date.newInstance(todayDate.year(), 1, 1),
                false
            )
        );
        thisYearContext.filters.add(
            dateBoundFilter(
                'DATE_FILTER_END',
                'Work_Order_Ledger__c',
                'Last_Service_Date__c',
                'Less Or Equal',
                Date.newInstance(todayDate.year(), 12, 31),
                true
            )
        );

        BillingControl_DataProvider.BillingFilterContextDTO lastYearContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        lastYearContext.filters.add(
            dateBoundFilter(
                'DATE_FILTER_START',
                'Work_Order_Ledger__c',
                'Last_Service_Date__c',
                'Greater Or Equal',
                Date.newInstance(todayDate.year() - 1, 1, 1),
                false
            )
        );
        lastYearContext.filters.add(
            dateBoundFilter(
                'DATE_FILTER_END',
                'Work_Order_Ledger__c',
                'Last_Service_Date__c',
                'Less Or Equal',
                Date.newInstance(todayDate.year() - 1, 12, 31),
                true
            )
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(41L, thisYearContext);
        BillingControl_WorkOrderLedger.RuntimeBundle lastYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(42L, lastYearContext);
        Test.stopTest();

        System.assertEquals(
            true,
            countAllRows(thisYearRuntime.sections) >= 1,
            'This Year should include Work Orders completed today.'
        );
        System.assertNotEquals(
            null,
            findRow(findSection(thisYearRuntime.sections, 'COMPLETED_THIS_WEEK').rows, workOrderRecord.Id)
        );
        System.assertEquals(
            0,
            countAllRows(lastYearRuntime.sections),
            'Last Year should exclude Work Orders completed today.'
        );
    }

    @IsTest
    static void ledgerDetailLoadsOnDemandForOneLedger() {
        WorkOrderLedgerAutomationControl.disableForTests();
        OrderDiaryAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Detail Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Detail Type', 1);
        Opportunity firstOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Detail Opp One', 800);
        Opportunity secondOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Detail Opp Two', 200);
        WorkOrder detailWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Detail Ledger WO');
        WorkOrder otherWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Other Ledger WO');

        String depositStatus = firstPicklistValue(WorkOrder.Deposit_Payments__c);
        String partsStatus = firstPicklistValue(WorkOrder.Parts_Hardware__c);
        detailWorkOrder.Deposit_Amount__c = 250;
        detailWorkOrder.Invoice_Number__c = 'INV-WO-DETAIL';
        if (depositStatus != null) {
            detailWorkOrder.Deposit_Payments__c = depositStatus;
        }
        if (partsStatus != null) {
            detailWorkOrder.Parts_Hardware__c = partsStatus;
        }
        update detailWorkOrder;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = detailWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = detailWorkOrder.Id, Opportunity__c = secondOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = otherWorkOrder.Id, Opportunity__c = firstOpportunity.Id)
        };

        Datetime firstEventTime = System.now().addDays(-2);
        Datetime secondEventTime = System.now().addDays(-1);
        insert new List<ServiceAppointment>{
            buildAppointment(detailWorkOrder.Id, 'None', null, null, 'Detail SA One'),
            buildAppointment(detailWorkOrder.Id, 'Scheduled', System.now().addDays(1), null, 'Detail SA Two')
        };
        ServiceAppointment invoiceAppointment = [
            SELECT Id, Invoice_Number__c
            FROM ServiceAppointment
            WHERE ParentRecordId = :detailWorkOrder.Id
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        invoiceAppointment.Invoice_Number__c = 'INV-SA-DETAIL';
        update invoiceAppointment;

        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ detailWorkOrder.Id, otherWorkOrder.Id });

        Work_Order_Ledger__c detailLedger = [
            SELECT Id
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :detailWorkOrder.Id
        ];
        Work_Order_Ledger__c otherLedger = [
            SELECT Id
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :otherWorkOrder.Id
        ];

        WorkOrderLedgerService.LedgerEvent laterEvent = namedEvent(
            detailWorkOrder.Id,
            WorkOrderLedgerService.EVENT_WORK_ORDER_STATUS_CHANGED,
            secondEventTime,
            UserInfo.getUserId(),
            'Old Status',
            'New Status',
            'Work Order status changed.'
        );
        laterEvent.IsBackfill = true;
        WorkOrderLedgerService.LedgerEvent earlierNullChangedBy = namedEvent(
            detailWorkOrder.Id,
            WorkOrderLedgerService.EVENT_DEPOSIT_STATUS,
            firstEventTime,
            null,
            null,
            depositStatus,
            'Deposit status recorded.'
        );
        earlierNullChangedBy.IsBackfill = true;
        WorkOrderLedgerService.persistEvents(
            new List<WorkOrderLedgerService.LedgerEvent>{ laterEvent, earlierNullChangedBy }
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.LedgerDetailWrapper emptyDetail =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(null);
        BillingControl_WorkOrderLedger.LedgerDetailWrapper detail =
            BillingControl_DataProvider.getWorkOrderLedgerDetail(detailLedger.Id);
        BillingControl_WorkOrderLedger.LedgerDetailWrapper otherDetail =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(otherLedger.Id);
        Test.stopTest();

        System.assertEquals(null, emptyDetail.ledgerId);
        System.assertEquals(detailLedger.Id, detail.ledgerId);
        System.assertEquals(detailWorkOrder.Id, detail.workOrderId);
        System.assertEquals('INV-WO-DETAIL', detail.workOrderInvoiceNumber);
        System.assertEquals(250, detail.depositAmount);
        if (depositStatus != null) {
            System.assertEquals(depositStatus, detail.depositStatus);
        }
        if (partsStatus != null) {
            System.assertEquals(partsStatus, detail.partsStatus);
        }
        System.assertEquals(2, detail.opportunities.size());
        System.assertEquals(2, detail.appointments.size());
        System.assertEquals(true, detail.timeline.size() >= 2);
        System.assertEquals(otherWorkOrder.Id, otherDetail.workOrderId);
        System.assertEquals(false, otherDetail.ledgerId == detail.ledgerId);

        Set<Id> detailAppointmentIds = new Set<Id>();
        Boolean sawInvoiceMarker = false;
        for (BillingControl_WorkOrderLedger.LedgerAppointmentWrapper appointmentRow : detail.appointments) {
            detailAppointmentIds.add(appointmentRow.serviceAppointmentId);
            if (appointmentRow.invoiceNumber == 'INV-SA-DETAIL') {
                sawInvoiceMarker = true;
            }
        }
        System.assertEquals(true, sawInvoiceMarker);
        System.assertEquals(false, detailAppointmentIds.contains(null));

        for (Integer indexValue = 1; indexValue < detail.timeline.size(); indexValue++) {
            Datetime previousDatetime = detail.timeline[indexValue - 1].eventDatetime;
            Datetime currentDatetime = detail.timeline[indexValue].eventDatetime;
            if (previousDatetime != null && currentDatetime != null) {
                System.assertEquals(true, previousDatetime <= currentDatetime);
            }
        }

        Boolean sawNamedChangedBy = false;
        Boolean sawNullChangedBy = false;
        for (BillingControl_Orders.TimelineEntryWrapper entryRecord : detail.timeline) {
            if (entryRecord.changedByName != null) {
                sawNamedChangedBy = true;
            }
            if (entryRecord.eventType == WorkOrderLedgerService.EVENT_DEPOSIT_STATUS
                && entryRecord.changedByName == null) {
                sawNullChangedBy = true;
            }
        }
        System.assertEquals(true, sawNamedChangedBy);
        System.assertEquals(true, sawNullChangedBy);
        System.assertEquals(true, String.isNotBlank(detail.reconciliationStatus));
    }

    @IsTest
    static void validationCountsAreAvailableForDiagnostics() {
        WorkOrderLedgerAutomationControl.disableForTests();
        OrderDiaryAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Validation Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Validation Type', 1);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Validation Ledger WO');
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.ValidationCountsWrapper counts =
            BillingControl_DataProvider.getWorkOrderLedgerValidationCounts();
        Test.stopTest();

        System.assertEquals(true, counts.ledgerCount >= 1);
        System.assertEquals(true, counts.openWorkOrderCount >= 1);
        System.assertEquals(true, counts.openWorkOrdersWithoutLedger >= 0);
        System.assertEquals(true, counts.unscheduledCount >= 0);
        System.assertEquals(true, counts.scheduledTodayCount >= 0);
        System.assertEquals(true, counts.completedThisWeekCount >= 0);
        System.assertEquals(true, counts.noOpportunityCount >= 0);
        System.assertEquals(true, counts.noServiceAppointmentCount >= 0);
        System.assertEquals(true, counts.multipleOpportunityCount >= 0);
        System.assertEquals(LEDGER_QUERY_LIMIT_FOR_ASSERT, counts.listWindowLimit);
        System.assertEquals(false, counts.listTruncated);
        System.assertEquals(true, counts.openLedgerCount >= 1);
    }

    private static final Integer LEDGER_QUERY_LIMIT_FOR_ASSERT = 10000;

    private static WorkOrder insertWorkOrder(Id accountId, Id workTypeId, String subjectValue) {
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = subjectValue,
            Status = openWorkOrderStatus(),
            AccountId = accountId,
            WorkTypeId = workTypeId
        );
        insert workOrderRecord;
        return workOrderRecord;
    }

    private static Opportunity insertOpportunity(Id accountId, Id workTypeId, String nameValue, Decimal amountValue) {
        Opportunity opportunityRecord = new Opportunity(
            Name = nameValue,
            AccountId = accountId,
            StageName = firstOpportunityStage(),
            CloseDate = Date.today().addDays(14),
            Amount = amountValue,
            Work_Type__c = workTypeId,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static ServiceAppointment buildAppointment(
        Id parentId,
        String statusValue,
        Datetime scheduledStart,
        Datetime actualEnd,
        String subjectValue
    ) {
        Datetime earliest = scheduledStart == null ? System.now() : scheduledStart;
        return new ServiceAppointment(
            ParentRecordId = parentId,
            Status = statusValue,
            Subject = subjectValue,
            EarliestStartTime = earliest,
            DueDate = earliest.addDays(7),
            SchedStartTime = scheduledStart,
            SchedEndTime = scheduledStart == null ? null : scheduledStart.addHours(1),
            ActualEndTime = actualEnd
        );
    }

    private static WorkOrderLedgerService.LedgerEvent namedEvent(
        Id workOrderId,
        String eventType,
        Datetime eventDatetime,
        Id changedById,
        String oldValue,
        String newValue,
        String descriptionValue
    ) {
        WorkOrderLedgerService.LedgerEvent eventRecord = new WorkOrderLedgerService.LedgerEvent();
        eventRecord.WorkOrderId = workOrderId;
        eventRecord.SourceRecordId = workOrderId;
        eventRecord.EventType = eventType;
        eventRecord.EventDatetime = eventDatetime;
        eventRecord.ChangedById = changedById;
        eventRecord.OldValue = oldValue;
        eventRecord.NewValue = newValue;
        eventRecord.Description = descriptionValue;
        eventRecord.SourceObject = WorkOrderLedgerService.SOURCE_WORK_ORDER;
        eventRecord.SystemGenerated = true;
        return eventRecord;
    }

    private static BillingControl_Orders.BucketSectionWrapper findSection(
        List<BillingControl_Orders.BucketSectionWrapper> sections,
        String bucketKey
    ) {
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            if (sectionRecord.bucketKey == bucketKey) {
                return sectionRecord;
            }
        }
        return null;
    }

    private static BillingControl_Orders.WorkOrderRowWrapper findRow(
        List<BillingControl_Orders.WorkOrderRowWrapper> rows,
        Id workOrderId
    ) {
        if (rows == null) {
            return null;
        }
        for (BillingControl_Orders.WorkOrderRowWrapper row : rows) {
            if (row.workOrderId == workOrderId) {
                return row;
            }
        }
        return null;
    }

    private static Integer countRows(List<BillingControl_Orders.WorkOrderRowWrapper> rows, Id workOrderId) {
        Integer matchCount = 0;
        if (rows == null) {
            return matchCount;
        }
        for (BillingControl_Orders.WorkOrderRowWrapper row : rows) {
            if (row.workOrderId == workOrderId) {
                matchCount++;
            }
        }
        return matchCount;
    }

    private static Integer countAllRows(List<BillingControl_Orders.BucketSectionWrapper> sections) {
        Integer rowCount = 0;
        if (sections == null) {
            return rowCount;
        }
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            if (sectionRecord.rows != null) {
                rowCount += sectionRecord.rows.size();
            }
        }
        return rowCount;
    }

    private static BillingControl_DataProvider.BillingFilterDTO dateBoundFilter(
        String developerKey,
        String objectApiName,
        String fieldApiName,
        String operatorValue,
        Date boundaryDate,
        Boolean endOfDay
    ) {
        BillingControl_DataProvider.BillingFilterDTO filterRecord =
            new BillingControl_DataProvider.BillingFilterDTO();
        filterRecord.developerKey = developerKey;
        filterRecord.objectApiName = objectApiName;
        filterRecord.fieldApiName = fieldApiName;
        filterRecord.operator = operatorValue;
        filterRecord.valueType = 'Static';
        String dateText =
            String.valueOf(boundaryDate.year())
            + '-'
            + String.valueOf(boundaryDate.month()).leftPad(2, '0')
            + '-'
            + String.valueOf(boundaryDate.day()).leftPad(2, '0');
        filterRecord.value = dateText + (endOfDay ? ' 23:59:59' : ' 00:00:00');
        return filterRecord;
    }

    private static String openWorkOrderStatus() {
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        for (Schema.PicklistEntry picklistEntry : WorkOrder.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && !closedStatuses.contains(picklistEntry.getValue())) {
                return picklistEntry.getValue();
            }
        }
        return 'New';
    }

    private static String firstOpportunityStage() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return 'Prospecting';
    }

    private static String firstPicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry picklistEntry : fieldToken.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }
}
