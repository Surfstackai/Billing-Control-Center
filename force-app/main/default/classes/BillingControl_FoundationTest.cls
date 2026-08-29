@isTest
private class BillingControl_FoundationTest {
    @isTest
    static void parserSplitsCombinedDepositAndBalanceTokens() {
        List<BillingControl_InvoiceNumberParser.ParsedToken> tokens =
            BillingControl_InvoiceNumberParser.parse('Inv 93157-DP 93199');

        System.assertEquals(2, tokens.size());
        System.assertEquals('Balance', tokens[0].type);
        System.assertEquals('93157', tokens[0].invoiceNumber);
        System.assertEquals('Deposit', tokens[1].type);
        System.assertEquals('93199', tokens[1].invoiceNumber);
    }

    @isTest
    static void parserAcceptsMixedCaseDpPrefix() {
        List<BillingControl_InvoiceNumberParser.ParsedToken> tokens =
            BillingControl_InvoiceNumberParser.parse('Inv 90791-Dp 93198');

        System.assertEquals(2, tokens.size());
        System.assertEquals('Balance', tokens[0].type);
        System.assertEquals('90791', tokens[0].invoiceNumber);
        System.assertEquals('Deposit', tokens[1].type);
        System.assertEquals('93198', tokens[1].invoiceNumber);
    }

    @isTest
    static void parserReadsStandaloneDepositAndInheritedBalanceNumbers() {
        List<BillingControl_InvoiceNumberParser.ParsedToken> depositTokens =
            BillingControl_InvoiceNumberParser.parse('DP 91802');
        System.assertEquals(1, depositTokens.size());
        System.assertEquals('Deposit', depositTokens[0].type);
        System.assertEquals('91802', depositTokens[0].invoiceNumber);

        List<BillingControl_InvoiceNumberParser.ParsedToken> shortDeposit =
            BillingControl_InvoiceNumberParser.parse('DP 3161');
        System.assertEquals(1, shortDeposit.size());
        System.assertEquals('3161', shortDeposit[0].invoiceNumber);

        List<BillingControl_InvoiceNumberParser.ParsedToken> inherited =
            BillingControl_InvoiceNumberParser.parse('Inv - 90521(VFD)-Booster -90665 -Inv 93194');
        System.assertEquals(3, inherited.size(), 'Bare numbers after Inv inherit Balance.');
        System.assertEquals('90521', inherited[0].invoiceNumber);
        System.assertEquals('Balance', inherited[0].type);
        System.assertEquals('90665', inherited[1].invoiceNumber);
        System.assertEquals('Balance', inherited[1].type);
        System.assertEquals('93194', inherited[2].invoiceNumber);
        System.assertEquals('Balance', inherited[2].type);
    }

    @isTest
    static void parserDenyListReturnsNoTokens() {
        List<String> denied = new List<String>{
            'Inspection to Quote',
            'To be Quote',
            'Pending as Per DW',
            'To be Rescheduled',
            'Incomplete',
            'No bill as per DW',
            'completed',
            'Deposit Required',
            'Waiting for deposit',
            'Deposit received',
            'Due in Full',
            'No Deposit required'
        };
        for (String deniedValue : denied) {
            System.assertEquals(
                0,
                BillingControl_InvoiceNumberParser.parse(deniedValue).size(),
                deniedValue + ' must not become an invoice token.'
            );
        }
        System.assertEquals(0, BillingControl_InvoiceNumberParser.parse('').size());
        System.assertEquals(0, BillingControl_InvoiceNumberParser.parse('not an invoice').size());
    }

    @isTest
    static void billedAppointmentIdsIgnoreVoidInvoicesAndTextFields() {
        FixtureData fixture = createFixture();

        Invoice__c voidInvoice = buildInvoice(fixture, 'INV-VOID-1', 50, 'Void');
        insert voidInvoice;
        insert new Invoice_Line__c(
            Invoice__c = voidInvoice.Id,
            Opportunity__c = fixture.opportunityId,
            Work_Order__c = fixture.workOrderId,
            Service_Appointment__c = fixture.unbilledAppointmentId,
            Description__c = 'Voided line',
            Quantity__c = 1,
            Unit_Price__c = 50,
            Line_Total__c = 50
        );

        Test.startTest();
        Set<Id> billedIds = BillingControl_BillingTruth.billedAppointmentIds(
            new Set<Id>{ fixture.billedAppointmentId, fixture.unbilledAppointmentId }
        );
        Test.stopTest();

        System.assertEquals(true, billedIds.contains(fixture.billedAppointmentId));
        System.assertEquals(false, billedIds.contains(fixture.unbilledAppointmentId));
        System.assertEquals(0, BillingControl_BillingTruth.billedAppointmentIds(new Set<Id>()).size());
    }

