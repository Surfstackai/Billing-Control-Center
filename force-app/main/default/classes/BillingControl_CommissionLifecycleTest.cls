@IsTest
private class BillingControl_CommissionLifecycleTest {
    @IsTest
    static void payableUsesInvoicedTotalAndPayRequiresPayable() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Commission Lifecycle Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Commission Lifecycle Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Commission Lifecycle Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 8000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Billed (Outstanding Receivable)',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true,
            Quote_Number__c = 'Q-CL-1'
        );
        insert opportunityRecord;
        insert new Invoice__c(
            Invoice_Number__c = 'Inv 94001',
            Opportunity__c = opportunityRecord.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 8000,
            Tax_Amount__c = 0,
            Total_Amount__c = 8000,
            Amount_Paid__c = 8000,
            Balance_Due__c = 0,
            Invoice_Type__c = 'Balance',
            Amount_Source__c = 'Entered'
        );
        Commission__c commissionRecord = new Commission__c(
            Opportunity__c = opportunityRecord.Id,
            Sales_Person__c = UserInfo.getUserId(),
            Status__c = 'Accrued',
            Commission_Rate__c = 10,
            Unique_Key__c = String.valueOf(opportunityRecord.Id) + String.valueOf(UserInfo.getUserId())
        );
        insert commissionRecord;

        Test.startTest();
        Boolean rejectedAccrued = false;
        try {
            BillingControl_CommissionLifecycle.payCommissions(
                new List<Id>{ commissionRecord.Id },
                Date.today(),
                null
            );
        } catch (AuraHandledException error) {
            rejectedAccrued = true;
        }
        BillingControl_CommissionLifecycle.markPayable(opportunityRecord.Id);
        BillingControl_CommissionLifecycle.payCommissions(
            new List<Id>{ commissionRecord.Id },
            Date.today().addDays(-3),
            null
        );
        BillingControl_CommissionLifecycle.TabRuntime tabRuntime =
            BillingControl_CommissionLifecycle.getTabRuntime(
                1L,
                'This Month',
                String.valueOf(Date.today().toStartOfMonth()),
                String.valueOf(Date.today()),
                null
            );
        Test.stopTest();

        Commission__c paidRecord = [
            SELECT Status__c, Paid_Date__c, Paid_Amount__c, Payable_Date__c, Amount_Basis__c
            FROM Commission__c
            WHERE Id = :commissionRecord.Id
        ];
        System.assertEquals(true, rejectedAccrued);
        System.assertEquals('Paid', paidRecord.Status__c);
        System.assertEquals('Invoiced Total', paidRecord.Amount_Basis__c);
        System.assertEquals(800, paidRecord.Paid_Amount__c);
        System.assertEquals(Date.today().addDays(-3), paidRecord.Paid_Date__c);
        System.assertEquals(1, tabRuntime.metrics.paidThisPeriodCount);
        BillingControl_CommissionLifecycle.CommissionRow paidRow;
        for (BillingControl_CommissionLifecycle.SectionWrapper section : tabRuntime.sections) {
            if (section.categoryKey == 'PAID' && !section.rows.isEmpty()) {
                paidRow = section.rows[0];
            }
        }
        System.assertEquals(8000, paidRow.customerPaidTotal);
        System.assertEquals(true, paidRow.customerPaidInFull);
    }

    @IsTest
    static void dateFilterUsesPaidDateNotCloseDate() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Paid Date Filter Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Paid Date Filter Type', 1);
        Opportunity thisMonth = new Opportunity(
            Name = 'Paid This Month Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 1000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity lastMonth = new Opportunity(
            Name = 'Paid Last Month Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 1000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ thisMonth, lastMonth };
        insert new List<Commission__c>{
            new Commission__c(
                Opportunity__c = thisMonth.Id,
                Sales_Person__c = UserInfo.getUserId(),
                Status__c = 'Paid',
                Paid_Date__c = Date.today(),
                Paid_Amount__c = 100,
                Unique_Key__c = String.valueOf(thisMonth.Id) + String.valueOf(UserInfo.getUserId())
            ),
            new Commission__c(
                Opportunity__c = lastMonth.Id,
                Sales_Person__c = UserInfo.getUserId(),
                Status__c = 'Paid',
                Paid_Date__c = Date.today().addMonths(-1),
                Paid_Amount__c = 50,
                Unique_Key__c = String.valueOf(lastMonth.Id) + String.valueOf(UserInfo.getUserId())
            )
        };

        Test.startTest();
        BillingControl_CommissionLifecycle.TabRuntime tabRuntime =
            BillingControl_CommissionLifecycle.getTabRuntime(
                1L,
                'This Month',
                String.valueOf(Date.today().toStartOfMonth()),
                String.valueOf(Date.today()),
                null
            );
        Test.stopTest();

        System.assertEquals(1, tabRuntime.metrics.paidThisPeriodCount, 'Paid section filters on Paid_Date__c.');
    }

    @IsTest
    static void ensureAccruedAndManualRateUseInvoicedTotal() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Manual Rate Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Manual Rate Type', 1);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Manual Rate Opp',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 5000,
            CloseDate = Date.today(),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true,
            OwnerId = UserInfo.getUserId()
        );
        insert opportunityRecord;

        Test.startTest();
        BillingControl_CommissionLifecycle.ensureAccrued(opportunityRecord);
        BillingControl_CommissionLifecycle.ensureAccrued(opportunityRecord);
        Commission__c accrued = [
            SELECT Id, Status__c, Commission_Rate__c
            FROM Commission__c
            WHERE Opportunity__c = :opportunityRecord.Id
        ];
        BillingControl_CommissionLifecycle.setManualRate(accrued.Id, 12.5);
        Test.stopTest();

        Commission__c updated = [
            SELECT Status__c, Commission_Rate__c
            FROM Commission__c
            WHERE Id = :accrued.Id
        ];
        System.assertEquals('Accrued', updated.Status__c);
        System.assertEquals(12.5, updated.Commission_Rate__c);
        System.assertEquals(1, [SELECT COUNT() FROM Commission__c WHERE Opportunity__c = :opportunityRecord.Id]);
    }
}
