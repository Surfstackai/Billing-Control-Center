@IsTest
private class BillingControl_MigrationServiceTest {
    @IsTest
    static void previewIsDryRunAndDoesNotVoidInvoices() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Migration Preview Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Migration Preview Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Migration Preview Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 1000,
            CloseDate = Date.today(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        insert new Invoice__c(
            Invoice_Number__c = 'Inv 95001',
            Opportunity__c = opportunityRecord.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Draft',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Amount_Source__c = 'Pending External'
        );

        Test.startTest();
        BillingControl_MigrationService.MigrationReport report = BillingControl_MigrationService.preview();
        Test.stopTest();

        System.assertEquals(true, report.dryRun);
        System.assertEquals(1, [SELECT COUNT() FROM Invoice__c WHERE Invoice_Number__c = 'Inv 95001' AND Status__c = 'Draft']);
        System.assert(report.stubInvoices >= 1);
        System.assert(report.openJobsMissingCommission >= 1);
    }

    @IsTest
    static void previewCountsUniqueJunctionsDepositsAndLeavesExecuteEmpty() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Migration Review Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Migration Review Type', 1);
        Opportunity firstOpportunity = new Opportunity(
            Name = 'Migration Unique Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 2000,
            CloseDate = Date.today(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity secondOpportunity = new Opportunity(
            Name = 'Migration Multi Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 3000,
            CloseDate = Date.today(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ firstOpportunity, secondOpportunity };

        WorkOrder uniqueWorkOrder = new WorkOrder(
            Subject = 'Migration Unique WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 95011-DP 95012',
            Deposit_Payments__c = 'Deposit received',
            Deposit_Amount__c = 250
        );
        WorkOrder multiWorkOrder = new WorkOrder(
            Subject = 'Migration Multi WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 95040',
            Deposit_Amount__c = 400
        );
        insert new List<WorkOrder>{ uniqueWorkOrder, multiWorkOrder };
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = firstOpportunity.Id, Work_Order__c = uniqueWorkOrder.Id),
            new Opportunity_WorkOrder__c(Opportunity__c = firstOpportunity.Id, Work_Order__c = multiWorkOrder.Id),
            new Opportunity_WorkOrder__c(Opportunity__c = secondOpportunity.Id, Work_Order__c = multiWorkOrder.Id)
        };

        ServiceAppointment uniqueAppointment = new ServiceAppointment(
            ParentRecordId = uniqueWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'Migration Unique SA',
            Invoice_Number__c = 'Inv 95021'
        );
        ServiceAppointment multiAppointment = new ServiceAppointment(
            ParentRecordId = multiWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'Migration Multi SA'
        );
        insert new List<ServiceAppointment>{ uniqueAppointment, multiAppointment };

        Test.startTest();
        BillingControl_MigrationService.MigrationReport dryRunReport = BillingControl_MigrationService.preview();
        BillingControl_MigrationService.MigrationReport executeReport = BillingControl_MigrationService.run(false);
        Test.stopTest();

        System.assert(dryRunReport.uniqueJunctionAutoAttributeCandidates >= 1);
        System.assert(dryRunReport.historicalInvoiceTokens >= 2);
        System.assert(dryRunReport.uniqueJunctionDepositSeeds >= 1);
        System.assert(dryRunReport.multiOppDepositReviews >= 1);
        System.assertEquals(true, dryRunReport.dryRun);
        System.assertEquals(false, executeReport.dryRun);
        System.assert(executeReport.attributedAppointments >= 1);
        System.assert(executeReport.invoicesCreated >= 2);
        Boolean reviewedMultiOppTokens = false;
        for (BillingControl_MigrationService.ReviewRow row : executeReport.reviewRows) {
            if (row.detail != null && row.detail.contains('Historical invoice tokens on a multi-Opp')) {
                reviewedMultiOppTokens = true;
            }
        }
        System.assertEquals(true, reviewedMultiOppTokens);
        System.assert(executeReport.depositsSeeded >= 1);
        ServiceAppointment attributed = [
            SELECT Opportunity__c
            FROM ServiceAppointment
            WHERE Id = :uniqueAppointment.Id
        ];
        System.assertEquals(firstOpportunity.Id, attributed.Opportunity__c);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Invoice_Payment__c
                WHERE Invoice__r.Opportunity__c = :firstOpportunity.Id
            ]
        );
        Opportunity seeded = [
            SELECT Deposit_Required__c, Deposit_Timing__c, Deposit_Amount_Required__c
            FROM Opportunity
            WHERE Id = :firstOpportunity.Id
        ];
        System.assertEquals(true, seeded.Deposit_Required__c);
        System.assertEquals('Before Completion', seeded.Deposit_Timing__c);
        System.assertEquals(250, seeded.Deposit_Amount_Required__c);
        System.assert(
            executeReport.commissionsCreated >= 1
            || [
                SELECT COUNT()
                FROM Commission__c
                WHERE Opportunity__c = :firstOpportunity.Id
            ] >= 1,
            'Historical invoices must leave Accrued commission on the unique Opportunity'
        );
    }
}