    @isTest
    static void invoiceMathRecalculatesFromPaymentsAndLeavesVoidAlone() {
        FixtureData fixture = createFixture();

        Invoice__c openInvoice = buildInvoice(fixture, 'INV-MATH-OPEN', 200, 'Sent');
        Invoice__c voidInvoice = buildInvoice(fixture, 'INV-MATH-VOID', 80, 'Void');
        Invoice__c pendingInvoice = buildInvoice(fixture, 'INV-MATH-PENDING', null, 'Sent');
        Invoice__c paidInvoice = buildInvoice(fixture, 'INV-MATH-PAID', 100, 'Sent');
        Invoice__c unpaidInvoice = buildInvoice(fixture, 'INV-MATH-UNPAID', 60, 'Draft');
        insert new List<Invoice__c>{ openInvoice, voidInvoice, pendingInvoice, paidInvoice, unpaidInvoice };

        insert new List<Invoice_Payment__c>{
            new Invoice_Payment__c(
                Opportunity__c = fixture.opportunityId,
                Invoice__c = openInvoice.Id,
                Amount_Received__c = 50,
                Payment_Date__c = Date.today()
            ),
            new Invoice_Payment__c(
                Opportunity__c = fixture.opportunityId,
                Invoice__c = openInvoice.Id,
                Amount_Received__c = 25,
                Payment_Date__c = Date.today()
            ),
            new Invoice_Payment__c(
                Opportunity__c = fixture.opportunityId,
                Invoice__c = voidInvoice.Id,
                Amount_Received__c = 10,
                Payment_Date__c = Date.today()
            ),
            new Invoice_Payment__c(
                Opportunity__c = fixture.opportunityId,
                Invoice__c = paidInvoice.Id,
                Amount_Received__c = 100,
                Payment_Date__c = Date.today()
            )
        };

        Set<Id> invoiceIds = new Set<Id>{
            openInvoice.Id, voidInvoice.Id, pendingInvoice.Id, paidInvoice.Id, unpaidInvoice.Id
        };

        Test.startTest();
        BillingControl_InvoiceMath.recalculate(invoiceIds);
        Test.stopTest();

        Map<Id, Invoice__c> updated = new Map<Id, Invoice__c>([
            SELECT Amount_Paid__c, Balance_Due__c, Status__c, Total_Amount__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]);

        System.assertEquals(75, updated.get(openInvoice.Id).Amount_Paid__c);
        System.assertEquals(125, updated.get(openInvoice.Id).Balance_Due__c);
        System.assertEquals('Partially Paid', updated.get(openInvoice.Id).Status__c);
        System.assertEquals('Void', updated.get(voidInvoice.Id).Status__c);
        System.assertEquals(10, updated.get(voidInvoice.Id).Amount_Paid__c);
        System.assertEquals('Draft', updated.get(pendingInvoice.Id).Status__c);
        System.assertEquals(0, updated.get(pendingInvoice.Id).Amount_Paid__c);
        System.assertEquals(null, updated.get(pendingInvoice.Id).Balance_Due__c);
        System.assertEquals(100, updated.get(paidInvoice.Id).Amount_Paid__c);
        System.assertEquals(0, updated.get(paidInvoice.Id).Balance_Due__c);
        System.assertEquals('Paid', updated.get(paidInvoice.Id).Status__c);
        System.assertEquals(0, updated.get(unpaidInvoice.Id).Amount_Paid__c);
        System.assertEquals(60, updated.get(unpaidInvoice.Id).Balance_Due__c);
        System.assertEquals('Sent', updated.get(unpaidInvoice.Id).Status__c);
    }

    @isTest
    static void opportunityFinancialsAggregateNonVoidInvoices() {
        FixtureData fixture = createFixture();

        Invoice__c secondInvoice = buildInvoice(fixture, 'INV-FIN-2', 150, 'Sent');
        secondInvoice.Amount_Paid__c = 150;
        secondInvoice.Balance_Due__c = 0;
        Invoice__c voidInvoice = buildInvoice(fixture, 'INV-FIN-VOID', 999, 'Void');
        Invoice__c pendingInvoice = buildInvoice(fixture, 'INV-FIN-PENDING', null, 'Draft');
        insert new List<Invoice__c>{ secondInvoice, voidInvoice, pendingInvoice };

        Opportunity emptyOpportunity = new Opportunity(
            Name = 'Foundation Empty Opp',
            AccountId = fixture.accountId,
            StageName = 'Prospecting',
            Amount = 10,
            CloseDate = Date.today().addDays(5),
            Do_not_create_Work_Order__c = true
        );
        insert emptyOpportunity;

        Test.startTest();
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> snapshots =
            BillingControl_OpportunityFinancials.load(
                new Set<Id>{ fixture.opportunityId, emptyOpportunity.Id }
            );
        Test.stopTest();

        BillingControl_OpportunityFinancials.Snapshot jobSnapshot = snapshots.get(fixture.opportunityId);
        System.assertEquals(450, jobSnapshot.invoicedTotal, 'Sent 300 + paid 150; void and null total excluded.');
        System.assertEquals(150, jobSnapshot.paidTotal);
        System.assertEquals(300, jobSnapshot.outstanding);
        System.assertEquals(false, jobSnapshot.paidInFull);
        System.assertEquals(2, jobSnapshot.invoiceCount);

        BillingControl_OpportunityFinancials.Snapshot emptySnapshot = snapshots.get(emptyOpportunity.Id);
        System.assertEquals(0, emptySnapshot.invoicedTotal);
        System.assertEquals(false, emptySnapshot.paidInFull);
    }

