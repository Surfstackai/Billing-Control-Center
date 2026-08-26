@IsTest
private class BillingControl_WorkOrderLedgerTest {
    @IsTest
    static void compactListUsesWorkOrderGrainWithoutOrders() {
        WorkOrderLedgerAutomationControl.disableForTests();
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
        WorkOrder inProgressWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'In Progress Ledger WO');
        WorkOrder woliWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'WOLI Parent Ledger WO');
        WorkOrder completedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Completed Week Ledger WO');

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = multiSaWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = multiOppWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = multiOppWorkOrder.Id, Opportunity__c = secondOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = noAppointmentWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = scheduledTodayWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = inProgressWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = woliWorkOrder.Id, Opportunity__c = firstOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = completedWorkOrder.Id, Opportunity__c = firstOpportunity.Id)
        };

        Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        Datetime futureStart = Datetime.newInstance(Date.today().addDays(3), Time.newInstance(10, 0, 0, 0));
        Datetime weekEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));

        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = woliWorkOrder.Id);
        insert lineItem;

        ServiceAppointment inProgressAppointment = buildAppointment(
            inProgressWorkOrder.Id,
            'Scheduled',
            todayStart,
            null,
            'In Progress SA'
        );
        inProgressAppointment.ActualStartTime = todayStart;

        insert new List<ServiceAppointment>{
            buildAppointment(multiSaWorkOrder.Id, 'None', null, null, 'Unscheduled SA One'),
            buildAppointment(multiSaWorkOrder.Id, 'Scheduled', futureStart, null, 'Future SA Two'),
            buildAppointment(multiOppWorkOrder.Id, 'None', null, null, 'Multi Opp SA'),
            buildAppointment(noOpportunityWorkOrder.Id, 'None', null, null, 'No Opp SA'),
            buildAppointment(scheduledTodayWorkOrder.Id, 'Scheduled', todayStart, null, 'Today SA'),
            inProgressAppointment,
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
                inProgressWorkOrder.Id,
                woliWorkOrder.Id,
                completedWorkOrder.Id
            }
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime = BillingControl_WorkOrderLedger.getRuntime(null, null);
        Test.stopTest();

        System.assertEquals(true, runtime.kpis.unscheduledCount >= 1);
        System.assertEquals(true, runtime.kpis.scheduledCount >= 1);
        System.assertEquals(true, runtime.kpis.inProgressCount >= 1);
        System.assertEquals(0, runtime.kpis.completedNotBilledCount);
        System.assertEquals(0, runtime.kpis.completedThisWeekCount);
        System.assertEquals(0, runtime.kpis.completedThisMonthCount);
        System.assertEquals(0, runtime.kpis.noOpportunityCount);
        System.assertEquals(0, runtime.kpis.noServiceAppointmentCount);
        System.assertEquals(0, runtime.kpis.multipleOpportunitiesCount);

        BillingControl_Orders.WorkOrderRowWrapper multiSaRow = findRow(
            findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows,
            multiSaWorkOrder.Id
        );
        System.assertNotEquals(null, multiSaRow);
        System.assertEquals(1, countRows(findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows, multiSaWorkOrder.Id));
        System.assertEquals(0, countRows(findSection(runtime.sections, 'READY_TO_SCHEDULE').rows, multiSaWorkOrder.Id));
        System.assertEquals(1, countOperationalOccurrences(runtime.sections, multiSaWorkOrder.Id));
        System.assertEquals(2, multiSaRow.relatedServiceAppointments.size());
        Boolean sawNoneDisplay = false;
        Boolean sawScheduledDisplay = false;
        for (BillingControl_Orders.WorkOrderRowWrapper appointmentRow : multiSaRow.relatedServiceAppointments) {
            if (appointmentRow.serviceAppointmentDisplay != null
                && appointmentRow.serviceAppointmentDisplay.contains('(none)')) {
                sawNoneDisplay = true;
            }
            if (appointmentRow.serviceAppointmentDisplay != null
                && appointmentRow.serviceAppointmentDisplay.contains('(Scheduled -')) {
                sawScheduledDisplay = true;
            }
        }
        System.assertEquals(true, sawNoneDisplay);
        System.assertEquals(true, sawScheduledDisplay);
        System.assertEquals(1000, multiSaRow.opportunityAmount);
        System.assertEquals(1000, multiSaRow.visitAmount);
        System.assertEquals(firstOpportunity.Name, multiSaRow.opportunityName);
        System.assertEquals(firstOpportunity.Id, multiSaRow.opportunityId);
        System.assertEquals(null, multiSaRow.depositAmount);
        System.assertEquals(null, multiSaRow.depositStatus);
        System.assertEquals(null, multiSaRow.partsStatus);
        System.assertEquals(null, multiSaRow.invoiceNumbers);
        System.assertNotEquals(null, multiSaRow.ledgerId);
        System.assertEquals(multiSaRow.reconciliationStatus, multiSaRow.status);
        System.assertNotEquals(null, multiSaRow.createdDate);
        System.assertNotEquals(null, multiSaRow.earliestStartTime);
        System.assertEquals('Multi SA Ledger WO', multiSaRow.subject);
        System.assertEquals('Ledger Tab Type', multiSaRow.workTypeName);

        BillingControl_Orders.WorkOrderRowWrapper multiOppRow = findRow(
            findSection(runtime.sections, 'READY_TO_SCHEDULE').rows,
            multiOppWorkOrder.Id
        );
        System.assertNotEquals(null, multiOppRow);
        System.assertEquals(1, countRows(findSection(runtime.sections, 'READY_TO_SCHEDULE').rows, multiOppWorkOrder.Id));
        System.assertEquals(1, countOperationalOccurrences(runtime.sections, multiOppWorkOrder.Id));
        System.assertEquals(null, multiOppRow.opportunityId);
        System.assertEquals(2, multiOppRow.relatedOpportunities.size());
        System.assertEquals(true, multiOppRow.opportunityName.contains(firstOpportunity.Name));
        System.assertEquals(true, multiOppRow.opportunityName.contains(secondOpportunity.Name));
        System.assertEquals(1500, multiOppRow.opportunityAmount);
        System.assertEquals(1500, multiOppRow.visitAmount);

        BillingControl_Orders.WorkOrderRowWrapper noSaRow = findRow(
            findSection(runtime.sections, 'READY_TO_SCHEDULE').rows,
            noAppointmentWorkOrder.Id
        );
        System.assertNotEquals(null, noSaRow);
        System.assertEquals(0, noSaRow.serviceAppointmentCount);
        System.assertEquals(1, countOperationalOccurrences(runtime.sections, noAppointmentWorkOrder.Id));

        BillingControl_Orders.WorkOrderRowWrapper noOppRow = findRow(
            findSection(runtime.sections, 'READY_TO_SCHEDULE').rows,
            noOpportunityWorkOrder.Id
        );
        System.assertNotEquals(null, noOppRow);
        System.assertEquals(null, noOppRow.opportunityAmount);
        System.assertEquals(null, noOppRow.visitAmount);

        BillingControl_Orders.WorkOrderRowWrapper todayRow = findRow(
            findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows,
            scheduledTodayWorkOrder.Id
        );
        System.assertNotEquals(null, todayRow);
        System.assertEquals(
            Date.today(),
            todayRow.relatedServiceAppointments[0].schedStartTime.date(),
            'Scheduled today must honor the running user timezone.'
        );
        System.assertEquals(true, todayRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(Scheduled -'));

        BillingControl_Orders.WorkOrderRowWrapper inProgressRow = findRow(
            findSection(runtime.sections, 'IN_PROGRESS').rows,
            inProgressWorkOrder.Id
        );
        System.assertNotEquals(null, inProgressRow);
        System.assertEquals(1, countOperationalOccurrences(runtime.sections, inProgressWorkOrder.Id));
        System.assertEquals(true, inProgressRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(In Progress -'));

        BillingControl_Orders.WorkOrderRowWrapper woliRow = findRow(
            findSection(runtime.sections, 'READY_TO_SCHEDULE').rows,
            woliWorkOrder.Id
        );
        System.assertNotEquals(null, woliRow);
        System.assertEquals(1, woliRow.relatedServiceAppointments.size());

        System.assertEquals(
            null,
            findAnyRow(runtime.sections, completedWorkOrder.Id),
            'Completed Service Appointments belong on Invoicing, not Work Order Ledger.'
        );
        System.assertEquals(0, countOperationalOccurrences(runtime.sections, completedWorkOrder.Id));
        System.assertNotEquals(null, BillingControl_WorkOrderLedger.getLedgerIdsByWorkOrderId(
            new Set<Id>{ multiOppWorkOrder.Id }
        ).get(multiOppWorkOrder.Id));
        System.assertNotEquals(null, BillingControl_WorkOrderLedger.getLedgerIdsByOpportunityId(
            new Set<Id>{ firstOpportunity.Id }
        ).get(firstOpportunity.Id));
    }

    @IsTest
    static void visitAmountSplitsPitCleaningOpportunityAcrossWorkOrders() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Pit Cleaning Visit Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Pit Cleaning', 1);
        Opportunity opportunityRecord = insertOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Annual Pit Cleaning Contract',
            1200
        );

        List<WorkOrder> visitWorkOrders = new List<WorkOrder>{
            insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Pit Cleaning Visit 1'),
            insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Pit Cleaning Visit 2'),
            insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Pit Cleaning Visit 3'),
            insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Pit Cleaning Visit 4')
        };
        List<Opportunity_WorkOrder__c> junctions = new List<Opportunity_WorkOrder__c>();
        Set<Id> visitWorkOrderIds = new Set<Id>();
        for (WorkOrder visitWorkOrder : visitWorkOrders) {
            visitWorkOrderIds.add(visitWorkOrder.Id);
            junctions.add(new Opportunity_WorkOrder__c(
                Work_Order__c = visitWorkOrder.Id,
                Opportunity__c = opportunityRecord.Id
            ));
        }
        insert junctions;
        WorkOrderLedgerService.backfillWorkOrders(visitWorkOrderIds);

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime = BillingControl_WorkOrderLedger.getRuntime(71L, null);
        Test.stopTest();

        BillingControl_Orders.BucketSectionWrapper readySection = findSection(runtime.sections, 'READY_TO_SCHEDULE');
        Decimal visitTotal = 0;
        for (WorkOrder visitWorkOrder : visitWorkOrders) {
            BillingControl_Orders.WorkOrderRowWrapper row = findRow(readySection.rows, visitWorkOrder.Id);
            System.assertNotEquals(null, row, 'Pit Cleaning visit Work Orders should appear on the ledger.');
            System.assertEquals(1200, row.opportunityAmount);
            System.assertEquals(300, row.visitAmount);
            visitTotal += row.visitAmount;
        }
        System.assertEquals(1200, visitTotal);
        System.assertEquals(1200, runtime.kpis.unscheduledRevenue);
        System.assertEquals(true, BillingControl_WorkOrderLedger.matchesPitCleaningText('Preventative Maintenance'));
        System.assertEquals(true, BillingControl_WorkOrderLedger.matchesPitCleaningText('Pit Cleaning'));
        System.assertEquals(false, BillingControl_WorkOrderLedger.matchesPitCleaningText('Plumbing'));
    }

    @IsTest
    static void dateFilterUsesCompletedServiceDate() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Date Filter Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Date Filter Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Date Filter Opp', 500);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Completed Today Ledger WO');
        WorkOrder siblingReadyWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Sibling Ready Ledger WO');
        Datetime completedEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        insert new List<ServiceAppointment>{
            buildAppointment(
                workOrderRecord.Id,
                'Completed',
                completedEnd.addHours(-2),
                completedEnd,
                'Completed Today SA'
            ),
            buildAppointment(siblingReadyWorkOrder.Id, 'None', null, null, 'Sibling Ready SA')
        };
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = siblingReadyWorkOrder.Id, Opportunity__c = opportunityRecord.Id)
        };
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id, siblingReadyWorkOrder.Id });

        Date todayDate = Date.today();

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(41L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle lastYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(42L, null, lastYearWindow(todayDate));
        Test.stopTest();

        System.assertEquals(
            true,
            countAllRows(thisYearRuntime.sections) >= 1,
            'This Year should include Work Orders whose actual completion or in-range schedule is this year.'
        );
        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, workOrderRecord.Id),
            'Completed Work Orders stay off Work Order Ledger.'
        );
        System.assertNotEquals(
            null,
            findRow(findSection(thisYearRuntime.sections, 'READY_TO_SCHEDULE').rows, siblingReadyWorkOrder.Id)
        );
        System.assertEquals(0, thisYearRuntime.kpis.completedThisWeekCount);
        System.assertEquals(0, thisYearRuntime.kpis.completedThisMonthCount);
        System.assertEquals(
            0,
            countAllRows(lastYearRuntime.sections),
            'Last Year should exclude Work Orders completed today.'
        );
    }

    @IsTest
    static void dateFilterExpandsOpportunityWorkAndHonorsOwner() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Expand Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Expand Type', 1);

        List<User> otherUsers = [
            SELECT Id, Name
            FROM User
            WHERE Id != :UserInfo.getUserId()
            AND IsActive = true
            LIMIT 1
        ];
        System.assertEquals(false, otherUsers.isEmpty(), 'Need a second active user for owner-filter coverage.');
        Id otherOwnerId = otherUsers[0].Id;

        Opportunity opportunityA = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Expand Opp A', 1200);
        Opportunity opportunityB = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Expand Opp B', 400);
        Opportunity opportunityOtherOwner = insertOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Expand Opp Other Owner',
            800
        );
        opportunityOtherOwner.OwnerId = otherOwnerId;
        update opportunityOtherOwner;

        WorkOrder matchingWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Matching Completed WO');
        WorkOrder siblingRelatedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Sibling Related WO');
        WorkOrder sharedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Shared Multi Opp WO');
        WorkOrder opportunityBOnlyWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Opp B Only WO');
        WorkOrder billedOnlyWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Billed Only Opp WO');
        WorkOrder noOpportunityWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'No Opp Completed WO');
        WorkOrder otherOwnerWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Other Owner Completed WO');

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = matchingWorkOrder.Id, Opportunity__c = opportunityA.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = siblingRelatedWorkOrder.Id, Opportunity__c = opportunityA.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = sharedWorkOrder.Id, Opportunity__c = opportunityA.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = sharedWorkOrder.Id, Opportunity__c = opportunityB.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = sharedWorkOrder.Id, Opportunity__c = opportunityOtherOwner.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = opportunityBOnlyWorkOrder.Id, Opportunity__c = opportunityB.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = billedOnlyWorkOrder.Id, Opportunity__c = opportunityB.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = otherOwnerWorkOrder.Id, Opportunity__c = opportunityOtherOwner.Id)
        };

        Datetime completedToday = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        Datetime completedLastYear = Datetime.newInstance(
            Date.newInstance(Date.today().year() - 1, 6, 15),
            Time.newInstance(14, 0, 0, 0)
        );
        Datetime futureStart = Datetime.newInstance(Date.today().addDays(5), Time.newInstance(10, 0, 0, 0));

        insert new List<ServiceAppointment>{
            buildAppointment(matchingWorkOrder.Id, 'Completed', completedToday.addHours(-2), completedToday, 'Match SA'),
            buildAppointment(
                siblingRelatedWorkOrder.Id,
                'Completed',
                completedLastYear.addHours(-2),
                completedLastYear,
                'Old Sibling SA'
            ),
            buildAppointment(sharedWorkOrder.Id, 'None', null, null, 'Shared Unscheduled SA'),
            buildAppointment(
                opportunityBOnlyWorkOrder.Id,
                'Scheduled',
                futureStart,
                null,
                'Opp B Scheduled SA'
            ),
            buildAppointment(
                billedOnlyWorkOrder.Id,
                'Completed',
                completedToday.addHours(-2),
                completedToday,
                'Billed SA'
            ),
            buildAppointment(
                noOpportunityWorkOrder.Id,
                'Completed',
                completedToday.addHours(-2),
                completedToday,
                'No Opp SA'
            ),
            buildAppointment(
                otherOwnerWorkOrder.Id,
                'Completed',
                completedToday.addHours(-2),
                completedToday,
                'Other Owner SA'
            )
        };
        ServiceAppointment billedAppointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordId = :billedOnlyWorkOrder.Id
            LIMIT 1
        ];
        billedAppointment.Invoice_Number__c = 'INV-EXPAND-BILLED';
        update billedAppointment;
        ServiceAppointment siblingAppointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordId = :siblingRelatedWorkOrder.Id
            LIMIT 1
        ];
        siblingAppointment.Invoice_Number__c = 'INV-EXPAND-SIBLING';
        update siblingAppointment;

        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{
                matchingWorkOrder.Id,
                siblingRelatedWorkOrder.Id,
                sharedWorkOrder.Id,
                opportunityBOnlyWorkOrder.Id,
                billedOnlyWorkOrder.Id,
                noOpportunityWorkOrder.Id,
                otherOwnerWorkOrder.Id
            }
        );

        Date todayDate = Date.today();
        BillingControl_DataProvider.BillingFilterContextDTO ownerContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        ownerContext.filters.add(
            buildEqualsFilter('OPPORTUNITY_OWNER', 'Opportunity', 'OwnerId', UserInfo.getUserId())
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(61L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle ownerRuntime =
            BillingControl_WorkOrderLedger.getRuntime(62L, ownerContext, thisYearWindow(todayDate));
        Test.stopTest();

        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, matchingWorkOrder.Id),
            'Completed Work Orders stay off Work Order Ledger.'
        );
        System.assertEquals(0, countOperationalOccurrences(thisYearRuntime.sections, matchingWorkOrder.Id));
        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, siblingRelatedWorkOrder.Id),
            'Invoiced Work Orders stay off Work Order Ledger.'
        );
        System.assertEquals(0, thisYearRuntime.kpis.completedThisWeekCount);
        System.assertEquals(0, thisYearRuntime.kpis.completedThisMonthCount);

        BillingControl_Orders.WorkOrderRowWrapper sharedRow = findRow(
            findSection(thisYearRuntime.sections, 'READY_TO_SCHEDULE').rows,
            sharedWorkOrder.Id
        );
        System.assertNotEquals(null, sharedRow);
        System.assertEquals(true, sharedRow.opportunityName.contains(opportunityA.Name));
        System.assertEquals(true, sharedRow.opportunityName.contains(opportunityB.Name));
        System.assertEquals(true, sharedRow.opportunityName.contains(opportunityOtherOwner.Name));
        System.assertEquals(true, sharedRow.ownerName.contains(UserInfo.getName()));

        System.assertNotEquals(
            null,
            findRow(findSection(thisYearRuntime.sections, 'SCHEDULED_APPOINTMENTS').rows, opportunityBOnlyWorkOrder.Id),
            'Work Orders created or scheduled in range stay on Work Order Ledger.'
        );
        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, billedOnlyWorkOrder.Id),
            'Billed completed appointments do not qualify an Opportunity.'
        );
        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, noOpportunityWorkOrder.Id),
            'Completed Work Orders stay off Work Order Ledger even without an Opportunity.'
        );
        System.assertEquals(
            null,
            findAnyRow(thisYearRuntime.sections, otherOwnerWorkOrder.Id),
            'Completed Work Orders stay off Work Order Ledger.'
        );

        System.assertEquals(
            null,
            findAnyRow(ownerRuntime.sections, matchingWorkOrder.Id),
            'Completed Work Orders stay off Work Order Ledger.'
        );
        System.assertEquals(
            null,
            findAnyRow(ownerRuntime.sections, siblingRelatedWorkOrder.Id),
            'Invoiced Work Orders stay off Work Order Ledger.'
        );
        System.assertNotEquals(null, findAnyRow(ownerRuntime.sections, sharedWorkOrder.Id));
        BillingControl_Orders.WorkOrderRowWrapper ownerSharedRow = findAnyRow(ownerRuntime.sections, sharedWorkOrder.Id);
        System.assertEquals(true, ownerSharedRow.opportunityName.contains(opportunityA.Name));
        System.assertEquals(true, ownerSharedRow.opportunityName.contains(opportunityB.Name));
        System.assertEquals(
            false,
            ownerSharedRow.opportunityName.contains(opportunityOtherOwner.Name),
            'Owner filter shows only that salesperson\'s opportunities on mixed Work Orders.'
        );
        System.assertEquals(1600, ownerSharedRow.opportunityAmount);
        System.assertEquals(true, ownerSharedRow.ownerName.contains(UserInfo.getName()));
        System.assertEquals(
            false,
            ownerSharedRow.ownerName != null && ownerSharedRow.ownerName.contains(otherUsers[0].Name),
            'Owner filter hides other salespeople on mixed Work Orders.'
        );
        System.assertEquals(
            null,
            findAnyRow(ownerRuntime.sections, otherOwnerWorkOrder.Id),
            'Owner filter drops other Opportunity owners.'
        );
        System.assertEquals(
            null,
            findAnyRow(ownerRuntime.sections, noOpportunityWorkOrder.Id),
            'No-opportunity rows drop when an owner is selected.'
        );
    }

    @IsTest
    static void ledgerDetailLoadsOnDemandForOneLedger() {
        WorkOrderLedgerAutomationControl.disableForTests();
        List<User> otherUsers = [
            SELECT Id, Name
            FROM User
            WHERE Id != :UserInfo.getUserId()
            AND IsActive = true
            LIMIT 1
        ];
        System.assertEquals(false, otherUsers.isEmpty(), 'Need a second active user for Account vs Opportunity owner coverage.');
        Id otherOwnerId = otherUsers[0].Id;
        String otherOwnerName = otherUsers[0].Name;

        Account accountRecord = new Account(Name = 'Ledger Detail Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Detail Type', 1);
        Opportunity firstOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Detail Opp One', 800);
        Opportunity secondOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Detail Opp Two', 200);
        firstOpportunity.OwnerId = otherOwnerId;
        secondOpportunity.OwnerId = otherOwnerId;
        update new List<Opportunity>{ firstOpportunity, secondOpportunity };
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
        System.assertEquals(UserInfo.getName(), detail.accountOwnerName);
        System.assertEquals(false, detail.accountOwnerName == otherOwnerName);
        System.assertEquals(otherOwnerName, detail.opportunities[0].ownerName);
        System.assertEquals('INV-WO-DETAIL', detail.workOrderInvoiceNumber);
        System.assertEquals(250, detail.depositAmount);
        if (depositStatus != null) {
            System.assertEquals(depositStatus, detail.depositStatus);
        }
        if (partsStatus != null) {
            System.assertEquals(partsStatus, detail.partsStatus);
        }
        System.assertEquals(2, detail.opportunities.size());
        System.assertEquals(otherOwnerName, detail.opportunities[0].ownerName);
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
    static void accountOwnerStaysLiveWithoutLedgerSync() {
        WorkOrderLedgerAutomationControl.disableForTests();
        List<User> otherUsers = [
            SELECT Id, Name, FirstName, LastName
            FROM User
            WHERE Id != :UserInfo.getUserId()
            AND IsActive = true
            LIMIT 1
        ];
        System.assertEquals(false, otherUsers.isEmpty(), 'Need a second active user for Account owner change coverage.');
        User otherOwner = otherUsers[0];
        String formulaOwnerName = (otherOwner.FirstName == null ? '' : otherOwner.FirstName)
            + (String.isBlank(otherOwner.FirstName) || String.isBlank(otherOwner.LastName) ? '' : ' ')
            + (otherOwner.LastName == null ? '' : otherOwner.LastName);
        formulaOwnerName = formulaOwnerName.trim();

        User runningUser = [
            SELECT FirstName, LastName
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        String runningFormulaOwnerName = (runningUser.FirstName == null ? '' : runningUser.FirstName)
            + (String.isBlank(runningUser.FirstName) || String.isBlank(runningUser.LastName) ? '' : ' ')
            + (runningUser.LastName == null ? '' : runningUser.LastName);
        runningFormulaOwnerName = runningFormulaOwnerName.trim();

        Account accountRecord = new Account(Name = 'Live Account Owner Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Live Account Owner Type', 1);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Live Account Owner WO');
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Work_Order_Ledger__c ledgerRecord = [
            SELECT Id, Account_Owner__c, LastModifiedDate
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderRecord.Id
        ];
        System.assertEquals(runningFormulaOwnerName, ledgerRecord.Account_Owner__c);
        BillingControl_WorkOrderLedger.LedgerDetailWrapper beforeChange =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerRecord.Id);
        System.assertEquals(UserInfo.getName(), beforeChange.accountOwnerName);

        accountRecord.OwnerId = otherOwner.Id;
        update accountRecord;

        Work_Order_Ledger__c ledgerAfterOwnerChange = [
            SELECT Id, Account_Owner__c, LastModifiedDate
            FROM Work_Order_Ledger__c
            WHERE Id = :ledgerRecord.Id
        ];
        BillingControl_WorkOrderLedger.LedgerDetailWrapper afterChange =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerRecord.Id);

        System.assertEquals(formulaOwnerName, ledgerAfterOwnerChange.Account_Owner__c);
        System.assertEquals(otherOwner.Name, afterChange.accountOwnerName);
        System.assertEquals(ledgerRecord.LastModifiedDate, ledgerAfterOwnerChange.LastModifiedDate);
    }

    @IsTest
    static void operationalBucketsExcludeInvoicedAndCompleted() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Classify Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Classify Type', 1);

        Opportunity unbilledOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Unbilled Completed Opp', 400);
        Opportunity billedOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Billed Completed Opp', 250);
        Opportunity woInvoiceOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'WO Invoice Opp', 300);

        WorkOrder unbilledWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Unbilled Completed WO');
        WorkOrder billedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Billed Completed WO');
        WorkOrder woInvoiceWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'WO Invoice WO');

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = unbilledWorkOrder.Id, Opportunity__c = unbilledOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = billedWorkOrder.Id, Opportunity__c = billedOpportunity.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = woInvoiceWorkOrder.Id, Opportunity__c = woInvoiceOpportunity.Id)
        };

        Datetime weekEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        insert new List<ServiceAppointment>{
            buildAppointment(unbilledWorkOrder.Id, 'Completed', weekEnd.addHours(-2), weekEnd, 'Unbilled Completed SA'),
            buildAppointment(billedWorkOrder.Id, 'Completed', weekEnd.addHours(-2), weekEnd, 'Billed Completed SA'),
            buildAppointment(woInvoiceWorkOrder.Id, 'None', null, null, 'Ready But Invoiced SA')
        };
        ServiceAppointment billedAppointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordId = :billedWorkOrder.Id
            LIMIT 1
        ];
        billedAppointment.Invoice_Number__c = 'INV-CLASSIFY-BILLED';
        update billedAppointment;
        woInvoiceWorkOrder.Invoice_Number__c = 'INV-WO-CLASSIFY';
        update woInvoiceWorkOrder;

        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{ unbilledWorkOrder.Id, billedWorkOrder.Id, woInvoiceWorkOrder.Id }
        );

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime = BillingControl_WorkOrderLedger.getRuntime(71L, null);
        Test.stopTest();

        System.assertEquals(0, countOperationalOccurrences(runtime.sections, unbilledWorkOrder.Id));
        System.assertEquals(0, countOperationalOccurrences(runtime.sections, billedWorkOrder.Id));
        System.assertEquals(null, findAnyRow(runtime.sections, unbilledWorkOrder.Id));
        System.assertEquals(null, findAnyRow(runtime.sections, billedWorkOrder.Id));
        System.assertEquals(
            1,
            countOperationalOccurrences(runtime.sections, woInvoiceWorkOrder.Id),
            'An invoice number on the Work Order does not hide its un-invoiced open appointments.'
        );
        System.assertNotEquals(
            null,
            findRow(findSection(runtime.sections, 'READY_TO_SCHEDULE').rows, woInvoiceWorkOrder.Id),
            'The un-invoiced Ready appointment still owns the bucket.'
        );
        System.assertEquals(0, runtime.kpis.completedNotBilledCount);
        System.assertEquals(0, runtime.kpis.completedThisWeekCount);
        System.assertEquals(0, runtime.kpis.completedThisMonthCount);
    }

    @IsTest
    static void validationCountsAreAvailableForDiagnostics() {
        WorkOrderLedgerAutomationControl.disableForTests();
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

    @IsTest
    static void dateFilterIncludesWoliParentScheduledInRange() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger WOLI Date Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger WOLI Date Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'WOLI Date Opp', 400);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'WOLI Date Ledger WO');
        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = workOrderRecord.Id);
        insert lineItem;
        Datetime scheduledStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        insert buildAppointment(lineItem.Id, 'Scheduled', scheduledStart, null, 'WOLI Date SA');
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(61L, null, thisYearWindow(Date.today()));
        Test.stopTest();

        System.assertNotEquals(
            null,
            findAnyRow(runtime.sections, workOrderRecord.Id),
            'A WOLI-parented in-range Service Appointment must include its Work Order.'
        );
    }

    @IsTest
    static void dateFilterSchedStartOnlyDoesNotRequireActualEnd() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger SchedStart Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger SchedStart Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'SchedStart Opp', 350);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'SchedStart Ledger WO');
        Datetime scheduledStart = Datetime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
        insert buildAppointment(workOrderRecord.Id, 'Scheduled', scheduledStart, null, 'SchedStart Only SA');
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(62L, null, thisYearWindow(Date.today()));
        Test.stopTest();

        System.assertNotEquals(
            null,
            findAnyRow(runtime.sections, workOrderRecord.Id),
            'SchedStartTime in range must include the Work Order even when ActualEndTime is blank.'
        );
    }

    @IsTest
    static void dateFilterReadyUsesEarliestStartAndScheduledUsesSchedStart() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Bucket Date Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Bucket Date Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Bucket Date Opp', 900);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Bucket Date Ledger WO');

        Datetime lastYearEarliest = Datetime.newInstance(
            Date.newInstance(Date.today().year() - 1, 3, 15),
            Time.newInstance(8, 0, 0, 0)
        );
        Datetime thisYearSchedStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        ServiceAppointment readyAppointment = buildAppointment(
            workOrderRecord.Id,
            'None',
            null,
            null,
            'Ready Last Year SA'
        );
        readyAppointment.EarliestStartTime = lastYearEarliest;
        readyAppointment.DueDate = lastYearEarliest.addDays(7);

        insert new List<ServiceAppointment>{
            readyAppointment,
            buildAppointment(
                workOrderRecord.Id,
                'Scheduled',
                thisYearSchedStart,
                null,
                'Scheduled This Year SA'
            )
        };
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Date todayDate = Date.today();
        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(64L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle lastYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(65L, null, lastYearWindow(todayDate));
        Test.stopTest();

        BillingControl_Orders.WorkOrderRowWrapper thisYearRow = findRow(
            findSection(thisYearRuntime.sections, 'SCHEDULED_APPOINTMENTS').rows,
            workOrderRecord.Id
        );
        System.assertNotEquals(null, thisYearRow, 'This year should classify on Scheduled Start.');
        System.assertEquals(
            null,
            findRow(findSection(thisYearRuntime.sections, 'READY_TO_SCHEDULE').rows, workOrderRecord.Id)
        );
        System.assertEquals(1, thisYearRow.relatedServiceAppointments.size());
        System.assertEquals(true, thisYearRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(Scheduled -'));

        BillingControl_Orders.WorkOrderRowWrapper lastYearRow = findRow(
            findSection(lastYearRuntime.sections, 'READY_TO_SCHEDULE').rows,
            workOrderRecord.Id
        );
        System.assertNotEquals(null, lastYearRow, 'Prior year should classify on Earliest Start Permitted.');
        System.assertEquals(
            null,
            findRow(findSection(lastYearRuntime.sections, 'SCHEDULED_APPOINTMENTS').rows, workOrderRecord.Id)
        );
        System.assertEquals(1, lastYearRow.relatedServiceAppointments.size());
        System.assertEquals(true, lastYearRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(none)'));
    }

    @IsTest
    static void thisMonthExcludesReadyWorkWithJanuaryEarliestStart() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Month Filter Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Month Filter Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Month Filter Opp', 275);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'January Earliest Ledger WO');
        Datetime januaryEarliest = Datetime.newInstance(
            Date.newInstance(Date.today().year(), 1, 15),
            Time.newInstance(8, 0, 0, 0)
        );
        ServiceAppointment readyAppointment = buildAppointment(
            workOrderRecord.Id,
            'None',
            null,
            null,
            'January Earliest SA'
        );
        readyAppointment.EarliestStartTime = januaryEarliest;
        readyAppointment.DueDate = januaryEarliest.addDays(7);
        insert readyAppointment;
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Date todayDate = Date.today();
        Date monthStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(66L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle thisMonthRuntime =
            BillingControl_WorkOrderLedger.getRuntime(67L, null, dateWindow(monthStart, monthEnd));
        Test.stopTest();

        System.assertNotEquals(
            null,
            findAnyRow(thisYearRuntime.sections, workOrderRecord.Id),
            'Current Year must include Ready to Schedule work whose Earliest Start Permitted is in January.'
        );
        if (todayDate.month() != 1) {
            System.assertEquals(
                null,
                findAnyRow(thisMonthRuntime.sections, workOrderRecord.Id),
                'This Month must exclude Ready to Schedule work whose Earliest Start Permitted is in January.'
            );
        }
    }

    @IsTest
    static void dateFilterExcludesClosedWorkOrderAppointments() {
        WorkOrderLedgerAutomationControl.disableForTests();
        String closedStatus = firstClosedWorkOrderStatus();
        System.assertNotEquals(null, closedStatus, 'Need a configured closed Work Order status.');

        Account accountRecord = new Account(Name = 'Ledger Closed Date Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Closed Date Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Closed Date Opp', 275);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Closed Date Ledger WO');
        Datetime scheduledStart = Datetime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
        insert buildAppointment(workOrderRecord.Id, 'Scheduled', scheduledStart, null, 'Closed Date SA');
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });
        update new WorkOrder(Id = workOrderRecord.Id, Status = closedStatus);

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(63L, null, thisYearWindow(Date.today()));
        Test.stopTest();

        System.assertEquals(
            null,
            findAnyRow(runtime.sections, workOrderRecord.Id),
            'Closed Work Orders must stay out of date-filtered ledger results.'
        );
    }

    @IsTest
    static void bucketQueriesUseOwnedDateFieldsAndExclusiveMembership() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Exclusive Bucket Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Exclusive Bucket Type', 1);

        Date todayDate = Date.today();
        Datetime thisYearEarliest = Datetime.newInstance(
            Date.newInstance(todayDate.year(), 2, 10),
            Time.newInstance(8, 0, 0, 0)
        );
        Datetime lastYearSchedStart = Datetime.newInstance(
            Date.newInstance(todayDate.year() - 1, 6, 15),
            Time.newInstance(9, 0, 0, 0)
        );
        Datetime thisYearActualStart = Datetime.newInstance(
            Date.newInstance(todayDate.year(), 3, 20),
            Time.newInstance(10, 0, 0, 0)
        );
        Datetime thisYearActualEnd = Datetime.newInstance(
            Date.newInstance(todayDate.year(), 4, 1),
            Time.newInstance(11, 0, 0, 0)
        );

        WorkOrder readyWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Ready Earliest WO');
        WorkOrder scheduledWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Scheduled Start WO');
        WorkOrder inProgressWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Actual Start WO');
        WorkOrder completedWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Completed End WO');
        WorkOrder precedenceWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Precedence WO');

        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Exclusive Bucket Opp', 600);
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = readyWorkOrder.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = scheduledWorkOrder.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = inProgressWorkOrder.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = completedWorkOrder.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = precedenceWorkOrder.Id, Opportunity__c = opportunityRecord.Id)
        };

        ServiceAppointment readyAppointment = buildAppointment(readyWorkOrder.Id, 'None', null, null, 'Ready SA');
        readyAppointment.EarliestStartTime = thisYearEarliest;
        readyAppointment.DueDate = thisYearEarliest.addDays(7);

        ServiceAppointment scheduledLastYear = buildAppointment(
            scheduledWorkOrder.Id,
            'Scheduled',
            lastYearSchedStart,
            null,
            'Scheduled Last Year SA'
        );
        ServiceAppointment inProgressAppointment = buildAppointment(
            inProgressWorkOrder.Id,
            'Scheduled',
            thisYearActualStart,
            null,
            'In Progress SA'
        );
        inProgressAppointment.ActualStartTime = thisYearActualStart;

        ServiceAppointment completedAppointment = buildAppointment(
            completedWorkOrder.Id,
            'Completed',
            thisYearActualEnd.addHours(-2),
            thisYearActualEnd,
            'Completed SA'
        );

        ServiceAppointment missingSchedEnd = new ServiceAppointment(
            Status = 'Scheduled',
            SchedStartTime = Datetime.newInstance(todayDate, Time.newInstance(12, 0, 0, 0)),
            SchedEndTime = null,
            ActualStartTime = null,
            ActualEndTime = null
        );
        System.assertEquals(
            0,
            BillingControl_WorkOrderLedger.operationalBucketCount(missingSchedEnd),
            'Scheduled Start without Scheduled End is not an operational bucket member.'
        );

        ServiceAppointment precedenceReady = buildAppointment(precedenceWorkOrder.Id, 'None', null, null, 'Precedence Ready SA');
        precedenceReady.EarliestStartTime = thisYearEarliest;
        precedenceReady.DueDate = thisYearEarliest.addDays(7);
        ServiceAppointment precedenceScheduled = buildAppointment(
            precedenceWorkOrder.Id,
            'Scheduled',
            Datetime.newInstance(todayDate, Time.newInstance(13, 0, 0, 0)),
            null,
            'Precedence Scheduled SA'
        );
        ServiceAppointment precedenceInProgress = buildAppointment(
            precedenceWorkOrder.Id,
            'Scheduled',
            thisYearActualStart,
            null,
            'Precedence In Progress SA'
        );
        precedenceInProgress.ActualStartTime = thisYearActualStart;

        insert new List<ServiceAppointment>{
            readyAppointment,
            scheduledLastYear,
            inProgressAppointment,
            completedAppointment,
            precedenceReady,
            precedenceScheduled,
            precedenceInProgress
        };
        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{
                readyWorkOrder.Id,
                scheduledWorkOrder.Id,
                inProgressWorkOrder.Id,
                completedWorkOrder.Id,
                precedenceWorkOrder.Id
            }
        );

        System.assertEquals(1, BillingControl_WorkOrderLedger.operationalBucketCount(readyAppointment));
        System.assertEquals(1, BillingControl_WorkOrderLedger.operationalBucketCount(scheduledLastYear));
        System.assertEquals(1, BillingControl_WorkOrderLedger.operationalBucketCount(inProgressAppointment));
        System.assertEquals(0, BillingControl_WorkOrderLedger.operationalBucketCount(completedAppointment));

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(80L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle lastYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(81L, null, lastYearWindow(todayDate));
        Test.stopTest();

        BillingControl_Orders.WorkOrderRowWrapper readyRow = findRow(
            findSection(thisYearRuntime.sections, 'READY_TO_SCHEDULE').rows,
            readyWorkOrder.Id
        );
        System.assertNotEquals(null, readyRow);
        System.assertEquals(1, readyRow.relatedServiceAppointments.size());
        System.assertEquals(true, readyRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(none)'));

        System.assertEquals(null, findAnyRow(thisYearRuntime.sections, scheduledWorkOrder.Id));
        System.assertNotEquals(
            null,
            findRow(findSection(lastYearRuntime.sections, 'SCHEDULED_APPOINTMENTS').rows, scheduledWorkOrder.Id)
        );

        BillingControl_Orders.WorkOrderRowWrapper inProgressRow = findRow(
            findSection(thisYearRuntime.sections, 'IN_PROGRESS').rows,
            inProgressWorkOrder.Id
        );
        System.assertNotEquals(null, inProgressRow);
        System.assertEquals(1, inProgressRow.relatedServiceAppointments.size());
        System.assertEquals(true, inProgressRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(In Progress -'));

        System.assertEquals(null, findAnyRow(thisYearRuntime.sections, completedWorkOrder.Id));

        BillingControl_Orders.WorkOrderRowWrapper precedenceRow = findRow(
            findSection(thisYearRuntime.sections, 'IN_PROGRESS').rows,
            precedenceWorkOrder.Id
        );
        System.assertNotEquals(null, precedenceRow, 'In Progress wins over Scheduled and Ready.');
        System.assertEquals(null, findRow(findSection(thisYearRuntime.sections, 'SCHEDULED_APPOINTMENTS').rows, precedenceWorkOrder.Id));
        System.assertEquals(null, findRow(findSection(thisYearRuntime.sections, 'READY_TO_SCHEDULE').rows, precedenceWorkOrder.Id));
        System.assertEquals(1, precedenceRow.relatedServiceAppointments.size());
        System.assertEquals(true, precedenceRow.relatedServiceAppointments[0].serviceAppointmentDisplay.contains('(In Progress -'));
    }

    @IsTest
    static void bucketQueryLimitWarnsWhenTruncated() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Limit Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Limit Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Limit Opp', 100);
        WorkOrder firstWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Limit WO One');
        WorkOrder secondWorkOrder = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Limit WO Two');
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Work_Order__c = firstWorkOrder.Id, Opportunity__c = opportunityRecord.Id),
            new Opportunity_WorkOrder__c(Work_Order__c = secondWorkOrder.Id, Opportunity__c = opportunityRecord.Id)
        };
        insert new List<ServiceAppointment>{
            buildAppointment(firstWorkOrder.Id, 'None', null, null, 'Limit SA One'),
            buildAppointment(secondWorkOrder.Id, 'None', null, null, 'Limit SA Two')
        };
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ firstWorkOrder.Id, secondWorkOrder.Id });

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        BillingControl_WorkOrderLedger.queryLimitOverride = 1;
        try {
            Test.startTest();
            BillingControl_WorkOrderLedger.RuntimeBundle runtime =
                BillingControl_WorkOrderLedger.getRuntime(82L, filterContext, thisYearWindow(Date.today()));
            Test.stopTest();
            System.assertNotEquals(null, runtime);
            System.assertNotEquals(null, filterContext.runtimeWarnings);
            System.assertEquals(
                true,
                String.join(filterContext.runtimeWarnings, ' ').contains('record limit'),
                'Hitting a per-bucket query cap must warn that results are incomplete.'
            );
        } finally {
            BillingControl_WorkOrderLedger.queryLimitOverride = null;
        }
    }

    @IsTest
    static void ordersRuntimePresetsChangeBucketMembership() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ledger Preset Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ledger Preset Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Preset Opp', 250);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Preset Ready WO');
        Date todayDate = Date.today();
        Datetime januaryEarliest = Datetime.newInstance(
            Date.newInstance(todayDate.year(), 1, 8),
            Time.newInstance(8, 0, 0, 0)
        );
        ServiceAppointment readyAppointment = buildAppointment(
            workOrderRecord.Id,
            'None',
            null,
            null,
            'Preset January Ready SA'
        );
        readyAppointment.EarliestStartTime = januaryEarliest;
        readyAppointment.DueDate = januaryEarliest.addDays(7);
        insert readyAppointment;
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle thisYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(90L, null, thisYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle thisMonthRuntime =
            BillingControl_WorkOrderLedger.getRuntime(
                91L,
                null,
                dateWindow(
                    Date.newInstance(todayDate.year(), todayDate.month(), 1),
                    Date.newInstance(todayDate.year(), todayDate.month(), 1).addMonths(1).addDays(-1)
                )
            );
        Integer quarterStartMonth = (((todayDate.month() - 1) / 3) * 3) + 1;
        BillingControl_WorkOrderLedger.RuntimeBundle thisQuarterRuntime =
            BillingControl_WorkOrderLedger.getRuntime(
                92L,
                null,
                dateWindow(
                    Date.newInstance(todayDate.year(), quarterStartMonth, 1),
                    Date.newInstance(todayDate.year(), quarterStartMonth, 1).addMonths(3).addDays(-1)
                )
            );
        BillingControl_WorkOrderLedger.RuntimeBundle lastYearRuntime =
            BillingControl_WorkOrderLedger.getRuntime(93L, null, lastYearWindow(todayDate));
        BillingControl_WorkOrderLedger.RuntimeBundle customJanuaryRuntime =
            BillingControl_WorkOrderLedger.getRuntime(
                94L,
                null,
                dateWindow(
                    Date.newInstance(todayDate.year(), 1, 1),
                    Date.newInstance(todayDate.year(), 1, 31)
                )
            );
        Test.stopTest();

        System.assertNotEquals(null, findAnyRow(thisYearRuntime.sections, workOrderRecord.Id));
        System.assertNotEquals(null, findAnyRow(customJanuaryRuntime.sections, workOrderRecord.Id));
        System.assertEquals(null, findAnyRow(lastYearRuntime.sections, workOrderRecord.Id));
        if (todayDate.month() != 1) {
            System.assertEquals(null, findAnyRow(thisMonthRuntime.sections, workOrderRecord.Id));
        }
        if (quarterStartMonth != 1) {
            System.assertEquals(null, findAnyRow(thisQuarterRuntime.sections, workOrderRecord.Id));
        }
    }

    /**
     * Mirrors production Work Order 00001935: an invoiced Work Order carrying billing history plus
     * new un-invoiced Scheduled work inside the window. It must stay on the operational ledger.
     */
    @IsTest
    static void billingHistoryDoesNotHideOpenAppointments() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Golden Shape Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Golden Shape Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Golden Shape Opp', 900);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Golden Shape WO');
        workOrderRecord.Invoice_Number__c = 'Inv 93122';
        update workOrderRecord;

        Date todayDate = Date.today();
        Date windowStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Date windowEnd = windowStart.addMonths(1).addDays(-1);
        Datetime inWindowStart = Datetime.newInstance(windowStart.addDays(9), Time.newInstance(9, 0, 0, 0));
        Datetime outOfWindowStart = Datetime.newInstance(windowEnd.addDays(3), Time.newInstance(9, 0, 0, 0));
        Datetime completedInWindow = Datetime.newInstance(windowStart.addDays(4), Time.newInstance(14, 0, 0, 0));

        ServiceAppointment invoicedScheduled = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            inWindowStart,
            null,
            'Golden Invoiced Scheduled SA'
        );
        invoicedScheduled.Invoice_Number__c = 'Inv 93122';
        ServiceAppointment openScheduledOne = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            inWindowStart.addHours(2),
            null,
            'Golden Open Scheduled SA One'
        );
        ServiceAppointment openScheduledTwo = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            inWindowStart.addHours(4),
            null,
            'Golden Open Scheduled SA Two'
        );
        ServiceAppointment nextMonthScheduled = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            outOfWindowStart,
            null,
            'Golden Next Month Scheduled SA'
        );
        ServiceAppointment completedInvoiced = buildAppointment(
            workOrderRecord.Id,
            'Completed',
            completedInWindow.addHours(-2),
            completedInWindow,
            'Golden Completed SA'
        );
        completedInvoiced.Invoice_Number__c = 'Inv 93122';
        insert new List<ServiceAppointment>{
            invoicedScheduled,
            openScheduledOne,
            openScheduledTwo,
            nextMonthScheduled,
            completedInvoiced
        };
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(120L, null, dateWindow(windowStart, windowEnd));
        Test.stopTest();

        System.assertEquals(
            1,
            countOperationalOccurrences(runtime.sections, workOrderRecord.Id),
            'The Work Order appears exactly once despite its billing history.'
        );
        BillingControl_Orders.WorkOrderRowWrapper row =
            findRow(findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows, workOrderRecord.Id);
        System.assertNotEquals(null, row, 'Open Scheduled work wins the bucket.');

        Set<Id> relatedIds = new Set<Id>();
        for (BillingControl_Orders.WorkOrderRowWrapper related : row.relatedServiceAppointments) {
            relatedIds.add(related.serviceAppointmentId);
        }
        System.assertEquals(
            new Set<Id>{ invoicedScheduled.Id, openScheduledOne.Id, openScheduledTwo.Id },
            relatedIds,
            'Every in-window Scheduled appointment attaches, invoiced or not, so the history is visible.'
        );
        System.assertEquals(
            false,
            row.billedBadge,
            'A row with un-invoiced work left is not marked fully billed.'
        );
        for (BillingControl_Orders.WorkOrderRowWrapper related : row.relatedServiceAppointments) {
            Boolean expectedBilled = related.serviceAppointmentId == invoicedScheduled.Id;
            System.assertEquals(
                expectedBilled,
                related.billedBadge,
                'Invoiced appointments are marked, not hidden.'
            );
            System.assertEquals(
                expectedBilled,
                related.serviceAppointmentDisplay.contains('Billed'),
                'The visible appointment text tells accounting which visits are already invoiced.'
            );
        }
    }

    @IsTest
    static void workOrderInvoiceStatusDoesNotBrandEveryAppointmentBilled() {
        ServiceAppointment ownInvoice = new ServiceAppointment(Invoice_Number__c = 'Inv 93122');
        ServiceAppointment parentInvoiceOnly = new ServiceAppointment(Invoice_Number__c = null);
        ServiceAppointment noInvoice = new ServiceAppointment();

        System.assertEquals(
            true,
            BillingControl_WorkOrderLedger.isBilledAppointment(ownInvoice),
            'An appointment with its own invoice number is billed.'
        );
        System.assertEquals(
            false,
            BillingControl_WorkOrderLedger.isBilledAppointment(parentInvoiceOnly),
            'The parent Work Order invoice status must not mark an un-invoiced visit as billed.'
        );
        System.assertEquals(
            false,
            BillingControl_WorkOrderLedger.isBilledAppointment(noInvoice),
            'An appointment with no invoice number is not billed.'
        );
        System.assertEquals(
            false,
            BillingControl_WorkOrderLedger.isFullyBilled(
                new List<ServiceAppointment>{ ownInvoice, noInvoice }
            ),
            'A row keeps outstanding work while any visit is un-invoiced.'
        );
    }

    @IsTest
    static void kpiRevenueCountsOnlyUnbilledAppointments() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Partial Billing Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Partial Billing Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Partial Billing Opp', 900);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Partial Billing WO');

        Date todayDate = Date.today();
        Date windowStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Date windowEnd = windowStart.addMonths(1).addDays(-1);
        Datetime scheduledStart = Datetime.newInstance(windowStart.addDays(8), Time.newInstance(9, 0, 0, 0));

        // One 900 Opportunity covers this Work Order's three visits, so each visit is worth 300.
        ServiceAppointment billedVisit = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            scheduledStart,
            null,
            'Partial Billed Visit'
        );
        billedVisit.Invoice_Number__c = 'Inv 90100';
        ServiceAppointment openVisitOne = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            scheduledStart.addHours(2),
            null,
            'Partial Open Visit One'
        );
        ServiceAppointment openVisitTwo = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            scheduledStart.addHours(4),
            null,
            'Partial Open Visit Two'
        );
        insert new List<ServiceAppointment>{ billedVisit, openVisitOne, openVisitTwo };
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(125L, null, dateWindow(windowStart, windowEnd));
        Test.stopTest();

        BillingControl_Orders.WorkOrderRowWrapper row =
            findRow(findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows, workOrderRecord.Id);
        System.assertNotEquals(null, row, 'The partly billed Work Order stays on the ledger.');
        System.assertEquals(3, row.relatedServiceAppointments.size(), 'All three visits stay visible.');
        System.assertEquals(
            600,
            row.operationalAmount,
            'Only the two un-invoiced visits contribute, at 300 each.'
        );
        System.assertEquals(
            600,
            runtime.kpis.scheduledRevenue,
            'Bucket revenue excludes the already invoiced visit.'
        );
        System.assertEquals(1, runtime.kpis.scheduledCount, 'The Work Order still counts once.');
    }

    @IsTest
    static void workOrderWithoutOpportunityReportsNoValueNotZero() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'No Opportunity Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('No Opportunity Type', 1);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'No Opportunity WO');
        Date todayDate = Date.today();
        Date windowStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Datetime scheduledStart = Datetime.newInstance(windowStart.addDays(10), Time.newInstance(9, 0, 0, 0));
        insert buildAppointment(workOrderRecord.Id, 'Scheduled', scheduledStart, null, 'No Opportunity SA');
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime = BillingControl_WorkOrderLedger.getRuntime(
            126L,
            null,
            dateWindow(windowStart, windowStart.addMonths(1).addDays(-1))
        );
        Test.stopTest();

        BillingControl_Orders.WorkOrderRowWrapper row =
            findRow(findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows, workOrderRecord.Id);
        System.assertNotEquals(null, row, 'A Work Order with no Opportunity still shows its open work.');
        System.assertEquals(
            null,
            row.operationalAmount,
            'No linked Opportunity means no value is known, so the row stays unpriced.'
        );
        System.assertEquals(
            null,
            row.opportunityAmount,
            'No linked Opportunity leaves the Opportunity amount unset.'
        );
        System.assertEquals(
            1,
            runtime.kpis.scheduledCount,
            'The Work Order still counts as outstanding work.'
        );
    }

    @IsTest
    static void fullyBilledWorkOrderStaysVisibleButOutOfKpis() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Invoiced Only Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Invoiced Only Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Invoiced Only Opp', 100);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Invoiced Only WO');
        Date todayDate = Date.today();
        Datetime scheduledStart = Datetime.newInstance(
            Date.newInstance(todayDate.year(), todayDate.month(), 1).addDays(5),
            Time.newInstance(9, 0, 0, 0)
        );
        ServiceAppointment invoicedScheduled = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            scheduledStart,
            null,
            'Invoiced Only Scheduled SA'
        );
        invoicedScheduled.Invoice_Number__c = 'Inv 90001';
        insert invoicedScheduled;
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle runtime =
            BillingControl_WorkOrderLedger.getRuntime(121L, null, thisYearWindow(todayDate));
        Test.stopTest();

        BillingControl_Orders.WorkOrderRowWrapper row =
            findRow(findSection(runtime.sections, 'SCHEDULED_APPOINTMENTS').rows, workOrderRecord.Id);
        System.assertNotEquals(
            null,
            row,
            'A re-openable billed Work Order keeps its operational history on the ledger.'
        );
        System.assertEquals(true, row.billedBadge, 'The row is marked fully billed.');
        System.assertEquals(
            0,
            runtime.kpis.scheduledCount,
            'Fully billed work does not inflate the outstanding Scheduled count.'
        );
        System.assertEquals(
            0,
            runtime.kpis.scheduledRevenue,
            'Fully billed work does not inflate operational revenue.'
        );
    }

    @IsTest
    static void ledgerDetailWindowLimitsAppointmentsToRange() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Detail Window Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Detail Window Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Detail Window Opp', 500);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Detail Window WO');

        Date todayDate = Date.today();
        Date windowStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Date windowEnd = windowStart.addMonths(1).addDays(-1);
        Datetime inWindow = Datetime.newInstance(windowStart.addDays(6), Time.newInstance(10, 0, 0, 0));
        Datetime priorYear = Datetime.newInstance(
            Date.newInstance(todayDate.year() - 1, 6, 15),
            Time.newInstance(10, 0, 0, 0)
        );

        ServiceAppointment inRangeScheduled = buildAppointment(
            workOrderRecord.Id,
            'Scheduled',
            inWindow,
            null,
            'Detail In Range Scheduled SA'
        );
        ServiceAppointment inRangeCompleted = buildAppointment(
            workOrderRecord.Id,
            'Completed',
            inWindow.addHours(-3),
            inWindow.addHours(-1),
            'Detail In Range Completed SA'
        );
        ServiceAppointment priorYearCompleted = buildAppointment(
            workOrderRecord.Id,
            'Completed',
            priorYear.addHours(-2),
            priorYear,
            'Detail Prior Year Completed SA'
        );
        insert new List<ServiceAppointment>{ inRangeScheduled, inRangeCompleted, priorYearCompleted };
        insert new Opportunity_WorkOrder__c(Work_Order__c = workOrderRecord.Id, Opportunity__c = opportunityRecord.Id);
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });
        Work_Order_Ledger__c ledgerRecord = [
            SELECT Id FROM Work_Order_Ledger__c WHERE Work_Order__c = :workOrderRecord.Id LIMIT 1
        ];

        Test.startTest();
        BillingControl_WorkOrderLedger.LedgerDetailWrapper windowed =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(
                ledgerRecord.Id,
                dateWindow(windowStart, windowEnd)
            );
        BillingControl_WorkOrderLedger.LedgerDetailWrapper fullDiary =
            BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerRecord.Id);
        Test.stopTest();

        Set<Id> windowedIds = new Set<Id>();
        for (BillingControl_WorkOrderLedger.LedgerAppointmentWrapper appointmentRow : windowed.appointments) {
            windowedIds.add(appointmentRow.serviceAppointmentId);
        }
        System.assertEquals(
            new Set<Id>{ inRangeScheduled.Id, inRangeCompleted.Id },
            windowedIds,
            'The drill-in shows every in-range appointment and nothing outside the window.'
        );
        System.assertEquals(
            3,
            fullDiary.appointments.size(),
            'Without a window the ledger stays a full diary for the record page.'
        );
    }

    @IsTest
    static void windowedDetailExcludesAppointmentsWithoutAStateOwnedDate() {
        BillingControl_WorkOrderLedger.DateTimeRange august =
            new BillingControl_WorkOrderLedger.DateTimeRange();
        august.rangeStart = Datetime.newInstance(Date.newInstance(2026, 8, 1), Time.newInstance(0, 0, 0, 0));
        august.rangeEnd = Datetime.newInstance(Date.newInstance(2026, 8, 31), Time.newInstance(23, 59, 59, 0));
        ServiceAppointment undated = new ServiceAppointment();
        ServiceAppointment inRange = new ServiceAppointment(
            SchedStartTime = Datetime.newInstance(Date.newInstance(2026, 8, 17), Time.newInstance(8, 0, 0, 0)),
            SchedEndTime = Datetime.newInstance(Date.newInstance(2026, 8, 17), Time.newInstance(9, 0, 0, 0))
        );

        System.assertEquals(
            false,
            BillingControl_WorkOrderLedger.isAppointmentInDetailRange(undated, august),
            'An appointment with no state-owned date is not in a complete window.'
        );
        System.assertEquals(
            true,
            BillingControl_WorkOrderLedger.isAppointmentInDetailRange(inRange, august),
            'A Scheduled appointment whose start is inside the window stays visible.'
        );
        System.assertEquals(
            true,
            BillingControl_WorkOrderLedger.isAppointmentInDetailRange(undated, new BillingControl_WorkOrderLedger.DateTimeRange()),
            'Without a window the record-page diary still includes undated appointments.'
        );
    }

    @IsTest
    static void opportunityJunctionsDoNotChangeBucketMembership() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Attribution Isolation Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Attribution Isolation Type', 1);
        Opportunity firstOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Attribution Opp One', 300);
        Opportunity secondOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Attribution Opp Two', 400);
        WorkOrder workOrderRecord = insertWorkOrder(accountRecord.Id, workTypeRecord.Id, 'Attribution Isolation WO');
        Date todayDate = Date.today();
        Datetime scheduledStart = Datetime.newInstance(
            Date.newInstance(todayDate.year(), todayDate.month(), 1).addDays(7),
            Time.newInstance(9, 0, 0, 0)
        );
        insert buildAppointment(workOrderRecord.Id, 'Scheduled', scheduledStart, null, 'Attribution Scheduled SA');
        Opportunity_WorkOrder__c firstJunction = new Opportunity_WorkOrder__c(
            Work_Order__c = workOrderRecord.Id,
            Opportunity__c = firstOpportunity.Id
        );
        insert firstJunction;
        WorkOrderLedgerService.backfillWorkOrders(new Set<Id>{ workOrderRecord.Id });

        Test.startTest();
        BillingControl_WorkOrderLedger.RuntimeBundle oneJunction =
            BillingControl_WorkOrderLedger.getRuntime(122L, null, thisYearWindow(todayDate));
        insert new Opportunity_WorkOrder__c(
            Work_Order__c = workOrderRecord.Id,
            Opportunity__c = secondOpportunity.Id
        );
        BillingControl_WorkOrderLedger.RuntimeBundle twoJunctions =
            BillingControl_WorkOrderLedger.getRuntime(123L, null, thisYearWindow(todayDate));
        delete [SELECT Id FROM Opportunity_WorkOrder__c WHERE Work_Order__c = :workOrderRecord.Id];
        BillingControl_WorkOrderLedger.RuntimeBundle noJunctions =
            BillingControl_WorkOrderLedger.getRuntime(124L, null, thisYearWindow(todayDate));
        Test.stopTest();

        System.assertEquals(1, countOperationalOccurrences(oneJunction.sections, workOrderRecord.Id));
        System.assertEquals(
            1,
            countOperationalOccurrences(twoJunctions.sections, workOrderRecord.Id),
            'A second Opportunity link does not duplicate or move the Work Order.'
        );
        System.assertEquals(
            1,
            countOperationalOccurrences(noJunctions.sections, workOrderRecord.Id),
            'Removing every Opportunity link does not remove the Work Order from its date bucket.'
        );
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

    private static Integer countOperationalOccurrences(
        List<BillingControl_Orders.BucketSectionWrapper> sections,
        Id workOrderId
    ) {
        Integer matchCount = 0;
        if (sections == null) {
            return matchCount;
        }
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            matchCount += countRows(sectionRecord.rows, workOrderId);
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

    private static BillingControl_Orders.WorkOrderRowWrapper findAnyRow(
        List<BillingControl_Orders.BucketSectionWrapper> sections,
        Id workOrderId
    ) {
        if (sections == null) {
            return null;
        }
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            BillingControl_Orders.WorkOrderRowWrapper match = findRow(sectionRecord.rows, workOrderId);
            if (match != null) {
                return match;
            }
        }
        return null;
    }

    private static BillingControl_DataProvider.DateRangeDTO dateWindow(Date startDate, Date endDate) {
        return new BillingControl_DataProvider.DateRangeDTO(startDate, endDate);
    }

    private static BillingControl_DataProvider.DateRangeDTO thisYearWindow(Date todayDate) {
        return dateWindow(
            Date.newInstance(todayDate.year(), 1, 1),
            Date.newInstance(todayDate.year(), 12, 31)
        );
    }

    private static BillingControl_DataProvider.DateRangeDTO lastYearWindow(Date todayDate) {
        return dateWindow(
            Date.newInstance(todayDate.year() - 1, 1, 1),
            Date.newInstance(todayDate.year() - 1, 12, 31)
        );
    }

    private static BillingControl_DataProvider.BillingFilterDTO buildEqualsFilter(
        String developerKey,
        String objectApiName,
        String fieldApiName,
        String value
    ) {
        BillingControl_DataProvider.BillingFilterDTO filterRecord =
            new BillingControl_DataProvider.BillingFilterDTO();
        filterRecord.developerKey = developerKey;
        filterRecord.objectApiName = objectApiName;
        filterRecord.fieldApiName = fieldApiName;
        filterRecord.operator = 'Equals';
        filterRecord.valueType = 'Static';
        filterRecord.value = value;
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

    private static String firstClosedWorkOrderStatus() {
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        for (Schema.PicklistEntry picklistEntry : WorkOrder.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && closedStatuses.contains(picklistEntry.getValue())) {
                return picklistEntry.getValue();
            }
        }
        return null;
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