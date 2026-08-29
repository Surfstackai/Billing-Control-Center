@IsTest
private class BillingControl_BillingReadinessTest {
    @IsTest
    static void groupsCompletedVisitsOntoOneOpportunityRow() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Readiness Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Readiness Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Balance Ready Opp', 5000);

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(Subject = 'WO A', Status = 'New', AccountId = accountRecord.Id, WorkTypeId = workTypeRecord.Id),
            new WorkOrder(Subject = 'WO B', Status = 'New', AccountId = accountRecord.Id, WorkTypeId = workTypeRecord.Id)
        };
        insert workOrders;
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = opportunityRecord.Id, Work_Order__c = workOrders[0].Id),
            new Opportunity_WorkOrder__c(Opportunity__c = opportunityRecord.Id, Work_Order__c = workOrders[1].Id)
        };

        Datetime endTime = Datetime.now().addHours(-2);
        insert new List<ServiceAppointment>{
            completedAppointment(workOrders[0].Id, opportunityRecord.Id, endTime, 'SA 1'),
            completedAppointment(workOrders[0].Id, opportunityRecord.Id, endTime.addMinutes(-30), 'SA 2'),
            completedAppointment(workOrders[1].Id, opportunityRecord.Id, endTime.addMinutes(-10), 'SA 3')
        };

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        BillingControl_BillingReadiness.TabRuntime tabRuntime = BillingControl_BillingReadiness.getTabRuntime(
            1L,
            'This Month',
            String.valueOf(Date.today().addYears(-1)),
            String.valueOf(Date.today()),
            null
        );
        Test.stopTest();

        System.assertEquals(1, runtime.metrics.balancesReadyCount, 'Five visits on one Opportunity is one Balances Ready row.');
        System.assertEquals(1, tabRuntime.metrics.balancesReadyCount);
        System.assertEquals(5, tabRuntime.groups.size());
        System.assertEquals(1, runtime.metrics.readyToBill);
        BillingControl_BillingReadiness.OpportunityRow row = firstRow(runtime, BillingControl_BillingReadiness.SECTION_BALANCES_READY);
        System.assertEquals(opportunityRecord.Id, row.opportunityId);
        System.assertEquals(2, row.workOrders.size(), 'Evidence tree is Work Order then Service Appointment.');
        System.assertEquals(3, row.completedEvidenceCount);
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_BALANCE_READY));
        System.assertEquals(opportunityRecord.Id, row.workOrders[0].appointments[0].opportunityId);
        System.assertEquals(false, row.workOrders[0].appointments[0].operationalUnassigned);
    }

    @IsTest
    static void depositDueAppearsWithoutCompletedVisits() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Deposit Due Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Deposit Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Deposit Due Opp', 8000);
        opportunityRecord.Deposit_Required__c = true;
        opportunityRecord.Deposit_Timing__c = 'Before Completion';
        update opportunityRecord;

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(1, runtime.metrics.depositsDueCount);
        BillingControl_BillingReadiness.OpportunityRow row = firstRow(runtime, BillingControl_BillingReadiness.SECTION_DEPOSITS_DUE);
        System.assertEquals(opportunityRecord.Id, row.opportunityId);
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_DEPOSIT_DUE));
        System.assertEquals(0, row.completedEvidenceCount);
    }

    @IsTest
    static void nullAmountIsBlockedAndReviewTokenIsNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Blocked Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Blocked Type', 1);
        Opportunity blockedOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'No Amount Opp', null);
        Opportunity reviewOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Review Opp', 2500);
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Blocked WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(Opportunity__c = blockedOpportunity.Id, Work_Order__c = workOrderRecord.Id);

        WorkOrder reviewWorkOrder = new WorkOrder(
            Subject = 'Review WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert reviewWorkOrder;
        insert new Opportunity_WorkOrder__c(Opportunity__c = reviewOpportunity.Id, Work_Order__c = reviewWorkOrder.Id);

        Datetime endTime = Datetime.now().addHours(-1);
        ServiceAppointment blockedAppointment = completedAppointment(
            workOrderRecord.Id,
            blockedOpportunity.Id,
            endTime,
            'Blocked SA'
        );
        ServiceAppointment reviewAppointment = completedAppointment(
            reviewWorkOrder.Id,
            reviewOpportunity.Id,
            endTime.addMinutes(-5),
            'Review SA'
        );
        reviewAppointment.Invoice_Number__c = 'Inspection to Quote';
        insert new List<ServiceAppointment>{ blockedAppointment, reviewAppointment };

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(true, runtime.metrics.blockedCount >= 1);
        System.assertEquals(true, runtime.metrics.needsReviewCount >= 1);
        BillingControl_BillingReadiness.OpportunityRow blockedRow = firstRow(runtime, BillingControl_BillingReadiness.SECTION_BLOCKED);
        System.assertEquals(true, blockedRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_BLOCKED_NO_AMOUNT));
        BillingControl_BillingReadiness.OpportunityRow reviewRow = firstRow(runtime, BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW);
        System.assertEquals(true, reviewRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_REVIEW));
        System.assertEquals(true, reviewRow.showReviewBanner);
    }

    @IsTest
    static void flagAppointmentForReviewWritesAccountingNote() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Flag Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Flag Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Flag Opp', 1000);
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Flag WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id
        );
        ServiceAppointment appointmentRecord = completedAppointment(
            workOrderRecord.Id,
            opportunityRecord.Id,
            Datetime.now().addHours(-1),
            'Flag SA'
        );
        insert appointmentRecord;

        Test.startTest();
        BillingControl_BillingReadiness.flagAppointmentForReview(appointmentRecord.Id);
        Test.stopTest();

        List<Work_Order_Ledger_Entry__c> notes = [
            SELECT Id, Event_Type__c, Service_Appointment__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = 'ACCOUNTING_NOTE'
            AND Service_Appointment__c = :appointmentRecord.Id
        ];
        System.assertEquals(1, notes.size(), 'Flag for review writes one ACCOUNTING_NOTE.');
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Boolean flaggedOnReadModel = false;
        for (BillingControl_BillingReadiness.SectionWrapper section : runtime.sections) {
            if (section.rows == null) {
                continue;
            }
            for (BillingControl_BillingReadiness.OpportunityRow row : section.rows) {
                if (row.workOrders == null) {
                    continue;
                }
                for (BillingControl_BillingReadiness.WorkOrderEvidence workOrder : row.workOrders) {
                    if (workOrder.appointments == null) {
                        continue;
                    }
                    for (BillingControl_BillingReadiness.AppointmentEvidence appointment : workOrder.appointments) {
                        if (appointment.serviceAppointmentId == appointmentRecord.Id) {
                            flaggedOnReadModel = appointment.flaggedForReview == true;
                        }
                    }
                }
            }
        }
        System.assertEquals(true, flaggedOnReadModel, 'Readiness reloads flaggedForReview from ACCOUNTING_NOTE.');
    }

    private static BillingControl_BillingReadiness.OpportunityRow firstRow(
        BillingControl_BillingReadiness.Runtime runtime,
        String sectionKey
    ) {
        for (BillingControl_BillingReadiness.SectionWrapper section : runtime.sections) {
            if (section.categoryKey == sectionKey && !section.rows.isEmpty()) {
                return section.rows[0];
            }
        }
        System.assert(false, 'Expected a row in ' + sectionKey);
        return null;
    }

    private static Opportunity insertOpportunity(Id accountId, Id workTypeId, String name, Decimal amount) {
        Opportunity opportunityRecord = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            Amount = amount,
            CloseDate = Date.today().addDays(10),
            Work_Type__c = workTypeId,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static ServiceAppointment completedAppointment(
        Id workOrderId,
        Id opportunityId,
        Datetime endTime,
        String subject
    ) {
        return new ServiceAppointment(
            ParentRecordId = workOrderId,
            Status = 'Completed',
            SchedStartTime = endTime.addHours(-1),
            SchedEndTime = endTime,
            ActualEndTime = endTime,
            Subject = subject,
            Opportunity__c = opportunityId
        );
    }
}
