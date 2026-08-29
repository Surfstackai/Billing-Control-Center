@IsTest
private class BillingControl_ReceivablesWorklistTest {
    @IsTest
    static void openArIgnoresInvoiceDateWindow() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Last Year Invoice Opp', 2500);

        Invoice__c lastYearInvoice = buildInvoice(
            fixture,
            'INV-LAST-YEAR',
            2500,
            'Sent',
            'Balance',
            Date.today().addYears(-1)
        );
        lastYearInvoice.Due_Date__c = Date.today().addDays(30);
        insert lastYearInvoice;

        Test.startTest();
        BillingControl_ReceivablesWorklist.TabRuntime tabRuntime =
            BillingControl_ReceivablesWorklist.getTabRuntime(
                1L,
                'This Month',
                String.valueOf(Date.today().toStartOfMonth()),
                String.valueOf(Date.today().toStartOfMonth().addMonths(1).addDays(-1)),
                null
            );
        Test.stopTest();

        System.assertEquals(1, tabRuntime.metrics.outstandingArCount, 'Open AR is who owes us now, not invoices issued this month.');
        System.assertEquals(2500, tabRuntime.metrics.outstandingAr);
        System.assertEquals(
            1,
            section(tabRuntime, BillingControl_ReceivablesWorklist.SECTION_OUTSTANDING_AR).invoiceCount
        );
    }

    @IsTest
    static void needsAmountAndSetInvoiceAmount() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Needs Amount Opp', 1800);
        Invoice__c pendingInvoice = buildInvoice(fixture, 'INV-PENDING', null, 'Draft', 'Balance', Date.today());
        insert pendingInvoice;

        Test.startTest();
        BillingControl_ReceivablesWorklist.TabRuntime beforeRuntime =
            BillingControl_ReceivablesWorklist.getTabRuntime(1L, 'This Month', null, null, null);
        BillingControl_ReceivablesWorklist.setInvoiceAmount(pendingInvoice.Id, 1800);
        BillingControl_ReceivablesWorklist.TabRuntime afterRuntime =
            BillingControl_ReceivablesWorklist.getTabRuntime(2L, 'This Month', null, null, null);
        Test.stopTest();

        System.assertEquals(1, beforeRuntime.metrics.needsAmountCount);
        System.assertEquals(0, beforeRuntime.metrics.outstandingArCount);
        System.assertEquals(0, afterRuntime.metrics.needsAmountCount);
        System.assertEquals(1, afterRuntime.metrics.outstandingArCount);
        System.assertEquals(1800, afterRuntime.metrics.outstandingAr);
    }

    @IsTest
    static void depositPaidInFullDoesNotPayTheJob() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Deposit Plus Balance Opp', 5000);
        insert new Opportunity_WorkOrder__c(Opportunity__c = fixture.opportunityId, Work_Order__c = fixture.workOrderId);
        insert new Commission__c(
            Opportunity__c = fixture.opportunityId,
            Sales_Person__c = UserInfo.getUserId(),
            Status__c = 'Accrued',
            Commission_Rate__c = 10,
            Unique_Key__c = String.valueOf(fixture.opportunityId) + String.valueOf(UserInfo.getUserId())
        );

        Invoice__c depositInvoice = buildInvoice(fixture, 'INV-DEP', 1000, 'Sent', 'Deposit', Date.today().addDays(-40));
        Invoice__c balanceInvoice = buildInvoice(fixture, 'INV-BAL', 4000, 'Sent', 'Balance', Date.today().addDays(-10));
        depositInvoice.Due_Date__c = Date.today().addDays(-10);
        insert new List<Invoice__c>{ depositInvoice, balanceInvoice };

        Test.startTest();
        Boolean missingInvoiceId = false;
        try {
            BillingControl_Receivables.postReceipt(receipt(fixture.opportunityId, 1000, 'NEED-INVOICE'));
        } catch (AuraHandledException error) {
            missingInvoiceId = true;
        }
        System.assertEquals(true, missingInvoiceId, 'Two open invoices require an explicit invoice id.');

        BillingControl_Invoicing.PaymentReceiptResultWrapper depositResult =
            BillingControl_Receivables.postInvoiceReceipt(
                fixture.opportunityId,
                depositInvoice.Id,
                1000,
                Date.today(),
                paymentMethod(),
                'DEP-PAID'
            );
        Test.stopTest();

        Opportunity opportunityRecord = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :fixture.opportunityId
        ];
        Commission__c commissionRecord = [
            SELECT Status__c, Commission_Paid__c, Paid_Amount__c, Paid_Date__c, Payable_Date__c
            FROM Commission__c
            WHERE Opportunity__c = :fixture.opportunityId
            LIMIT 1
        ];
        Invoice__c updatedDeposit = [
            SELECT Status__c, Amount_Paid__c, Balance_Due__c
            FROM Invoice__c
            WHERE Id = :depositInvoice.Id
        ];

        System.assertEquals(0, depositResult.balanceDue);
        System.assertEquals('Partially Paid', depositResult.billingStatus);
        System.assertEquals('Partially Paid', opportunityRecord.Billing_Status__c);
        System.assertEquals('Paid', updatedDeposit.Status__c);
        System.assertEquals('Accrued', commissionRecord.Status__c);
        System.assertEquals(0, commissionRecord.Commission_Paid__c);
        System.assertEquals(null, commissionRecord.Paid_Amount__c);
        System.assertEquals(null, commissionRecord.Paid_Date__c);
        System.assertEquals(null, commissionRecord.Payable_Date__c);
    }

    @IsTest
    static void depositOnlyPaidStaysPartiallyPaidUntilQuoteIsCovered() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Deposit Only Opp', 5000);
        insert new Commission__c(
            Opportunity__c = fixture.opportunityId,
            Sales_Person__c = UserInfo.getUserId(),
            Status__c = 'Accrued',
            Commission_Rate__c = 10,
            Unique_Key__c = String.valueOf(fixture.opportunityId) + String.valueOf(UserInfo.getUserId())
        );
        Invoice__c depositInvoice = buildInvoice(fixture, 'INV-DEP-ONLY', 1000, 'Sent', 'Deposit', Date.today());
        insert depositInvoice;

        Test.startTest();
        BillingControl_Invoicing.PaymentReceiptResultWrapper depositResult =
            BillingControl_Receivables.postInvoiceReceipt(
                fixture.opportunityId,
                depositInvoice.Id,
                1000,
                Date.today(),
                paymentMethod(),
                'DEP-ONLY-PAID'
            );
        Test.stopTest();

        Opportunity opportunityRecord = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :fixture.opportunityId
        ];
        Commission__c commissionRecord = [
            SELECT Status__c, Payable_Date__c
            FROM Commission__c
            WHERE Opportunity__c = :fixture.opportunityId
            LIMIT 1
        ];
        System.assertEquals('Partially Paid', depositResult.billingStatus);
        System.assertEquals('Partially Paid', opportunityRecord.Billing_Status__c);
        System.assertEquals('Accrued', commissionRecord.Status__c);
        System.assertEquals(null, commissionRecord.Payable_Date__c);
    }

    @IsTest
    static void getInvoiceForReceiptRejectsVoidAndWrongOpportunity() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Receipt Guard Opp', 900);
        Fixture otherFixture = createFixture('Other Receipt Opp', 400);
        Invoice__c voidInvoice = buildInvoice(fixture, 'INV-VOID', 900, 'Void', 'Balance', Date.today());
        Invoice__c otherInvoice = buildInvoice(otherFixture, 'INV-OTHER', 400, 'Sent', 'Balance', Date.today());
        insert new List<Invoice__c>{ voidInvoice, otherInvoice };

        Boolean voidRejected = false;
        Boolean wrongOpportunityRejected = false;
        Test.startTest();
        try {
            BillingControl_Receivables.getInvoiceForReceipt(voidInvoice.Id, fixture.opportunityId);
        } catch (AuraHandledException error) {
            voidRejected = true;
        }
        try {
            BillingControl_Receivables.getInvoiceForReceipt(otherInvoice.Id, fixture.opportunityId);
        } catch (AuraHandledException error) {
            wrongOpportunityRejected = true;
        }
        Test.stopTest();

        System.assertEquals(true, voidRejected);
        System.assertEquals(true, wrongOpportunityRejected);
    }

    @IsTest
    static void threePartialPaymentsLeaveCommissionAccruedUntilPaidInFull() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Fixture fixture = createFixture('Three Partial Opp', 5000);
        insert new Commission__c(
            Opportunity__c = fixture.opportunityId,
            Sales_Person__c = UserInfo.getUserId(),
            Status__c = 'Accrued',
            Commission_Rate__c = 10,
            Unique_Key__c = String.valueOf(fixture.opportunityId) + String.valueOf(UserInfo.getUserId())
        );
        Invoice__c invoiceRecord = buildInvoice(fixture, 'INV-PARTIALS', 5000, 'Sent', 'Balance', Date.today());
        insert invoiceRecord;

        Test.startTest();
        BillingControl_Receivables.postInvoiceReceipt(fixture.opportunityId, invoiceRecord.Id, 2000, Date.today(), paymentMethod(), 'P1');
        BillingControl_Receivables.postInvoiceReceipt(fixture.opportunityId, invoiceRecord.Id, 1000, Date.today(), paymentMethod(), 'P2');
        BillingControl_Receivables.postInvoiceReceipt(fixture.opportunityId, invoiceRecord.Id, 2000, Date.today(), paymentMethod(), 'P3');
        Test.stopTest();

        System.assertEquals(3, [SELECT COUNT() FROM Invoice_Payment__c WHERE Invoice__c = :invoiceRecord.Id]);
        Invoice__c paidInvoice = [SELECT Status__c, Balance_Due__c FROM Invoice__c WHERE Id = :invoiceRecord.Id];
        Opportunity opportunityRecord = [SELECT Billing_Status__c FROM Opportunity WHERE Id = :fixture.opportunityId];
        Commission__c commissionRecord = [
            SELECT Status__c, Paid_Amount__c, Commission_Paid__c, Amount_Basis__c
            FROM Commission__c
            WHERE Opportunity__c = :fixture.opportunityId
        ];
        System.assertEquals('Paid', paidInvoice.Status__c);
        System.assertEquals(0, paidInvoice.Balance_Due__c);
        System.assertEquals('Paid', opportunityRecord.Billing_Status__c);
        System.assertEquals('Payable', commissionRecord.Status__c);
        System.assertEquals(null, commissionRecord.Paid_Amount__c);
        System.assertEquals(0, commissionRecord.Commission_Paid__c == null ? 0 : commissionRecord.Commission_Paid__c);
        System.assertEquals('Invoiced Total', commissionRecord.Amount_Basis__c);
    }

    private static BillingControl_ReceivablesWorklist.SectionWrapper section(
        BillingControl_ReceivablesWorklist.TabRuntime tabRuntime,
        String categoryKey
    ) {
        for (BillingControl_ReceivablesWorklist.SectionWrapper sectionWrapper : tabRuntime.invoiceSections) {
            if (sectionWrapper.categoryKey == categoryKey) {
                return sectionWrapper;
            }
        }
        System.assert(false, 'Missing section ' + categoryKey);
        return null;
    }

    private static BillingControl_Invoicing.PostReceiptInputWrapper receipt(
        Id opportunityId,
        Decimal amountReceived,
        String referenceNumber
    ) {
        BillingControl_Invoicing.PostReceiptInputWrapper input = new BillingControl_Invoicing.PostReceiptInputWrapper();
        input.opportunityId = opportunityId;
        input.amountReceived = amountReceived;
        input.paymentDate = Date.today();
        input.paymentMethod = paymentMethod();
        input.referenceNumber = referenceNumber;
        return input;
    }

    private static String paymentMethod() {
        for (Schema.PicklistEntry entry : Invoice_Payment__c.Payment_Method__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return 'Wire';
    }

    private class Fixture {
        Id accountId;
        Id opportunityId;
        Id workOrderId;
    }

    private static Fixture createFixture(String opportunityName, Decimal amountValue) {
        Account accountRecord = new Account(Name = opportunityName + ' Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType(opportunityName + ' Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = amountValue,
            CloseDate = Date.today().addDays(20),
            Billing_Status__c = 'Billed (Outstanding Receivable)',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true,
            Quote_Number__c = 'Q-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = opportunityName + ' WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;

        Fixture fixture = new Fixture();
        fixture.accountId = accountRecord.Id;
        fixture.opportunityId = opportunityRecord.Id;
        fixture.workOrderId = workOrderRecord.Id;
        return fixture;
    }

    private static Invoice__c buildInvoice(
        Fixture fixture,
        String invoiceNumber,
        Decimal totalAmount,
        String statusValue,
        String invoiceType,
        Date invoiceDate
    ) {
        return new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = fixture.opportunityId,
            Account__c = fixture.accountId,
            Status__c = statusValue,
            Invoice_Date__c = invoiceDate,
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = totalAmount,
            Tax_Amount__c = 0,
            Total_Amount__c = totalAmount,
            Amount_Paid__c = 0,
            Balance_Due__c = totalAmount,
            Invoice_Type__c = invoiceType,
            Amount_Source__c = 'Derived'
        );
    }
}
