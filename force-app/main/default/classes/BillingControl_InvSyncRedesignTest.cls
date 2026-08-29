@IsTest
private class BillingControl_InvSyncRedesignTest {
    @IsTest
    static void parserTokensCreatePendingExternalInvoicesAndRerunIsNoop() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'INV-Sync Multi Token Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Multi Token Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync Multi Token Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 15000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync Multi Token WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 93157-DP 93199'
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(Opportunity__c = opportunityRecord.Id, Work_Order__c = workOrderRecord.Id);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'INV-Sync Multi Token SA',
            Opportunity__c = opportunityRecord.Id
        );
        insert appointmentRecord;

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper firstRun =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        BillingControl_Invoicing.InvSyncResultWrapper secondRun =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(2, firstRun.invoicesCreated);
        System.assertEquals(0, secondRun.invoicesCreated);
        List<Invoice__c> invoices = [
            SELECT Invoice_Number__c, Invoice_Type__c, Amount_Source__c, Status__c, Total_Amount__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
            ORDER BY Invoice_Number__c
        ];
        System.assertEquals(2, invoices.size());
        System.assertEquals('Pending External', invoices[0].Amount_Source__c);
        System.assertEquals(null, invoices[0].Total_Amount__c);
        System.assertEquals('Draft', invoices[0].Status__c);
        Set<String> types = new Set<String>{ invoices[0].Invoice_Type__c, invoices[1].Invoice_Type__c };
        System.assertEquals(true, types.contains('Deposit'));
        System.assertEquals(true, types.contains('Balance'));
        ServiceAppointment stamped = [SELECT Opportunity__c, Invoice_Number__c FROM ServiceAppointment WHERE Id = :appointmentRecord.Id];
        System.assertEquals(opportunityRecord.Id, stamped.Opportunity__c);
        System.assertEquals('Inv 93157, DP 93199', stamped.Invoice_Number__c);
    }

    @IsTest
    static void coalescedExistingHeaderSkipsParsedDigitKeys() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'INV-Sync Coalesced Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Coalesced Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync Coalesced Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 15000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        insert new Invoice__c(
            Invoice_Number__c = 'Inv 93157-DP 93199',
            Opportunity__c = opportunityRecord.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Draft',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Invoice_Type__c = 'Balance',
            Amount_Source__c = 'Pending External'
        );
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync Coalesced WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 93157-DP 93199'
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(Opportunity__c = opportunityRecord.Id, Work_Order__c = workOrderRecord.Id);
        insert new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'INV-Sync Coalesced SA',
            Opportunity__c = opportunityRecord.Id
        );

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper syncResult =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(0, syncResult.invoicesCreated);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Invoice__c WHERE Opportunity__c = :opportunityRecord.Id]
        );
    }

    @IsTest
    static void parserCanonicalAndDigitKeyAndDenyList() {
        List<BillingControl_InvoiceNumberParser.ParsedToken> tokens =
            BillingControl_InvoiceNumberParser.parse('Inv 93157-DP 93199');
        System.assertEquals(2, tokens.size());
        System.assertEquals('Inv 93157', BillingControl_InvoiceNumberParser.canonicalNumber(tokens[0]));
        System.assertEquals('DP 93199', BillingControl_InvoiceNumberParser.canonicalNumber(tokens[1]));
        System.assertEquals('93157', BillingControl_InvoiceNumberParser.digitKey('Inv 93157'));
        System.assertEquals(0, BillingControl_InvoiceNumberParser.parse('waiting for deposit').size());
        System.assertEquals(null, BillingControl_InvoiceNumberParser.canonicalNumber(null));
        System.assertEquals(null, BillingControl_InvoiceNumberParser.digitKey('not-an-invoice'));
    }
}
