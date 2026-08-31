@IsTest
private class BillingControl_InvSyncRedesignTest {
    @IsTest
    static void parserTokensCreatePendingExternalInvoicesAndRerunIsNoop() {
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

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper firstRun =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        BillingControl_Invoicing.InvSyncResultWrapper secondRun =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
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

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper syncResult =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
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

    @isTest
    static void testInvSyncPrefersServiceAppointmentInvoiceNumber() {
        Account accountRecord = new Account(Name = 'INV-Sync SA Wins Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync SA Wins Work Type', 2);

        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync SA Wins Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 250,
            CloseDate = Date.today().addDays(8),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync SA Wins Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 93999'
        );
        insert workOrderRecord;

        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'INV-Sync SA Wins Appointment',
            Opportunity__c = opportunityRecord.Id,
            Invoice_Number__c = 'Inv 93111'
        );
        insert appointmentRecord;

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'INV-Sync should create one invoice from the SA number.');
        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c, Opportunity__c, Total_Amount__c, Balance_Due__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
        ];
        System.assertEquals('Inv 93111', createdInvoice.Invoice_Number__c);
        System.assertEquals(null, createdInvoice.Total_Amount__c, 'INV-Sync must not invent an external invoice amount.');

        Invoice_Line__c createdLine = [
            SELECT Service_Appointment__c, Work_Order__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :createdInvoice.Id
        ];
        System.assertNotEquals(null, createdLine.Service_Appointment__c, 'INV-Sync must create Invoice_Line__c.');
        System.assertEquals(appointmentRecord.Id, createdLine.Service_Appointment__c);
        System.assertEquals(workOrderRecord.Id, createdLine.Work_Order__c);

        ServiceAppointment updatedAppointment = [
            SELECT Invoice_Number__c
            FROM ServiceAppointment
            WHERE Id = :appointmentRecord.Id
        ];
        System.assertEquals('Inv 93111', updatedAppointment.Invoice_Number__c, 'Existing SA invoice numbers must not be overwritten.');

        Opportunity updatedOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        System.assertEquals('Ready for Billing', updatedOpportunity.Billing_Status__c);
    }

    @isTest
    static void testInvSyncStampsBlankServiceAppointmentFromWorkOrder() {
        Account accountRecord = new Account(Name = 'INV-Sync WO Stamp Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync WO Stamp Work Type', 2);

        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync WO Stamp Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 180,
            CloseDate = Date.today().addDays(9),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync WO Stamp Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Inv 93222'
        );
        insert workOrderRecord;

        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-4),
            SchedEndTime = System.now().addHours(-3),
            ActualEndTime = System.now().addHours(-2),
            Subject = 'INV-Sync WO Stamp Appointment',
            Opportunity__c = opportunityRecord.Id
        );
        insert appointmentRecord;

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated);
        System.assertEquals(1, result.serviceAppointmentsUpdated);

        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
        ];
        System.assertEquals('Inv 93222', createdInvoice.Invoice_Number__c);

        ServiceAppointment updatedAppointment = [
            SELECT Invoice_Number__c
            FROM ServiceAppointment
            WHERE Id = :appointmentRecord.Id
        ];
        System.assertEquals('Inv 93222', updatedAppointment.Invoice_Number__c);
    }

    @isTest
    static void testInvSyncSkipsExistingInvoiceAndOutOfScopeRows() {
        Account accountRecord = new Account(Name = 'INV-Sync Skip Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Skip Work Type', 2);

        Opportunity existingOpportunity = new Opportunity(
            Name = 'INV-Sync Existing Invoice Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 90,
            CloseDate = Date.today().addDays(4),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity priorYearOpportunity = new Opportunity(
            Name = 'INV-Sync Prior Year Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 110,
            CloseDate = Date.today().addDays(5),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ existingOpportunity, priorYearOpportunity };

        WorkOrder existingWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Existing Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder priorYearWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Prior Year Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert new List<WorkOrder>{ existingWorkOrder, priorYearWorkOrder };

        ServiceAppointment existingAppointment = new ServiceAppointment(
            ParentRecordId = existingWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-5),
            SchedEndTime = System.now().addHours(-4),
            ActualEndTime = System.now().addHours(-3),
            Subject = 'INV-Sync Existing Appointment',
            Opportunity__c = existingOpportunity.Id,
            Invoice_Number__c = 'Inv 93101'
        );
        ServiceAppointment priorYearAppointment = new ServiceAppointment(
            ParentRecordId = priorYearWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(10, 0, 0, 0)),
            SchedEndTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(11, 0, 0, 0)),
            ActualEndTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(12, 0, 0, 0)),
            Subject = 'INV-Sync Prior Year Appointment',
            Opportunity__c = priorYearOpportunity.Id,
            Invoice_Number__c = 'Inv 93102'
        );
        insert new List<ServiceAppointment>{ existingAppointment, priorYearAppointment };

        insert new Invoice__c(
            Invoice_Number__c = 'Inv 93101',
            Opportunity__c = existingOpportunity.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 90,
            Tax_Amount__c = 0,
            Total_Amount__c = 90,
            Amount_Paid__c = 0,
            Balance_Due__c = 90
        );

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, '005000000000000AAA');
        BillingControl_Invoicing.InvSyncResultWrapper existingResult =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Database.executeBatch(
            new BillingControl_InvSyncBatch(dateFilter, null),
            40
        );
        Test.stopTest();

        System.assertEquals(0, result.invoicesCreated, 'Owner filter should exclude the current user\'s opportunities.');
        System.assertEquals(0, existingResult.invoicesCreated, 'Existing Invoice__c numbers must be skipped.');
        System.assert(existingResult.skippedCount > 0, 'Existing invoice numbers should be counted as skipped.');

        Integer priorYearInvoiceCount = [
            SELECT COUNT()
            FROM Invoice__c
            WHERE Invoice_Number__c = 'Inv 93102'
        ];
        System.assertEquals(0, priorYearInvoiceCount, 'Last-year appointments must stay outside This Year INV-Sync.');
    }

    @isTest
    static void testInvSyncSkipsExistingInvoiceLineOnAppointment() {
        Account accountRecord = new Account(Name = 'INV-Sync Existing Line Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Existing Line Work Type', 2);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync Existing Line Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 140,
            CloseDate = Date.today().addDays(4),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync Existing Line WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'INV-Sync Existing Line SA',
            Opportunity__c = opportunityRecord.Id,
            Invoice_Number__c = 'Inv 93103'
        );
        insert appointmentRecord;
        Invoice__c existingInvoice = new Invoice__c(
            Invoice_Number__c = 'INV-LINE-OTHER',
            Opportunity__c = opportunityRecord.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 40,
            Tax_Amount__c = 0,
            Total_Amount__c = 40,
            Amount_Paid__c = 0,
            Balance_Due__c = 40
        );
        insert existingInvoice;
        insert new Invoice_Line__c(
            Invoice__c = existingInvoice.Id,
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id,
            Service_Appointment__c = appointmentRecord.Id,
            Description__c = 'Existing line',
            Quantity__c = 1,
            Unit_Price__c = 40,
            Line_Total__c = 40
        );

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(0, result.invoicesCreated);
        System.assert(result.skippedCount > 0, 'Existing Invoice_Line__c rows must increment skippedCount.');
        Integer createdCount = [
            SELECT COUNT()
            FROM Invoice__c
            WHERE Invoice_Number__c = 'INV-LINE-EXIST'
        ];
        System.assertEquals(0, createdCount);
    }

    @isTest
    static void testInvSyncSkipsDuplicateInvoiceNumberInSameScope() {
        Account accountRecord = new Account(Name = 'INV-Sync Batch Dup Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Batch Dup Work Type', 2);
        Opportunity firstOpportunity = new Opportunity(
            Name = 'INV-Sync Batch Dup Opportunity One',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 80,
            CloseDate = Date.today().addDays(3),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity secondOpportunity = new Opportunity(
            Name = 'INV-Sync Batch Dup Opportunity Two',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 90,
            CloseDate = Date.today().addDays(4),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ firstOpportunity, secondOpportunity };
        WorkOrder firstWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Batch Dup WO One',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder secondWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Batch Dup WO Two',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert new List<WorkOrder>{ firstWorkOrder, secondWorkOrder };
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = firstWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-4),
                SchedEndTime = System.now().addHours(-3),
                ActualEndTime = System.now().addHours(-3),
                Subject = 'INV-Sync Batch Dup SA One',
                Opportunity__c = firstOpportunity.Id,
                Invoice_Number__c = 'Inv 93200'
            ),
            new ServiceAppointment(
                ParentRecordId = secondWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-2),
                SchedEndTime = System.now().addHours(-1),
                ActualEndTime = System.now().addHours(-1),
                Subject = 'INV-Sync Batch Dup SA Two',
                Opportunity__c = secondOpportunity.Id,
                Invoice_Number__c = 'Inv 93200'
            )
        };

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'Only the first group with a shared invoice number should persist.');
        System.assert(result.skippedCount > 0, 'The second group must be counted as skipped.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Invoice__c WHERE Invoice_Number__c = 'Inv 93200']
        );
    }

    @isTest
    static void testInvSyncSkipsFullyInvoicedAndSecondInvoiceGroup() {
        Account accountRecord = new Account(Name = 'INV-Sync Remaining Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Remaining Work Type', 2);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync Remaining Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 100,
            CloseDate = Date.today().addDays(5),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync Remaining WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = workOrderRecord.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-5),
                SchedEndTime = System.now().addHours(-4),
                ActualEndTime = System.now().addHours(-4),
                Subject = 'INV-Sync Remaining SA One',
                Opportunity__c = opportunityRecord.Id,
                Invoice_Number__c = 'Inv 93301'
            ),
            new ServiceAppointment(
                ParentRecordId = workOrderRecord.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-3),
                SchedEndTime = System.now().addHours(-2),
                ActualEndTime = System.now().addHours(-2),
                Subject = 'INV-Sync Remaining SA Two',
                Opportunity__c = opportunityRecord.Id,
                Invoice_Number__c = 'Inv 93302'
            )
        };

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(2, result.invoicesCreated, 'Each parsed invoice number becomes its own pending-external invoice.');
        System.assertEquals(2, [SELECT COUNT() FROM Invoice__c WHERE Opportunity__c = :opportunityRecord.Id]);
    }

    @isTest
    static void testInvSyncPreservesPaidAndPartiallyPaidStatuses() {
        Account accountRecord = new Account(Name = 'INV-Sync Status Preserve Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync Status Preserve Work Type', 2);
        Opportunity paidOpportunity = new Opportunity(
            Name = 'INV-Sync Paid Preserve Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 60,
            CloseDate = Date.today().addDays(2),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity partialOpportunity = new Opportunity(
            Name = 'INV-Sync Partial Preserve Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 70,
            CloseDate = Date.today().addDays(3),
            Billing_Status__c = 'Partially Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ paidOpportunity, partialOpportunity };
        WorkOrder paidWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Paid Preserve WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder partialWorkOrder = new WorkOrder(
            Subject = 'INV-Sync Partial Preserve WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert new List<WorkOrder>{ paidWorkOrder, partialWorkOrder };
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = paidWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-4),
                SchedEndTime = System.now().addHours(-3),
                ActualEndTime = System.now().addHours(-3),
                Subject = 'INV-Sync Paid Preserve SA',
                Opportunity__c = paidOpportunity.Id,
                Invoice_Number__c = 'Inv 93401'
            ),
            new ServiceAppointment(
                ParentRecordId = partialWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-2),
                SchedEndTime = System.now().addHours(-1),
                ActualEndTime = System.now().addHours(-1),
                Subject = 'INV-Sync Partial Preserve SA',
                Opportunity__c = partialOpportunity.Id,
                Invoice_Number__c = 'Inv 93402'
            )
        };

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Map<Id, Opportunity> statusBeforeSync = new Map<Id, Opportunity>([
            SELECT Id, Billing_Status__c
            FROM Opportunity
            WHERE Id IN :new Set<Id>{ paidOpportunity.Id, partialOpportunity.Id }
        ]);

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(2, result.invoicesCreated);
        Map<Id, Opportunity> updatedById = new Map<Id, Opportunity>([
            SELECT Id, Billing_Status__c
            FROM Opportunity
            WHERE Id IN :new Set<Id>{ paidOpportunity.Id, partialOpportunity.Id }
        ]);
        if (statusBeforeSync.get(paidOpportunity.Id).Billing_Status__c == 'Paid') {
            System.assertEquals('Paid', updatedById.get(paidOpportunity.Id).Billing_Status__c);
        }
        if (statusBeforeSync.get(partialOpportunity.Id).Billing_Status__c == 'Partially Paid') {
            System.assertEquals('Partially Paid', updatedById.get(partialOpportunity.Id).Billing_Status__c);
        }
    }

    @isTest
    static void testInvSyncAttributesWoliParentedAppointment() {
        Account accountRecord = new Account(Name = 'INV-Sync WOLI Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('INV-Sync WOLI Work Type', 2);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'INV-Sync WOLI Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 55,
            CloseDate = Date.today().addDays(6),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'INV-Sync WOLI WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = workOrderRecord.Id);
        insert lineItem;
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = lineItem.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-3),
            SchedEndTime = System.now().addHours(-2),
            ActualEndTime = System.now().addHours(-1),
            Subject = 'INV-Sync WOLI SA',
            Opportunity__c = opportunityRecord.Id,
            Invoice_Number__c = 'Inv 93501'
        );
        insert appointmentRecord;

        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter =
            new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_InvSync.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated);
        Invoice_Line__c createdLine = [
            SELECT Work_Order__c, Service_Appointment__c
            FROM Invoice_Line__c
            WHERE Service_Appointment__c = :appointmentRecord.Id
        ];
        System.assertEquals(workOrderRecord.Id, createdLine.Work_Order__c);
        System.assertEquals(appointmentRecord.Id, createdLine.Service_Appointment__c);
    }

}
