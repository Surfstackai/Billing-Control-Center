@IsTest
private class BillingControl_BillingReadinessTest {
    @IsTest
    static void groupsCompletedVisitsOntoOneOpportunityRow() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Readiness Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Readiness Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Ready to Bill Opp', 5000);

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

        System.assertEquals(1, runtime.metrics.balancesReadyCount, 'Three visits on one Opportunity is one Ready to Bill row.');
        System.assertEquals(1, tabRuntime.metrics.balancesReadyCount);
        System.assertEquals(4, tabRuntime.groups.size());
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
        BillingControl_BillingReadiness.TabRuntime pastWindow = BillingControl_BillingReadiness.getTabRuntime(
            2L,
            'Custom',
            '2000-01-01',
            '2000-01-02',
            null
        );
        BillingControl_BillingReadiness.TabRuntime ownerMatch = BillingControl_BillingReadiness.getTabRuntime(
            3L,
            'This Month',
            String.valueOf(Date.today().addYears(-1)),
            String.valueOf(Date.today()),
            UserInfo.getUserId()
        );
        Test.stopTest();

        System.assertEquals(1, runtime.metrics.depositsDueCount);
        BillingControl_BillingReadiness.OpportunityRow row = firstRow(runtime, BillingControl_BillingReadiness.SECTION_DEPOSITS_DUE);
        System.assertEquals(opportunityRecord.Id, row.opportunityId);
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_DEPOSIT_DUE));
        System.assertEquals(0, row.completedEvidenceCount);
        System.assertEquals(
            1,
            pastWindow.metrics.depositsDueCount,
            'Deposit Due is not suppressed by the completed-visit date window.'
        );
        System.assertEquals(1, ownerMatch.metrics.depositsDueCount, 'Owner filter still includes the current owner.');

        List<User> otherUsers = [
            SELECT Id
            FROM User
            WHERE Id != :UserInfo.getUserId()
            AND IsActive = true
            LIMIT 1
        ];
        if (!otherUsers.isEmpty()) {
            BillingControl_BillingReadiness.TabRuntime ownerMiss = BillingControl_BillingReadiness.getTabRuntime(
                4L,
                'This Month',
                String.valueOf(Date.today().addYears(-1)),
                String.valueOf(Date.today()),
                otherUsers[0].Id
            );
            System.assertEquals(
                0,
                ownerMiss.metrics.depositsDueCount,
                'Owner filtering still excludes Deposit Due Opportunities owned by someone else.'
            );
        }
    }

    @IsTest
    static void readyToBillIncludesFullyInvoicedQuoteWithUnbilledVisit() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('Fully Invoiced Extra Visit', 10000);
        ServiceAppointment billedVisit = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-3),
            'Billed SA'
        );
        ServiceAppointment unbilledVisit = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-1),
            'Unbilled SA'
        );
        insert new List<ServiceAppointment>{ billedVisit, unbilledVisit };
        insertBalanceInvoice(fixture, billedVisit.Id, 10000, 'INV-FULL-10000');

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        BillingControl_BillingReadiness.OpportunityRow row = firstRow(
            runtime,
            BillingControl_BillingReadiness.SECTION_BALANCES_READY
        );
        System.assertEquals(fixture.opportunityId, row.opportunityId);
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_BALANCE_READY));
        System.assertEquals(
            false,
            row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_UNDER_INVOICED),
            'Unbilled attributed work is Ready to Bill, not Balance Remaining.'
        );
    }

    @IsTest
    static void readyToBillAbsentWhenAllAttributedVisitsAreBilled() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('All Visits Billed At Quote', 5000);
        ServiceAppointment billedVisit = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-2),
            'Billed At Quote SA'
        );
        insert billedVisit;
        insertBalanceInvoice(fixture, billedVisit.Id, 5000, 'INV-AT-QUOTE');

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(0, runtime.metrics.balancesReadyCount);
        System.assertEquals(0, runtime.metrics.underInvoicedCount);
        System.assertEquals(false, sectionContains(runtime, BillingControl_BillingReadiness.SECTION_BALANCES_READY, fixture.opportunityId));
    }

    @IsTest
    static void balanceRemainingRequiresAllAttributedVisitsBilledBelowQuote() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture billedFixture = createVisitFixture('Balance Remaining Opp', 10000);
        ServiceAppointment billedVisit = completedAppointment(
            billedFixture.workOrderId,
            billedFixture.opportunityId,
            Datetime.now().addHours(-2),
            'Billed Below Quote SA'
        );
        insert billedVisit;
        insertBalanceInvoice(billedFixture, billedVisit.Id, 4000, 'INV-BELOW-QUOTE');

        Fixture unbilledFixture = createVisitFixture('Still Unbilled Opp', 8000);
        insert completedAppointment(
            unbilledFixture.workOrderId,
            unbilledFixture.opportunityId,
            Datetime.now().addHours(-1),
            'Still Unbilled SA'
        );

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        BillingControl_BillingReadiness.OpportunityRow remainingRow = firstRow(
            runtime,
            BillingControl_BillingReadiness.SECTION_UNDER_INVOICED
        );
        System.assertEquals(billedFixture.opportunityId, remainingRow.opportunityId);
        System.assertEquals(true, remainingRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_UNDER_INVOICED));
        System.assertEquals(
            false,
            sectionContains(runtime, BillingControl_BillingReadiness.SECTION_UNDER_INVOICED, unbilledFixture.opportunityId)
        );
        System.assertEquals(
            true,
            sectionContains(runtime, BillingControl_BillingReadiness.SECTION_BALANCES_READY, unbilledFixture.opportunityId)
        );
    }

    @IsTest
    static void missingAmountAndInvalidInvoiceNumberAreNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Review Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Review Type', 1);
        Opportunity missingAmount = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'No Amount Opp', null);
        Opportunity reviewOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Review Opp', 2500);
        WorkOrder missingWorkOrder = new WorkOrder(
            Subject = 'No Amount WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert missingWorkOrder;
        insert new Opportunity_WorkOrder__c(Opportunity__c = missingAmount.Id, Work_Order__c = missingWorkOrder.Id);

        WorkOrder reviewWorkOrder = new WorkOrder(
            Subject = 'Review WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert reviewWorkOrder;
        insert new Opportunity_WorkOrder__c(Opportunity__c = reviewOpportunity.Id, Work_Order__c = reviewWorkOrder.Id);

        Datetime endTime = Datetime.now().addHours(-1);
        ServiceAppointment missingAppointment = completedAppointment(
            missingWorkOrder.Id,
            missingAmount.Id,
            endTime,
            'No Amount SA'
        );
        ServiceAppointment reviewAppointment = completedAppointment(
            reviewWorkOrder.Id,
            reviewOpportunity.Id,
            endTime.addMinutes(-5),
            'Review SA'
        );
        reviewAppointment.Invoice_Number__c = 'Inspection to Quote';
        insert new List<ServiceAppointment>{ missingAppointment, reviewAppointment };

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(true, runtime.metrics.needsReviewCount >= 2);
        BillingControl_BillingReadiness.OpportunityRow missingRow = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            missingAmount.Id
        );
        System.assertEquals(true, missingRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_MISSING_QUOTE_AMOUNT));
        System.assertEquals(true, missingRow.showReviewBanner);
        BillingControl_BillingReadiness.OpportunityRow reviewRow = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            reviewOpportunity.Id
        );
        System.assertEquals(true, reviewRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_INVOICE_REFERENCE));
        System.assertEquals(true, reviewRow.showReviewBanner);
    }

    @IsTest
    static void unresolvedMultiOpportunityAttributionIsNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Attribution Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Attribution Type', 1);
        Opportunity firstOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Attr Opp A', 3000);
        Opportunity secondOpportunity = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'Attr Opp B', 4000);
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Multi Opp WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = firstOpportunity.Id, Work_Order__c = workOrderRecord.Id),
            new Opportunity_WorkOrder__c(Opportunity__c = secondOpportunity.Id, Work_Order__c = workOrderRecord.Id)
        };
        insert completedAppointment(workOrderRecord.Id, null, Datetime.now().addHours(-1), 'Unassigned SA');

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        BillingControl_BillingReadiness.OpportunityRow attributionRow = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            firstOpportunity.Id
        );
        System.assertEquals(true, attributionRow.readinessReasons.contains(BillingControl_BillingReadiness.REASON_VISIT_UNASSIGNED));
        System.assertEquals(true, attributionRow.showReviewBanner);
        Boolean sawUnattributedVisit = false;
        for (BillingControl_BillingReadiness.WorkOrderEvidence workOrder : attributionRow.workOrders) {
            for (BillingControl_BillingReadiness.AppointmentEvidence appointment : workOrder.appointments) {
                if (appointment.unattributed == true) {
                    sawUnattributedVisit = true;
                }
            }
        }
        System.assertEquals(true, sawUnattributedVisit, 'Needs Review still identifies the unassigned visit.');
    }

    @IsTest
    static void ordinaryNotesDoNotCreateNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture descriptionFixture = createVisitFixture('Description Only Opp', 2000);
        ServiceAppointment descriptionVisit = completedAppointment(
            descriptionFixture.workOrderId,
            descriptionFixture.opportunityId,
            Datetime.now().addHours(-3),
            'Description SA'
        );
        descriptionVisit.Description = 'Technician documented pit conditions.';
        insert descriptionVisit;

        Fixture noteFixture = createVisitFixture('Service Note Only Opp', 2100);
        ServiceAppointment noteVisit = completedAppointment(
            noteFixture.workOrderId,
            noteFixture.opportunityId,
            Datetime.now().addHours(-2),
            'Service Note SA'
        );
        noteVisit.ServiceNote = 'Replaced the float switch.';
        insert noteVisit;

        Id internalNoteOpportunityId;
        if (Schema.sObjectType.ServiceAppointment.fields.getMap().containsKey('Internal_Service_Note__c')) {
            Fixture internalFixture = createVisitFixture('Internal Note Only Opp', 2200);
            ServiceAppointment internalVisit = completedAppointment(
                internalFixture.workOrderId,
                internalFixture.opportunityId,
                Datetime.now().addHours(-1),
                'Internal Note SA'
            );
            internalVisit.put('Internal_Service_Note__c', 'Internal follow-up only.');
            insert internalVisit;
            internalNoteOpportunityId = internalFixture.opportunityId;
        }

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(
            false,
            sectionContains(runtime, BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW, descriptionFixture.opportunityId)
        );
        System.assertEquals(
            false,
            sectionContains(runtime, BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW, noteFixture.opportunityId)
        );
        if (internalNoteOpportunityId != null) {
            System.assertEquals(
                false,
                sectionContains(runtime, BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW, internalNoteOpportunityId)
            );
        }
    }

    @IsTest
    static void denyListInvoiceTextIsNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('Deny List Opp', 1500);
        ServiceAppointment appointmentRecord = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-1),
            'Deny List SA'
        );
        appointmentRecord.Invoice_Number__c = 'no bill as per dw';
        insert appointmentRecord;

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        BillingControl_BillingReadiness.OpportunityRow row = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            fixture.opportunityId
        );
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_INVOICE_REFERENCE));
    }

    @IsTest
    static void flagAppointmentForReviewWritesBillingReviewFlag() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('Flag Opp', 1000);
        ServiceAppointment appointmentRecord = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-1),
            'Flag SA'
        );
        insert appointmentRecord;

        Test.startTest();
        BillingControl_BillingReadiness.flagAppointmentForReview(appointmentRecord.Id);
        Test.stopTest();

        List<Work_Order_Ledger_Entry__c> flags = [
            SELECT Id, Event_Type__c, Service_Appointment__c, Description__c
            FROM Work_Order_Ledger_Entry__c
            WHERE Event_Type__c = :BillingControl_BillingReadiness.EVENT_BILLING_REVIEW_FLAG
            AND Service_Appointment__c = :appointmentRecord.Id
        ];
        System.assertEquals(1, flags.size(), 'Flag for review writes one BILLING_REVIEW_FLAG.');
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        BillingControl_BillingReadiness.OpportunityRow row = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            fixture.opportunityId
        );
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_FLAGGED_BY_ACCOUNTING));
        System.assertEquals(true, row.showReviewBanner);
        System.assertEquals(true, visitIsFlagged(row, appointmentRecord.Id));
    }

    @IsTest
    static void ordinaryAccountingNoteDoesNotTriggerNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('Ordinary Note Opp', 1800);
        ServiceAppointment appointmentRecord = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-1),
            'Ordinary Note SA'
        );
        insert appointmentRecord;
        persistLedgerEvent(
            fixture.workOrderId,
            appointmentRecord.Id,
            fixture.opportunityId,
            'ACCOUNTING_NOTE',
            'Follow up with customer about payment terms.'
        );

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        System.assertEquals(
            false,
            sectionContains(runtime, BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW, fixture.opportunityId),
            'A generic ACCOUNTING_NOTE must not become Needs Review.'
        );
        BillingControl_BillingReadiness.OpportunityRow row = firstRow(
            runtime,
            BillingControl_BillingReadiness.SECTION_BALANCES_READY
        );
        System.assertEquals(false, visitIsFlagged(row, appointmentRecord.Id));
        System.assertEquals(false, row.showReviewBanner);
    }

    @IsTest
    static void legacyAccountingNoteFlagPrefixStillTriggersNeedsReview() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createVisitFixture('Legacy Flag Opp', 1900);
        ServiceAppointment appointmentRecord = completedAppointment(
            fixture.workOrderId,
            fixture.opportunityId,
            Datetime.now().addHours(-1),
            'Legacy Flag SA'
        );
        insert appointmentRecord;
        persistLedgerEvent(
            fixture.workOrderId,
            appointmentRecord.Id,
            fixture.opportunityId,
            'ACCOUNTING_NOTE',
            BillingControl_BillingReadiness.FLAG_FOR_REVIEW_DESCRIPTION_PREFIX + ' SA-LEGACY'
        );

        Test.startTest();
        BillingControl_BillingReadiness.Runtime runtime = BillingControl_BillingReadiness.load(null);
        Test.stopTest();

        BillingControl_BillingReadiness.OpportunityRow row = rowForOpportunity(
            runtime,
            BillingControl_BillingReadiness.SECTION_NEEDS_REVIEW,
            fixture.opportunityId
        );
        System.assertEquals(true, row.readinessReasons.contains(BillingControl_BillingReadiness.REASON_FLAGGED_BY_ACCOUNTING));
        System.assertEquals(true, visitIsFlagged(row, appointmentRecord.Id));
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

    private static BillingControl_BillingReadiness.OpportunityRow rowForOpportunity(
        BillingControl_BillingReadiness.Runtime runtime,
        String sectionKey,
        Id opportunityId
    ) {
        for (BillingControl_BillingReadiness.SectionWrapper section : runtime.sections) {
            if (section.categoryKey != sectionKey || section.rows == null) {
                continue;
            }
            for (BillingControl_BillingReadiness.OpportunityRow row : section.rows) {
                if (row.opportunityId == opportunityId) {
                    return row;
                }
            }
        }
        System.assert(false, 'Expected Opportunity in ' + sectionKey + ': ' + opportunityId);
        return null;
    }

    private static Boolean sectionContains(
        BillingControl_BillingReadiness.Runtime runtime,
        String sectionKey,
        Id opportunityId
    ) {
        for (BillingControl_BillingReadiness.SectionWrapper section : runtime.sections) {
            if (section.categoryKey != sectionKey || section.rows == null) {
                continue;
            }
            for (BillingControl_BillingReadiness.OpportunityRow row : section.rows) {
                if (row.opportunityId == opportunityId) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Boolean visitIsFlagged(
        BillingControl_BillingReadiness.OpportunityRow row,
        Id serviceAppointmentId
    ) {
        if (row == null || row.workOrders == null) {
            return false;
        }
        for (BillingControl_BillingReadiness.WorkOrderEvidence workOrder : row.workOrders) {
            if (workOrder.appointments == null) {
                continue;
            }
            for (BillingControl_BillingReadiness.AppointmentEvidence appointment : workOrder.appointments) {
                if (appointment.serviceAppointmentId == serviceAppointmentId) {
                    return appointment.flaggedForReview == true;
                }
            }
        }
        return false;
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

    private static Fixture createVisitFixture(String name, Decimal amount) {
        Account accountRecord = new Account(Name = name + ' Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType(name + ' Type', 1);
        Opportunity opportunityRecord = insertOpportunity(accountRecord.Id, workTypeRecord.Id, name, amount);
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = name + ' WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id
        );
        Fixture fixture = new Fixture();
        fixture.accountId = accountRecord.Id;
        fixture.opportunityId = opportunityRecord.Id;
        fixture.workOrderId = workOrderRecord.Id;
        return fixture;
    }

    private static void insertBalanceInvoice(Fixture fixture, Id serviceAppointmentId, Decimal amount, String invoiceNumber) {
        Invoice__c invoiceRecord = new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = fixture.opportunityId,
            Account__c = fixture.accountId,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = amount,
            Tax_Amount__c = 0,
            Total_Amount__c = amount,
            Amount_Paid__c = 0,
            Balance_Due__c = amount,
            Invoice_Type__c = 'Balance'
        );
        insert invoiceRecord;
        insert new Invoice_Line__c(
            Invoice__c = invoiceRecord.Id,
            Opportunity__c = fixture.opportunityId,
            Work_Order__c = fixture.workOrderId,
            Service_Appointment__c = serviceAppointmentId,
            Description__c = invoiceNumber,
            Quantity__c = 1,
            Unit_Price__c = amount,
            Line_Total__c = amount
        );
    }

    private static void persistLedgerEvent(
        Id workOrderId,
        Id serviceAppointmentId,
        Id opportunityId,
        String eventType,
        String description
    ) {
        WorkOrderLedgerService.LedgerEvent eventRecord = new WorkOrderLedgerService.LedgerEvent();
        eventRecord.WorkOrderId = workOrderId;
        eventRecord.SourceRecordId = serviceAppointmentId;
        eventRecord.EventType = eventType;
        eventRecord.EventDatetime = System.now();
        eventRecord.ChangedById = UserInfo.getUserId();
        eventRecord.ServiceAppointmentId = serviceAppointmentId;
        eventRecord.OpportunityId = opportunityId;
        eventRecord.SourceObject = 'ServiceAppointment';
        eventRecord.Description = description;
        eventRecord.SystemGenerated = false;
        eventRecord.EventKey = eventType + '|' + String.valueOf(serviceAppointmentId) + '|' + String.valueOf(System.now().getTime());
        WorkOrderLedgerService.persistEvents(new List<WorkOrderLedgerService.LedgerEvent>{ eventRecord });
    }

    private class Fixture {
        Id accountId;
        Id opportunityId;
        Id workOrderId;
    }
}