    @isTest
    static void backfillSetsBalanceAndDerivedOnBlankInvoiceFields() {
        FixtureData fixture = createFixture();
        Invoice__c invoiceRecord = [
            SELECT Invoice_Type__c, Amount_Source__c
            FROM Invoice__c
            WHERE Id = :fixture.invoiceId
        ];
        invoiceRecord.Invoice_Type__c = null;
        invoiceRecord.Amount_Source__c = null;
        update invoiceRecord;

        Test.startTest();
        Integer updatedCount = BillingControl_InvoiceTypeBackfill.backfillExistingInvoices();
        Test.stopTest();

        Invoice__c backfilled = [
            SELECT Invoice_Type__c, Amount_Source__c
            FROM Invoice__c
            WHERE Id = :fixture.invoiceId
        ];
        System.assert(updatedCount >= 1);
        System.assertEquals('Balance', backfilled.Invoice_Type__c);
        System.assertEquals('Derived', backfilled.Amount_Source__c);
    }

    private class FixtureData {
        Id accountId;
        Id opportunityId;
        Id workOrderId;
        Id billedAppointmentId;
        Id unbilledAppointmentId;
        Id invoiceId;
    }

    private static FixtureData createFixture() {
        Account accountRecord = new Account(Name = 'Foundation Test Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Foundation Work Type', 2);

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Foundation Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            Amount = 500,
            CloseDate = Date.today().addDays(10),
            Do_not_create_Work_Order__c = true,
            Deposit_Required__c = true,
            Deposit_Percent__c = 50,
            Deposit_Timing__c = 'Before Completion'
        );
        insert opportunityRecord;

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Foundation Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;

        Datetime startTime = Datetime.now().addDays(-2);
        Datetime endTime = startTime.addHours(2);
        ServiceAppointment billedAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = endTime,
            ActualEndTime = endTime,
            Subject = 'Billed appointment'
        );
        ServiceAppointment unbilledAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime.addHours(3),
            SchedEndTime = endTime.addHours(3),
            ActualEndTime = endTime.addHours(3),
            Subject = 'Unbilled appointment'
        );
        insert new List<ServiceAppointment>{ billedAppointment, unbilledAppointment };

        Invoice__c invoiceRecord = buildInvoiceHeader(
            opportunityRecord.Id,
            accountRecord.Id,
            'INV-FOUND-1',
            300,
            'Sent'
        );
        insert invoiceRecord;
        insert new Invoice_Line__c(
            Invoice__c = invoiceRecord.Id,
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id,
            Service_Appointment__c = billedAppointment.Id,
            Description__c = 'Billed line',
            Quantity__c = 1,
            Unit_Price__c = 300,
            Line_Total__c = 300
        );

        FixtureData fixture = new FixtureData();
        fixture.accountId = accountRecord.Id;
        fixture.opportunityId = opportunityRecord.Id;
        fixture.workOrderId = workOrderRecord.Id;
        fixture.billedAppointmentId = billedAppointment.Id;
        fixture.unbilledAppointmentId = unbilledAppointment.Id;
        fixture.invoiceId = invoiceRecord.Id;
        return fixture;
    }

    private static Invoice__c buildInvoice(FixtureData fixture, String invoiceNumber, Decimal totalAmount, String statusValue) {
        return buildInvoiceHeader(fixture.opportunityId, fixture.accountId, invoiceNumber, totalAmount, statusValue);
    }

    private static Invoice__c buildInvoiceHeader(
        Id opportunityId,
        Id accountId,
        String invoiceNumber,
        Decimal totalAmount,
        String statusValue
    ) {
        return new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Status__c = statusValue,
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = totalAmount,
            Tax_Amount__c = 0,
            Total_Amount__c = totalAmount,
            Amount_Paid__c = 0,
            Balance_Due__c = totalAmount,
            Invoice_Type__c = 'Balance',
            Amount_Source__c = 'Derived'
        );
    }
}
