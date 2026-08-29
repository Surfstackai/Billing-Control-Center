@isTest
private class BillingControl_InvoiceServiceTest {
    @isTest
    static void createDepositInvoiceWithoutServiceAppointments() {
        FixtureData fixture = createFixture(10000, true);

        BillingControl_InvoiceService.InvoiceRequest request = newRequest(fixture.opportunityId, 'Deposit', 5000);
        request.acceptFullRemaining = false;

        Test.startTest();
        BillingControl_InvoiceService.InvoiceResult result = BillingControl_InvoiceService.createInvoice(request);
        Test.stopTest();

        Invoice__c invoiceRecord = [
            SELECT Invoice_Type__c, Total_Amount__c, Amount_Source__c, Status__c
            FROM Invoice__c
            WHERE Id = :result.invoiceId
        ];
        System.assertEquals('Deposit', invoiceRecord.Invoice_Type__c);
        System.assertEquals(5000, invoiceRecord.Total_Amount__c);
        System.assertEquals('Entered', invoiceRecord.Amount_Source__c);
        Invoice_Line__c lineRecord = [
            SELECT Service_Appointment__c, Description__c, Line_Total__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :invoiceRecord.Id
            LIMIT 1
        ];
        System.assertEquals(null, lineRecord.Service_Appointment__c);
        System.assert(lineRecord.Description__c.contains('Deposit'));
        System.assertEquals(5000, lineRecord.Line_Total__c);
        System.assertEquals(1, [SELECT COUNT() FROM Commission__c WHERE Opportunity__c = :fixture.opportunityId]);
        Opportunity billedOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :fixture.opportunityId
        ];
        System.assertEquals(
            BillingControl_Invoicing.getOutstandingReceivableStatusForUpdate(),
            billedOpportunity.Billing_Status__c,
            'First invoice should move the Opportunity to outstanding receivable unless it was already paid.'
        );
    }

    @isTest
    static void doesNotOverwritePaidBillingStatus() {
        FixtureData fixture = createFixture(4000, false);
        update new Opportunity(Id = fixture.opportunityId, Billing_Status__c = 'Paid');
        Opportunity paidBeforeInvoice = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :fixture.opportunityId
        ];
        System.assertEquals('Paid', paidBeforeInvoice.Billing_Status__c);

        BillingControl_InvoiceService.InvoiceRequest request = newRequest(fixture.opportunityId, 'Balance', 500);
        request.serviceAppointmentIds = new List<Id>{ fixture.billedAppointmentId };
        request.acceptFullRemaining = false;

        Test.startTest();
        BillingControl_InvoiceService.createInvoice(request);
        Test.stopTest();

        Opportunity paidAfterInvoice = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :fixture.opportunityId
        ];
        System.assertEquals(
            'Paid',
            paidAfterInvoice.Billing_Status__c,
            'Invoice creation must not overwrite an existing Paid billing status.'
        );
    }

    @isTest
    static void fullRemainingRequiresExplicitConsent() {
        FixtureData fixture = createFixture(2500, false);
        BillingControl_InvoiceService.InvoiceRequest request = newRequest(fixture.opportunityId, 'Balance', 2500);
        request.acceptFullRemaining = false;

        Test.startTest();
        try {
            BillingControl_InvoiceService.createInvoice(request);
            System.assert(false, 'Full remaining must require acceptFullRemaining.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('full remaining'));
        }
        Test.stopTest();
    }

    @isTest
    static void varianceRequiresExplicitConsent() {
        FixtureData fixture = createFixture(1000, false);
        BillingControl_InvoiceService.InvoiceRequest request = newRequest(fixture.opportunityId, 'Balance', 1500);
        request.acceptFullRemaining = false;
        request.acceptVariance = false;

        Test.startTest();
        try {
            BillingControl_InvoiceService.createInvoice(request);
            System.assert(false, 'Amount over Opportunity.Amount must require acceptVariance.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('exceeds'));
        }
        Test.stopTest();
    }

    @isTest
    static void multiOpportunityWorkOrderDoesNotStampAppointmentUnlessOptedIn() {
        FixtureData fixture = createMultiOpportunityFixture();
        BillingControl_InvoiceService.InvoiceRequest request = newRequest(fixture.opportunityId, 'Balance', 400);
        request.serviceAppointmentIds = new List<Id>{ fixture.billedAppointmentId };
        request.acceptFullRemaining = false;
        request.updateOperationalAttribution = false;

        Test.startTest();
        BillingControl_InvoiceService.InvoiceResult result = BillingControl_InvoiceService.createInvoice(request);
        Test.stopTest();

        Invoice__c invoiceRecord = [SELECT Opportunity__c FROM Invoice__c WHERE Id = :result.invoiceId];
        System.assertEquals(fixture.opportunityId, invoiceRecord.Opportunity__c);
        ServiceAppointment appointmentRecord = [
            SELECT Opportunity__c
            FROM ServiceAppointment
            WHERE Id = :fixture.billedAppointmentId
        ];
        System.assertEquals(null, appointmentRecord.Opportunity__c);

        request.invoiceNumber = 'P6-OPT-IN-001';
        request.serviceAppointmentIds = new List<Id>{ fixture.unbilledAppointmentId };
        request.updateOperationalAttribution = true;
        BillingControl_InvoiceService.createInvoice(request);
        ServiceAppointment optedInAppointment = [
            SELECT Opportunity__c
            FROM ServiceAppointment
            WHERE Id = :fixture.unbilledAppointmentId
        ];
        System.assertEquals(fixture.opportunityId, optedInAppointment.Opportunity__c);
    }

    @isTest
    static void rejectsAlreadyBilledAppointmentAndForeignOpportunity() {
        FixtureData fixture = createFixture(800, false);
        BillingControl_InvoiceService.InvoiceRequest firstRequest = newRequest(fixture.opportunityId, 'Balance', 300);
        firstRequest.serviceAppointmentIds = new List<Id>{ fixture.billedAppointmentId };
        firstRequest.acceptFullRemaining = false;
        BillingControl_InvoiceService.createInvoice(firstRequest);

        BillingControl_InvoiceService.InvoiceRequest duplicateRequest = newRequest(fixture.opportunityId, 'Balance', 200);
        duplicateRequest.invoiceNumber = 'ALREADY-BILLED-001';
        duplicateRequest.serviceAppointmentIds = new List<Id>{ fixture.billedAppointmentId };
        try {
            BillingControl_InvoiceService.createInvoice(duplicateRequest);
            System.assert(false, 'Already billed appointments must be rejected.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('already billed'));
        }

        Opportunity otherOpportunity = new Opportunity(
            Name = 'Foreign Attribution Opportunity',
            AccountId = fixture.accountId,
            StageName = 'Prospecting',
            Amount = 500,
            CloseDate = Date.today().addDays(8),
            Do_not_create_Work_Order__c = true
        );
        insert otherOpportunity;
        update new ServiceAppointment(Id = fixture.unbilledAppointmentId, Opportunity__c = otherOpportunity.Id);

        BillingControl_InvoiceService.InvoiceRequest foreignRequest = newRequest(fixture.opportunityId, 'Balance', 200);
        foreignRequest.invoiceNumber = 'FOREIGN-SA-001';
        foreignRequest.serviceAppointmentIds = new List<Id>{ fixture.unbilledAppointmentId };
        try {
            BillingControl_InvoiceService.createInvoice(foreignRequest);
            System.assert(false, 'SA attributed to another Opportunity must be rejected.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('different Opportunity'));
        }
    }

    @isTest
    static void defaultsAndCandidatesSurfaceQuoteAndRemaining() {
        FixtureData fixture = createFixture(2000, true);
        Test.startTest();
        BillingControl_InvoiceService.InvoiceDefaults depositDefaults =
            BillingControl_InvoiceService.getInvoiceDefaults(fixture.opportunityId, 'Deposit');
        BillingControl_InvoiceService.InvoiceDefaults balanceDefaults =
            BillingControl_InvoiceService.getInvoiceDefaults(fixture.opportunityId, 'Balance');
        List<BillingControl_InvoiceService.OpportunityCandidate> workOrderCandidates =
            BillingControl_InvoiceService.listCandidateOpportunities('WorkOrder', fixture.workOrderId);
        BillingControl_InvoiceService.VisitInvoiceContext visitContext =
            BillingControl_InvoiceService.getVisitInvoiceContext(fixture.unbilledAppointmentId);
        Test.stopTest();

        System.assertEquals(1000, depositDefaults.suggestedAmount);
        System.assertEquals(2000, balanceDefaults.suggestedAmount);
        System.assertEquals(1, workOrderCandidates.size());
        System.assertEquals(fixture.opportunityId, workOrderCandidates[0].opportunityId);
        System.assertEquals(fixture.unbilledAppointmentId, visitContext.serviceAppointmentId);
        System.assertEquals(false, visitContext.unassigned, 'Fixture unbilled appointment has operational Opportunity.');
        System.assertEquals(fixture.workOrderId, visitContext.workOrderId);
    }

    private class FixtureData {
        Id accountId;
        Id opportunityId;
        Id workOrderId;
        Id billedAppointmentId;
        Id unbilledAppointmentId;
    }

    private static BillingControl_InvoiceService.InvoiceRequest newRequest(
        Id opportunityId,
        String invoiceType,
        Decimal invoiceAmount
    ) {
        BillingControl_InvoiceService.InvoiceRequest request = new BillingControl_InvoiceService.InvoiceRequest();
        request.opportunityId = opportunityId;
        request.invoiceType = invoiceType;
        request.invoiceAmount = invoiceAmount;
        request.acceptFullRemaining = false;
        request.acceptVariance = false;
        request.amountPendingExternal = false;
        request.updateOperationalAttribution = false;
        return request;
    }

    private static FixtureData createFixture(Decimal amount, Boolean depositRequired) {
        Account accountRecord = new Account(Name = 'Invoice Service Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Invoice Service Work Type', 2);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Invoice Service Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            Amount = amount,
            CloseDate = Date.today().addDays(10),
            Do_not_create_Work_Order__c = true,
            Deposit_Required__c = depositRequired,
            Deposit_Percent__c = 50,
            Deposit_Timing__c = 'Before Completion'
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Invoice Service Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id
        );
        Datetime startTime = Datetime.now().addDays(-1);
        ServiceAppointment firstAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Invoice Service SA One',
            Opportunity__c = opportunityRecord.Id
        );
        ServiceAppointment secondAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime.addHours(2),
            SchedEndTime = startTime.addHours(3),
            ActualEndTime = startTime.addHours(3),
            Subject = 'Invoice Service SA Two',
            Opportunity__c = opportunityRecord.Id
        );
        insert new List<ServiceAppointment>{ firstAppointment, secondAppointment };

        FixtureData fixture = new FixtureData();
        fixture.accountId = accountRecord.Id;
        fixture.opportunityId = opportunityRecord.Id;
        fixture.workOrderId = workOrderRecord.Id;
        fixture.billedAppointmentId = firstAppointment.Id;
        fixture.unbilledAppointmentId = secondAppointment.Id;
        return fixture;
    }

    private static FixtureData createMultiOpportunityFixture() {
        Account accountRecord = new Account(Name = 'Invoice Service Multi Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Invoice Service Multi Work Type', 2);
        Opportunity firstOpportunity = new Opportunity(
            Name = 'Invoice Service Multi Opp A',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            Amount = 900,
            CloseDate = Date.today().addDays(10),
            Do_not_create_Work_Order__c = true
        );
        Opportunity secondOpportunity = new Opportunity(
            Name = 'Invoice Service Multi Opp B',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            Amount = 800,
            CloseDate = Date.today().addDays(11),
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ firstOpportunity, secondOpportunity };
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Invoice Service Multi Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = firstOpportunity.Id, Work_Order__c = workOrderRecord.Id),
            new Opportunity_WorkOrder__c(Opportunity__c = secondOpportunity.Id, Work_Order__c = workOrderRecord.Id)
        };
        Datetime startTime = Datetime.now().addDays(-1);
        ServiceAppointment firstAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Multi Opp SA One'
        );
        ServiceAppointment secondAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime.addHours(2),
            SchedEndTime = startTime.addHours(3),
            ActualEndTime = startTime.addHours(3),
            Subject = 'Multi Opp SA Two'
        );
        insert new List<ServiceAppointment>{ firstAppointment, secondAppointment };

        FixtureData fixture = new FixtureData();
        fixture.accountId = accountRecord.Id;
        fixture.opportunityId = firstOpportunity.Id;
        fixture.workOrderId = workOrderRecord.Id;
        fixture.billedAppointmentId = firstAppointment.Id;
        fixture.unbilledAppointmentId = secondAppointment.Id;
        return fixture;
    }
}
