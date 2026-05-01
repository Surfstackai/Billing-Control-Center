@isTest
private class BillingControlCenterServiceTest {
    @testSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'Billing Control Center Test Account');
        insert accountRecord;

        WorkType installType = TestDataFactory.createWorkType('Install', 2);
        WorkType repairType = TestDataFactory.createWorkType('Repair', 3);

        List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Awaiting Billing Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Prospecting',
                Amount = 100,
                CloseDate = Date.today().addDays(10),
                Billing_Status__c = 'Ready for Billing',
                Ready_for_Billing_Date__c = Date.today().addDays(-5),
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Ready To Bill Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Qualification',
                Amount = 200,
                CloseDate = Date.today().addDays(15),
                Billing_Status__c = 'Ready for Billing',
                Ready_for_Billing_Date__c = Date.today(),
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Outstanding Receivable Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 300,
                CloseDate = Date.today().addDays(20),
                Billing_Status__c = getOutstandingReceivableStatusValue(),
                Work_Type__c = repairType.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Paid Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 400,
                CloseDate = Date.today().addDays(25),
                Billing_Status__c = 'Paid',
                Work_Type__c = installType.Id,
                Do_not_create_Work_Order__c = true
            )
        };
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'Awaiting Billing Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                Priority = 'High',
                WorkTypeId = installType.Id
            ),
            new WorkOrder(
                Subject = 'Outstanding Receivable Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                Priority = 'Medium',
                WorkTypeId = repairType.Id
            )
        };
        insert workOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[0].Id,
                Work_Order__c = workOrders[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[2].Id,
                Work_Order__c = workOrders[1].Id
            )
        };

        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = workOrders[0].Id,
                Status = 'Completed',
                SchedStartTime = System.now().addDays(-6),
                SchedEndTime = System.now().addDays(-6).addHours(2),
                ActualEndTime = System.now().addDays(-4),
                Subject = 'Completed Unbilled Older',
                Opportunity__c = opportunities[0].Id
            ),
            new ServiceAppointment(
                ParentRecordId = workOrders[1].Id,
                Status = 'Completed',
                SchedStartTime = System.now().addDays(-2),
                SchedEndTime = System.now().addDays(-2).addHours(2),
                ActualEndTime = System.now().addDays(-1),
                Subject = 'Completed Unbilled Recent',
                Opportunity__c = opportunities[1].Id
            ),
            new ServiceAppointment(
                ParentRecordId = workOrders[1].Id,
                Status = 'Completed',
                SchedStartTime = System.now().addDays(-10),
                SchedEndTime = System.now().addDays(-10).addHours(2),
                ActualEndTime = System.now().addDays(-9),
                Subject = 'Completed Billed Historical',
                Opportunity__c = opportunities[1].Id,
                Invoice_Number__c = 'INV-HIST-001'
            )
        };

        insert new List<Commission__c>{
            new Commission__c(
                Opportunity__c = opportunities[2].Id,
                Sales_Person__c = UserInfo.getUserId(),
                Commission_Rate__c = 10,
                Commission_Paid__c = 0,
                Unique_Key__c = opportunities[2].Id + UserInfo.getUserId() + '-earned'
            ),
            new Commission__c(
                Opportunity__c = opportunities[3].Id,
                Sales_Person__c = UserInfo.getUserId(),
                Commission_Rate__c = 15,
                Commission_Paid__c = 10,
                Unique_Key__c = opportunities[3].Id + UserInfo.getUserId() + '-payable'
            )
        };
    }

    @isTest
    static void testBillingMetrics() {
        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getBillingControlMetrics();
        BillingControl_Invoicing.OpportunityBillingMetricsWrapper legacyMetrics =
            BillingControl_Invoicing.getOpportunityBillingMetrics();
        Test.stopTest();

        System.assertEquals(1, metrics.completedMoreThan2Days, 'Expected one completed opportunity older than two days.');
        System.assertEquals(1, metrics.readyToBill, 'Expected one recent ready-to-bill opportunity.');
        System.assertEquals(100, metrics.unbilledRevenue, 'Expected awaiting-billing revenue total.');
        System.assertEquals(300, metrics.outstandingAr, 'Expected outstanding AR total.');

        System.assertEquals(1, legacyMetrics.awaitedBilling, 'Legacy metric should still return older ready-for-billing count.');
        System.assertEquals(1, legacyMetrics.readyForBillingLast2Days, 'Legacy metric should still return recent ready-for-billing count.');
        System.assertEquals(1, legacyMetrics.outstandingReceivables, 'Legacy metric should still return outstanding receivable count.');
        System.assertEquals(200, legacyMetrics.totalUnbilledRevenue, 'Legacy metric should still return recent ready-for-billing revenue.');
    }

    @isTest
    static void testOpportunityQueries() {
        Test.startTest();
        List<BillingControl_Invoicing.OpportunityWrapper> awaitingBilling =
            BillingControl_Invoicing.getAwaitingBillingOpportunities();
        List<BillingControl_Invoicing.OpportunityWrapper> outstandingReceivables =
            BillingControl_Invoicing.getOutstandingReceivableOpportunities();
        List<BillingControl_Invoicing.OpportunityWrapper> readyForBilling =
            BillingControl_Invoicing.getReadyForBillingOpportunities();
        Test.stopTest();

        System.assertEquals(1, awaitingBilling.size(), 'Expected one awaiting billing opportunity.');
        System.assertEquals('Awaiting Billing Opportunity', awaitingBilling[0].name, 'The awaiting billing opportunity should match the older ready record.');
        System.assertEquals(1, awaitingBilling[0].workOrders.size(), 'Awaiting billing opportunity should include its related work order.');
        System.assertEquals('High', awaitingBilling[0].workOrders[0].priority, 'Related work order fields should be mapped.');

        System.assertEquals(1, outstandingReceivables.size(), 'Expected one outstanding receivable opportunity.');
        System.assertEquals('Outstanding Receivable Opportunity', outstandingReceivables[0].name, 'Outstanding receivable opportunity should match the billed record.');
        System.assertEquals(1, outstandingReceivables[0].workOrders.size(), 'Outstanding receivable opportunity should include its related work order.');

        System.assertEquals(1, readyForBilling.size(), 'Expected one recent ready-for-billing opportunity.');
        System.assertEquals('Ready To Bill Opportunity', readyForBilling[0].name, 'Recent ready-for-billing opportunity should be returned by the legacy query.');
        System.assertEquals(0, readyForBilling[0].workOrders.size(), 'Opportunity without junction rows should return an empty work order list.');
    }

    @isTest
    static void testServiceAppointmentBillingMetricsAndGrouping() {
        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetrics();
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getBillableServiceAppointmentGroups();
        Test.stopTest();

        System.assertEquals(1, metrics.completedMoreThan2Days, 'One unbilled completed appointment should be older than two days.');
        System.assertEquals(2, metrics.readyToBill, 'Two unbilled completed appointments should be ready to bill.');
        System.assertEquals(300, metrics.unbilledRevenue, 'Uninvoiced revenue should sum unique opportunity amounts.');

        System.assertEquals(3, sections.size(), 'Appointments should be returned in the three KPI-backed sections.');
        Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sectionByKey =
            new Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
        }

        System.assertEquals(1, sectionByKey.get('AGED_COMPLETED').serviceAppointmentCount, 'Aged section should only include appointments older than two days.');
        System.assertEquals(100, sectionByKey.get('AGED_COMPLETED').totalBillableAmount, 'Aged section should total only its contributing appointment.');
        System.assertEquals(2, sectionByKey.get('READY_TO_BILL').serviceAppointmentCount, 'Ready-to-bill section should include all completed unbilled appointments.');
        System.assertEquals(300, sectionByKey.get('READY_TO_BILL').totalBillableAmount, 'Ready-to-bill section should total all completed unbilled appointments.');
        System.assertEquals(2, sectionByKey.get('UNBILLED_REVENUE').serviceAppointmentCount, 'Revenue section should include the appointments contributing to the revenue sum.');
        System.assertEquals(300, sectionByKey.get('UNBILLED_REVENUE').totalBillableAmount, 'Revenue section should match the uninvoiced revenue KPI.');

        List<BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper> groups =
            sectionByKey.get('READY_TO_BILL').opportunityGroups;
        System.assertEquals(2, groups.size(), 'Appointments should still group by opportunity inside each KPI section.');
        Map<String, BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper> groupByName =
            new Map<String, BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper>();
        for (BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper opportunityGroup : groups) {
            groupByName.put(opportunityGroup.opportunityName, opportunityGroup);
        }

        System.assertEquals('Pending Invoice', groupByName.get('Awaiting Billing Opportunity').billingState, 'Opportunity with no prior billed appointments should be Pending Invoice.');
        System.assertEquals('Partial', groupByName.get('Ready To Bill Opportunity').billingState, 'Opportunity with prior billed appointments should be Partial.');
        System.assertEquals('Ready for Billing', groupByName.get('Awaiting Billing Opportunity').opportunityBillingStatus);
        System.assertEquals(100, groupByName.get('Awaiting Billing Opportunity').opportunityAmount);
    }

    @isTest
    static void testServiceAppointmentBillingMetricsDedupesRevenueByOpportunity() {
        BillingControl_Invoicing.BillingControlMetricsWrapper beforeMetrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetrics();

        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];

        Opportunity dedupeOpportunity = new Opportunity(
            Name = 'Dedupe Revenue Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Qualification',
            Amount = 10000,
            CloseDate = Date.today().addDays(40),
            Billing_Status__c = 'Ready for Billing',
            Ready_for_Billing_Date__c = Date.today(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert dedupeOpportunity;

        WorkOrder dedupeWorkOrder = new WorkOrder(
            Subject = 'Dedupe Revenue Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert dedupeWorkOrder;

        insert new Opportunity_WorkOrder__c(
            Opportunity__c = dedupeOpportunity.Id,
            Work_Order__c = dedupeWorkOrder.Id
        );

        Datetime baseStart = System.now().addDays(-1);
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = dedupeWorkOrder.Id,
                Opportunity__c = dedupeOpportunity.Id,
                Status = 'Completed',
                SchedStartTime = baseStart,
                SchedEndTime = baseStart.addHours(1),
                ActualEndTime = baseStart.addHours(1),
                Subject = 'Dedupe SA 1'
            ),
            new ServiceAppointment(
                ParentRecordId = dedupeWorkOrder.Id,
                Opportunity__c = dedupeOpportunity.Id,
                Status = 'Completed',
                SchedStartTime = baseStart.addHours(2),
                SchedEndTime = baseStart.addHours(3),
                ActualEndTime = baseStart.addHours(3),
                Subject = 'Dedupe SA 2'
            )
        };

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper afterMetrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetrics();
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getBillableServiceAppointmentGroups();
        Test.stopTest();

        System.assertEquals(
            beforeMetrics.readyToBill + 2,
            afterMetrics.readyToBill,
            'Billable SA count should still count each Service Appointment.'
        );
        System.assertEquals(
            beforeMetrics.unbilledRevenue + 10000,
            afterMetrics.unbilledRevenue,
            'Uninvoiced revenue should count each opportunity only once even when multiple SAs exist.'
        );

        BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper readySection;
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            if (section.categoryKey == 'READY_TO_BILL') {
                readySection = section;
                break;
            }
        }
        System.assertNotEquals(null, readySection, 'Ready-to-bill section should be returned.');

        BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper dedupeGroup;
        for (BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper opportunityGroup : readySection.opportunityGroups) {
            if (opportunityGroup.opportunityId == dedupeOpportunity.Id) {
                dedupeGroup = opportunityGroup;
                break;
            }
        }
        System.assertNotEquals(null, dedupeGroup, 'Rows should be grouped under the opportunity.');
        System.assertEquals(2, dedupeGroup.serviceAppointmentCount, 'Both appointments should be grouped under one opportunity header.');
        System.assertEquals(10000, dedupeGroup.opportunityAmount, 'Opportunity amount should be carried on the group header.');
    }

    @isTest
    static void testCompleteServiceAppointmentBillingGroupsByOpportunity() {
        List<ServiceAppointment> toBill = [
            SELECT Id, Opportunity__c, Invoice_Number__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY Opportunity__c ASC
        ];
        System.assertEquals(2, toBill.size(), 'Expected two unbilled completed service appointments in setup data.');

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ toBill[0].Id, toBill[1].Id },
                null
            );
        Test.stopTest();

        System.assertEquals(2, result.serviceAppointmentsUpdated, 'Selected service appointments should be marked billed.');
        System.assertEquals(2, result.invoicesCreated, 'One invoice group should be created per opportunity.');
        System.assertEquals(2, result.invoiceGroups.size(), 'Invoice group details should be returned for each opportunity.');

        List<Invoice__c> createdInvoices = [
            SELECT Id, Invoice_Number__c, Opportunity__c
            FROM Invoice__c
            WHERE Opportunity__c IN :new Set<Id>{ toBill[0].Opportunity__c, toBill[1].Opportunity__c }
        ];
        System.assertEquals(2, createdInvoices.size(), 'An invoice header should be created per selected opportunity.');
        Set<Id> createdInvoiceIds = new Set<Id>();
        for (Invoice__c invoiceRecord : createdInvoices) {
            createdInvoiceIds.add(invoiceRecord.Id);
        }

        List<Invoice_Line__c> createdInvoiceLines = [
            SELECT Id, Invoice__c
            FROM Invoice_Line__c
            WHERE Invoice__c IN :createdInvoiceIds
        ];
        System.assertEquals(2, createdInvoiceLines.size(), 'Each billed appointment should create one invoice line.');

        List<ServiceAppointment> billedAppointments = [
            SELECT Id, Invoice_Number__c
            FROM ServiceAppointment
            WHERE Id IN :new Map<Id, ServiceAppointment>(toBill).keySet()
        ];
        for (ServiceAppointment appointment : billedAppointments) {
            System.assertNotEquals(null, appointment.Invoice_Number__c, 'Billed appointment should have an invoice number.');
            System.assert(appointment.Invoice_Number__c.startsWith('INV-'), 'Generated invoice number should use the INV- prefix.');
        }

        List<Opportunity> updatedOpportunities = [
            SELECT Id, Billing_Status__c
            FROM Opportunity
            WHERE Id IN :new Set<Id>{ toBill[0].Opportunity__c, toBill[1].Opportunity__c }
        ];
        for (Opportunity updatedOpportunity : updatedOpportunities) {
            System.assertEquals(
                getOutstandingReceivableStatusValue(),
                updatedOpportunity.Billing_Status__c,
                'Complete Billing should move selected opportunities to billed outstanding receivables status.'
            );
        }
    }

    @isTest
    static void testCompleteServiceAppointmentBillingUsesProvidedInvoiceNumbers() {
        ServiceAppointment oneAppointment = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        Map<String, String> invoiceNumberByOpportunityId = new Map<String, String>();
        invoiceNumberByOpportunityId.put(String.valueOf(oneAppointment.Opportunity__c), 'USER-INV-10001');

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ oneAppointment.Id },
                invoiceNumberByOpportunityId
            );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'One invoice should be created for the opportunity.');
        List<Invoice__c> created = [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Opportunity__c = :oneAppointment.Opportunity__c
            AND Invoice_Number__c = 'USER-INV-10001'
        ];
        System.assertEquals(1, created.size(), 'Invoice header should use the provided invoice number.');
        System.assertEquals('USER-INV-10001', created[0].Invoice_Number__c);
    }

    @isTest
    static void testCommissionMetricsAndGrouping() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [
            SELECT Id
            FROM WorkType
            LIMIT 1
        ];

        insert new Opportunity(
            Name = 'Revenue Under Collection Only Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 150,
            CloseDate = Date.today().addDays(30),
            Billing_Status__c = getOutstandingReceivableStatusValue(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );

        Test.startTest();
        BillingControl_Invoicing.CommissionMetricsWrapper metrics =
            BillingControl_Invoicing.getCommissionMetrics();
        List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getCommissionData('kpi');
        Test.stopTest();

        System.assertEquals(300, metrics.unbilledRevenue, 'Ready-for-billing revenue should sum all ready opportunities.');
        System.assert(metrics.unbilledRevenueCount > 0, 'Ready-for-billing count should include qualifying opportunities.');
        System.assertEquals(450, metrics.revenueUnderCollection, 'Outstanding receivable revenue should sum billed opportunities.');
        System.assertEquals(2, metrics.revenueUnderCollectionCount, 'Revenue under collection count should include both outstanding opportunities.');
        System.assertEquals(30, metrics.commissionEarned, 'Commission earned should total outstanding receivable commissions.');
        System.assert(metrics.commissionEarnedCount > 0, 'Commission earned count should include qualifying commissions.');
        System.assertEquals(50, metrics.commissionPayable, 'Commission payable should total unpaid paid-opportunity commissions.');
        System.assert(metrics.commissionPayableCount > 0, 'Commission payable count should include qualifying commissions.');

        System.assertEquals(3, sections.size(), 'Expected exactly three KPI sections.');

        Map<String, BillingControl_Invoicing.CommissionKpiCategoryWrapper> sectionByKey =
            new Map<String, BillingControl_Invoicing.CommissionKpiCategoryWrapper>();
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
        }

        BillingControl_Invoicing.CommissionKpiCategoryWrapper revenueSection =
            sectionByKey.get('REVENUE_UNDER_COLLECTION');
        BillingControl_Invoicing.CommissionKpiCategoryWrapper earnedSection =
            sectionByKey.get('COMMISSION_EARNED');
        BillingControl_Invoicing.CommissionKpiCategoryWrapper payableSection =
            sectionByKey.get('COMMISSION_PAYABLE');

        System.assertNotEquals(null, revenueSection, 'Revenue under collection section should be present.');
        System.assertNotEquals(null, earnedSection, 'Commission earned section should be present.');
        System.assertNotEquals(null, payableSection, 'Commission payable section should be present.');

        System.assertEquals(2, revenueSection.opportunityCount, 'Revenue section should include all outstanding receivable opportunities.');
        System.assertEquals(450, revenueSection.totalAmount, 'Revenue section should sum invoice amount for all outstanding receivable opportunities.');
        System.assertEquals(0, revenueSection.totalCommission, 'Revenue section should not include commission amount.');
        System.assertEquals(1, revenueSection.salespersonGroups.size(), 'Revenue section should preserve salesperson grouping.');
        Set<String> revenueOpportunityNames = new Set<String>();
        for (BillingControl_Invoicing.SalespersonWrapper revenueSalesperson : revenueSection.salespersonGroups) {
            for (BillingControl_Invoicing.OpportunityWrapper revenueOpportunity : revenueSalesperson.opportunities) {
                revenueOpportunityNames.add(revenueOpportunity.opportunityName);
            }
        }
        System.assertEquals(true, revenueOpportunityNames.contains('Outstanding Receivable Opportunity'), 'Revenue section should include commissioned outstanding opportunities because they contribute to A/R.');
        System.assertEquals(true, revenueOpportunityNames.contains('Revenue Under Collection Only Opportunity'), 'Revenue section should include non-commission outstanding opportunities.');

        System.assertEquals(1, earnedSection.opportunityCount, 'Earned section should include outstanding opportunities with commission.');
        System.assertEquals(300, earnedSection.totalAmount, 'Earned section should carry invoice amount from outstanding opportunities with commission.');
        System.assertEquals(30, earnedSection.totalCommission, 'Earned section should carry accrued commission amount.');
        System.assertEquals(1, earnedSection.salespersonGroups.size(), 'Earned section should preserve salesperson grouping.');
        System.assertEquals(
            'Outstanding Receivable Opportunity',
            earnedSection.salespersonGroups[0].opportunities[0].opportunityName,
            'Earned section should include the outstanding commissioned opportunity.'
        );

        System.assertEquals(1, payableSection.opportunityCount, 'Payable section should include paid opportunities with unpaid commission.');
        System.assertEquals(400, payableSection.totalAmount, 'Payable section should aggregate paid opportunity amount.');
        System.assertEquals(60, payableSection.totalCommission, 'Payable section should aggregate commission amount.');
        System.assertEquals(10, payableSection.totalPaid, 'Payable section should aggregate paid commission amount.');
        System.assertEquals(1, payableSection.salespersonGroups.size(), 'Payable section should preserve salesperson grouping.');
        System.assertEquals(
            'Paid Opportunity',
            payableSection.salespersonGroups[0].opportunities[0].opportunityName,
            'Payable section should include the paid commissioned opportunity.'
        );

        Set<Id> revenueOpportunityIds = new Set<Id>();
        for (BillingControl_Invoicing.SalespersonWrapper salesperson : revenueSection.salespersonGroups) {
            for (BillingControl_Invoicing.OpportunityWrapper opportunity : salesperson.opportunities) {
                revenueOpportunityIds.add(opportunity.opportunityId);
            }
        }
        Set<Id> earnedOpportunityIds = new Set<Id>();
        for (BillingControl_Invoicing.SalespersonWrapper salesperson : earnedSection.salespersonGroups) {
            for (BillingControl_Invoicing.OpportunityWrapper opportunity : salesperson.opportunities) {
                earnedOpportunityIds.add(opportunity.opportunityId);
            }
        }
        Set<Id> overlapIds = new Set<Id>(revenueOpportunityIds);
        overlapIds.retainAll(earnedOpportunityIds);
        System.assertEquals(
            1,
            overlapIds.size(),
            'Outstanding receivable opportunities with commission should appear in both A/R and Commission Accrued sections.'
        );

        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            Set<Id> sectionOpportunityIds = new Set<Id>();
            Integer sectionOpportunityTotal = 0;
            for (BillingControl_Invoicing.SalespersonWrapper salesperson : section.salespersonGroups) {
                for (BillingControl_Invoicing.OpportunityWrapper opportunity : salesperson.opportunities) {
                    sectionOpportunityTotal++;
                    System.assertEquals(
                        true,
                        sectionOpportunityIds.add(opportunity.opportunityId),
                        'An opportunity should not be duplicated within the same KPI category.'
                    );
                }
            }
            System.assertEquals(
                section.opportunityCount,
                sectionOpportunityTotal,
                'Section opportunity count should match grouped opportunity rows.'
            );
        }
    }

    @isTest
    static void testUpdateCommissionPaid() {
        Commission__c payableCommission = [
            SELECT Id, Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__r.Name = 'Paid Opportunity'
            LIMIT 1
        ];

        System.assertEquals(10, payableCommission.Commission_Paid__c, 'Test data should start partially paid.');

        Test.startTest();
        BillingControl_Invoicing.updateCommissionPaid(new List<Id>{ payableCommission.Id });
        Test.stopTest();

        Commission__c refreshedCommission = [
            SELECT Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Id = :payableCommission.Id
        ];

        System.assertEquals(
            refreshedCommission.Commission_Amount__c,
            refreshedCommission.Commission_Paid__c,
            'Pay action should mark the commission as fully paid.'
        );
    }

    @isTest
    static void testPostReceiptSupportsPartialAndFullPayments() {
        Opportunity outstandingOpportunity = [
            SELECT Id, Amount, Amount_Paid__c, Billing_Status__c
            FROM Opportunity
            WHERE Name = 'Outstanding Receivable Opportunity'
            LIMIT 1
        ];

        BillingControl_Invoicing.PostReceiptInputWrapper partialReceipt =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        partialReceipt.opportunityId = outstandingOpportunity.Id;
        partialReceipt.amountReceived = 100;
        partialReceipt.paymentDate = Date.today();
        partialReceipt.paymentMethod = getPaymentMethodValue();
        partialReceipt.referenceNumber = 'PARTIAL-001';

        Test.startTest();
        BillingControl_Invoicing.PaymentReceiptResultWrapper partialResult =
            BillingControl_Invoicing.postReceipt(partialReceipt);

        Opportunity partiallyPaidOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :outstandingOpportunity.Id
        ];

        System.assertEquals(100, partialResult.totalPaid, 'Partial result should report the running paid total.');
        System.assertEquals(200, partialResult.balanceDue, 'Partial result should report the remaining balance.');
        System.assertEquals('Partially Paid', partialResult.billingStatus, 'Partial result should report the updated status.');
        System.assertEquals('Partially Paid', partiallyPaidOpportunity.Billing_Status__c, 'Opportunity should move to Partially Paid after a partial receipt.');

        Commission__c partiallyAccruedCommission = [
            SELECT Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__c = :outstandingOpportunity.Id
            LIMIT 1
        ];
        System.assertEquals(10, partiallyAccruedCommission.Commission_Paid__c, 'Partial payment should accrue commission proportionally.');

        BillingControl_Invoicing.PostReceiptInputWrapper finalReceipt =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        finalReceipt.opportunityId = outstandingOpportunity.Id;
        finalReceipt.amountReceived = 200;
        finalReceipt.paymentDate = Date.today();
        finalReceipt.paymentMethod = getPaymentMethodValue();
        finalReceipt.referenceNumber = 'FINAL-001';

        BillingControl_Invoicing.PaymentReceiptResultWrapper finalResult =
            BillingControl_Invoicing.postReceipt(finalReceipt);
        Test.stopTest();

        Opportunity paidOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :outstandingOpportunity.Id
        ];

        System.assertEquals(300, finalResult.totalPaid, 'Final receipt should bring the running total to the invoice amount.');
        System.assertEquals(0, finalResult.balanceDue, 'Final receipt should clear the remaining balance.');
        System.assertEquals('Paid', finalResult.billingStatus, 'Final receipt should report a paid invoice.');
        System.assertEquals('Paid', paidOpportunity.Billing_Status__c, 'Opportunity should move to Paid after the balance is cleared.');

        Commission__c fullyAccruedCommission = [
            SELECT Commission_Amount__c, Commission_Paid__c
            FROM Commission__c
            WHERE Opportunity__c = :outstandingOpportunity.Id
            LIMIT 1
        ];
        System.assertEquals(
            fullyAccruedCommission.Commission_Amount__c,
            fullyAccruedCommission.Commission_Paid__c,
            'Final payment should fully accrue the remaining commission amount.'
        );

        List<Invoice_Payment__c> payments = [
            SELECT Amount_Received__c, Reference_Number__c, Invoice__c
            FROM Invoice_Payment__c
            WHERE Opportunity__c = :outstandingOpportunity.Id
            ORDER BY CreatedDate ASC
        ];

        System.assertEquals(2, payments.size(), 'Two payment records should be created for the partial and final receipts.');
        System.assertEquals(100, payments[0].Amount_Received__c, 'The first payment should capture the partial amount.');
        System.assertEquals(200, payments[1].Amount_Received__c, 'The second payment should capture the final amount.');
        System.assertNotEquals(null, payments[0].Invoice__c, 'Each payment should reference an invoice.');
        System.assertNotEquals(null, payments[1].Invoice__c, 'Each payment should reference an invoice.');
    }

    @isTest
    static void testPostReceiptRejectsOverpayment() {
        Opportunity outstandingOpportunity = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Outstanding Receivable Opportunity'
            LIMIT 1
        ];

        BillingControl_Invoicing.PostReceiptInputWrapper invalidReceipt =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        invalidReceipt.opportunityId = outstandingOpportunity.Id;
        invalidReceipt.amountReceived = 301;
        invalidReceipt.paymentDate = Date.today();
        invalidReceipt.paymentMethod = getPaymentMethodValue();
        invalidReceipt.referenceNumber = 'OVERPAY-001';

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            BillingControl_Invoicing.postReceipt(invalidReceipt);
            System.assert(false, 'Expected overpayment validation to throw an exception.');
        } catch (AuraHandledException error) {
            exceptionThrown = true;
            System.assert(String.isNotBlank(error.getMessage()), 'Expected an overpayment error message.');
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected overpayment validation to throw an exception.');
    }

    @isTest
    static void testPostReceiptValidatesRequiredInputs() {
        Opportunity outstandingOpportunity = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Outstanding Receivable Opportunity'
            LIMIT 1
        ];

        List<BillingControl_Invoicing.PostReceiptInputWrapper> invalidInputs =
            new List<BillingControl_Invoicing.PostReceiptInputWrapper>();

        invalidInputs.add(null);

        BillingControl_Invoicing.PostReceiptInputWrapper missingOpportunity =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        missingOpportunity.amountReceived = 10;
        missingOpportunity.paymentDate = Date.today();
        missingOpportunity.paymentMethod = getPaymentMethodValue();
        missingOpportunity.referenceNumber = 'REQ-001';
        invalidInputs.add(missingOpportunity);

        BillingControl_Invoicing.PostReceiptInputWrapper invalidAmount =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        invalidAmount.opportunityId = outstandingOpportunity.Id;
        invalidAmount.amountReceived = 0;
        invalidAmount.paymentDate = Date.today();
        invalidAmount.paymentMethod = getPaymentMethodValue();
        invalidAmount.referenceNumber = 'REQ-002';
        invalidInputs.add(invalidAmount);

        BillingControl_Invoicing.PostReceiptInputWrapper missingDate =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        missingDate.opportunityId = outstandingOpportunity.Id;
        missingDate.amountReceived = 10;
        missingDate.paymentMethod = getPaymentMethodValue();
        missingDate.referenceNumber = 'REQ-003';
        invalidInputs.add(missingDate);

        BillingControl_Invoicing.PostReceiptInputWrapper missingMethod =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        missingMethod.opportunityId = outstandingOpportunity.Id;
        missingMethod.amountReceived = 10;
        missingMethod.paymentDate = Date.today();
        missingMethod.referenceNumber = 'REQ-004';
        invalidInputs.add(missingMethod);

        BillingControl_Invoicing.PostReceiptInputWrapper missingReference =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        missingReference.opportunityId = outstandingOpportunity.Id;
        missingReference.amountReceived = 10;
        missingReference.paymentDate = Date.today();
        missingReference.paymentMethod = getPaymentMethodValue();
        invalidInputs.add(missingReference);

        for (BillingControl_Invoicing.PostReceiptInputWrapper invalidInput : invalidInputs) {
            Boolean exceptionThrown = false;
            try {
                BillingControl_Invoicing.postReceipt(invalidInput);
            } catch (AuraHandledException error) {
                exceptionThrown = true;
                System.assert(String.isNotBlank(error.getMessage()), 'Validation exceptions should include a message.');
            }
            System.assertEquals(true, exceptionThrown, 'Each invalid input should be rejected.');
        }
    }

    @isTest
    static void testUpdateCommissionPaidHandlesNullAndEmptyInput() {
        Test.startTest();
        BillingControl_Invoicing.updateCommissionPaid(null);
        BillingControl_Invoicing.updateCommissionPaid(new List<Id>());
        Test.stopTest();

        System.assertEquals(true, true, 'Null and empty commission lists should be ignored without error.');
    }

    @isTest
    static void testCreateCommissionRecordsHandlesEmptyInvalidSuccessAndDuplicate() {
        Account accountRecord = new Account(Name = 'Commission Creation Test Account');
        insert accountRecord;

        WorkType workTypeRecord = TestDataFactory.createWorkType('Commission Work Type', 2);

        Opportunity successOpportunity = new Opportunity(
            Name = 'Commission Create Success Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 125,
            CloseDate = Date.today().addDays(5),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity duplicateOpportunity = new Opportunity(
            Name = 'Commission Create Duplicate Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 225,
            CloseDate = Date.today().addDays(6),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ successOpportunity, duplicateOpportunity };

        insert new Commission__c(
            Opportunity__c = duplicateOpportunity.Id,
            Sales_Person__c = UserInfo.getUserId(),
            Commission_Rate__c = 12,
            Unique_Key__c = duplicateOpportunity.Id + UserInfo.getUserId()
        );

        Test.startTest();
        BillingControl_Invoicing.CommissionResultWrapper emptyResult =
            BillingControl_Invoicing.createCommissionRecords(null);

        BillingControl_Invoicing.CommissionInputWrapper invalidInput =
            new BillingControl_Invoicing.CommissionInputWrapper();
        BillingControl_Invoicing.CommissionResultWrapper invalidOnlyResult =
            BillingControl_Invoicing.createCommissionRecords(
                new List<BillingControl_Invoicing.CommissionInputWrapper>{ invalidInput }
            );

        BillingControl_Invoicing.CommissionInputWrapper successInput =
            new BillingControl_Invoicing.CommissionInputWrapper();
        successInput.opportunityId = successOpportunity.Id;
        successInput.commissionRate = 8;

        BillingControl_Invoicing.CommissionInputWrapper duplicateInput =
            new BillingControl_Invoicing.CommissionInputWrapper();
        duplicateInput.opportunityId = duplicateOpportunity.Id;
        duplicateInput.ownerId = UserInfo.getUserId();
        duplicateInput.commissionRate = 12;

        BillingControl_Invoicing.CommissionResultWrapper mixedResult =
            BillingControl_Invoicing.createCommissionRecords(
                new List<BillingControl_Invoicing.CommissionInputWrapper>{
                    successInput,
                    duplicateInput,
                    invalidInput
                }
            );
        Test.stopTest();

        System.assertEquals(0, emptyResult.successCount, 'Null input should not create any commissions.');
        System.assertEquals(0, emptyResult.errorMessages.size(), 'Null input should return no errors.');

        System.assertEquals(0, invalidOnlyResult.successCount, 'Inputs without opportunity ids should be ignored.');
        System.assertEquals(0, invalidOnlyResult.errorMessages.size(), 'Ignored inputs should not produce errors.');

        System.assertEquals(1, mixedResult.successCount, 'Exactly one commission should be created successfully.');
        System.assertEquals(1, mixedResult.errorMessages.size(), 'Duplicate commission should be reported once.');
        System.assert(
            mixedResult.errorMessages[0].contains('Commission already exists for Opportunity'),
            'Duplicate errors should be translated into the friendly duplicate message.'
        );

        Opportunity refreshedSuccessOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :successOpportunity.Id
        ];
        System.assertEquals(
            getOutstandingReceivableStatusValue(),
            refreshedSuccessOpportunity.Billing_Status__c,
            'Successful commission creation should move the opportunity into outstanding receivable.'
        );

        List<Commission__c> createdCommissions = [
            SELECT Opportunity__c, Sales_Person__c, Commission_Rate__c
            FROM Commission__c
            WHERE Opportunity__c = :successOpportunity.Id
        ];
        System.assertEquals(1, createdCommissions.size(), 'One commission record should exist for the successful opportunity.');
        System.assertEquals(UserInfo.getUserId(), createdCommissions[0].Sales_Person__c, 'Owner should default from the opportunity when omitted.');
        System.assertEquals(8, createdCommissions[0].Commission_Rate__c, 'The requested commission rate should be preserved.');
    }

    private static String getOutstandingReceivableStatusValue() {
        for (Schema.PicklistEntry entry : Opportunity.Billing_Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == 'Billed (Outstanding Receivables)') {
                return entry.getValue();
            }
        }
        for (Schema.PicklistEntry entry : Opportunity.Billing_Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == 'Billed (Outstanding Receivable)') {
                return entry.getValue();
            }
        }
        return 'Billed (Outstanding Receivable)';
    }

    private static String getPaymentMethodValue() {
        for (Schema.PicklistEntry entry : Invoice_Payment__c.Payment_Method__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return 'Wire';
    }
}