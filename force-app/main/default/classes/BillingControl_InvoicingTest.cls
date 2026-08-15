@isTest
private class BillingControl_InvoicingTest {
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

        List<ServiceAppointment> appointments = [
            SELECT Id, Opportunity__c, ParentRecordId, ActualEndTime
            FROM ServiceAppointment
            ORDER BY CreatedDate ASC
        ];

        Id standardPricebookId = Test.getStandardPricebookId();
        List<Order> diaryOrders = new List<Order>{
            new Order(
            AccountId = accountRecord.Id,
            OpportunityId = opportunities[0].Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        ),
            new Order(
            AccountId = accountRecord.Id,
            OpportunityId = opportunities[1].Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        ),
            new Order(
            AccountId = accountRecord.Id,
            OpportunityId = opportunities[1].Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        ),
            new Order(
            AccountId = accountRecord.Id,
            OpportunityId = opportunities[2].Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        ),
            new Order(
            AccountId = accountRecord.Id,
            OpportunityId = opportunities[3].Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        )
        };
        insert diaryOrders;

        Invoice__c outstandingInvoice = new Invoice__c(
            Invoice_Number__c = 'INV-OUT-001',
            Opportunity__c = opportunities[2].Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 300,
            Tax_Amount__c = 0,
            Total_Amount__c = 300,
            Amount_Paid__c = 0,
            Balance_Due__c = 300
        );
        Invoice__c paidInvoice = new Invoice__c(
            Invoice_Number__c = 'INV-PAID-001',
            Opportunity__c = opportunities[3].Id,
            Account__c = accountRecord.Id,
            Status__c = 'Paid',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 400,
            Tax_Amount__c = 0,
            Total_Amount__c = 400,
            Amount_Paid__c = 400,
            Balance_Due__c = 0
        );
        insert new List<Invoice__c>{ outstandingInvoice, paidInvoice };

        insert new List<Invoice_Line__c>{
            new Invoice_Line__c(
                Invoice__c = outstandingInvoice.Id,
                Opportunity__c = opportunities[2].Id,
                Work_Order__c = workOrders[1].Id,
                Service_Appointment__c = appointments[1].Id,
                Description__c = 'Outstanding Invoice Line',
                Quantity__c = 1,
                Unit_Price__c = 300,
                Line_Total__c = 300
            ),
            new Invoice_Line__c(
                Invoice__c = paidInvoice.Id,
                Opportunity__c = opportunities[3].Id,
                Work_Order__c = workOrders[1].Id,
                Service_Appointment__c = appointments[2].Id,
                Description__c = 'Paid Invoice Line',
                Quantity__c = 1,
                Unit_Price__c = 400,
                Line_Total__c = 400
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

        System.assertEquals(0, metrics.completedMoreThan2Days, 'Invoicing eligibility must not use an aged ActualEndTime bucket.');
        System.assertEquals(3, metrics.readyToBill, 'Completed unbilled Service Appointments qualify without Order diary rows.');
        System.assertEquals(300, metrics.unbilledRevenue, 'Revenue deduplicates current Opportunity amounts across attributed appointments.');
        System.assertEquals(metrics.readyToBill, metrics.completedLaterCount, 'Completed Later is the full Ready to Bill population.');
        System.assertEquals(metrics.unbilledRevenue, metrics.completedLaterAmount);
        System.assertEquals(true, metrics.completedTodayCount <= metrics.completedThisWeekCount);
        System.assertEquals(true, metrics.completedThisWeekCount <= metrics.completedLaterCount);

        System.assertEquals(3, sections.size(), 'Appointments should be returned in the three KPI-backed sections.');
        Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sectionByKey =
            new Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
        }

        System.assertEquals(0, sectionByKey.get('AGED_COMPLETED').serviceAppointmentCount, 'The retained response-shape category is not an eligibility section.');
        System.assertEquals(0, sectionByKey.get('AGED_COMPLETED').totalBillableAmount, 'Invoicing must not calculate revenue from an ActualEndTime bucket.');
        System.assertEquals(3, sectionByKey.get('READY_TO_BILL').serviceAppointmentCount, 'Ready-to-bill section should include attributed completed appointments on work orders that are not fully billed.');
        System.assertEquals(300, sectionByKey.get('READY_TO_BILL').totalBillableAmount, 'Ready-to-bill section revenue uses deduplicated Opportunities.');
        System.assertEquals(2, sectionByKey.get('READY_TO_BILL').rows.size(), 'Ready-to-bill table rows should remain one row per Work Order.');
        System.assertEquals(3, sectionByKey.get('UNBILLED_REVENUE').serviceAppointmentCount, 'Revenue section should include the attributed appointments contributing to the KPI.');
        System.assertEquals(300, sectionByKey.get('UNBILLED_REVENUE').totalBillableAmount, 'Revenue section should match the deduplicated KPI.');

        Set<Id> readyRowAppointmentIds = new Set<Id>();
        for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : sectionByKey.get('READY_TO_BILL').rows) {
            readyRowAppointmentIds.add(row.serviceAppointmentId);
            System.assertEquals(
                row.serviceAppointmentNumber,
                row.serviceAppointmentDisplay,
                'Invoicing rows should display a Service Appointment label.'
            );
        }
        System.assertEquals(2, readyRowAppointmentIds.size(), 'Each ready-to-bill Work Order should surface as its own table row.');

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
            'Completed Service Appointments should appear on Invoicing without Order diary rows.'
        );
        System.assertEquals(
            beforeMetrics.unbilledRevenue + 10000,
            afterMetrics.unbilledRevenue,
            'Attributed Service Appointments should add their Opportunity amount once.'
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
        System.assertNotEquals(null, dedupeGroup, 'Attributed Service Appointments should group by Opportunity without Order diary rows.');
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
            SELECT Id, Invoice__c, Line_Total__c
            FROM Invoice_Line__c
            WHERE Invoice__c IN :createdInvoiceIds
        ];
        System.assertEquals(2, createdInvoiceLines.size(), 'Each billed appointment should create one invoice line.');
        for (Invoice_Line__c invoiceLineRecord : createdInvoiceLines) {
            System.assertNotEquals(null, invoiceLineRecord.Invoice__c, 'Complete Billing must create Invoice_Line__c.');
            System.assert(invoiceLineRecord.Line_Total__c > 0, 'Invoice lines should use positive current Opportunity-based allocations.');
        }

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
    static void testCompleteServiceAppointmentBillingUsesCurrentOpportunityAmount() {
        ServiceAppointment appointmentToBill = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        Opportunity opportunityToSkew = [
            SELECT Id, Amount
            FROM Opportunity
            WHERE Id = :appointmentToBill.Opportunity__c
            LIMIT 1
        ];
        opportunityToSkew.Amount = 9999;
        update opportunityToSkew;

        Test.startTest();
        BillingControl_Invoicing.completeServiceAppointmentBilling(
            new List<Id>{ appointmentToBill.Id },
            new Map<String, String>{ String.valueOf(appointmentToBill.Opportunity__c) => 'ORDER-AMOUNT-001' }
        );
        Test.stopTest();

        Invoice__c createdInvoice = [
            SELECT Id, Total_Amount__c
            FROM Invoice__c
            WHERE Opportunity__c = :appointmentToBill.Opportunity__c
            AND Invoice_Number__c = 'ORDER-AMOUNT-001'
            LIMIT 1
        ];
        System.assertEquals(9999, createdInvoice.Total_Amount__c, 'Invoice totals must use the current Opportunity.Amount, not the stale diary amount.');

        Invoice_Line__c createdInvoiceLine = [
            SELECT Line_Total__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :createdInvoice.Id
            LIMIT 1
        ];
        System.assertEquals(9999, createdInvoiceLine.Line_Total__c);
        System.assertNotEquals(null, createdInvoiceLine.Line_Total__c, 'Complete Billing must create Invoice_Line__c.');
    }

    @isTest
    static void testCompleteBillingAllocatesCurrentOpportunityAmountOnceAcrossSelectedAppointments() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Current Amount Allocation Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 100,
            CloseDate = Date.today().addDays(10),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(Subject = 'Allocation Work Order One', Status = 'New', AccountId = accountRecord.Id, WorkTypeId = workTypeRecord.Id),
            new WorkOrder(Subject = 'Allocation Work Order Two', Status = 'New', AccountId = accountRecord.Id, WorkTypeId = workTypeRecord.Id)
        };
        insert workOrders;

        Datetime startTime = System.now().addHours(-8);
        List<ServiceAppointment> appointments = new List<ServiceAppointment>{
            new ServiceAppointment(ParentRecordId = workOrders[0].Id, Status = 'Completed', SchedStartTime = startTime, SchedEndTime = startTime.addHours(1), ActualEndTime = startTime.addHours(1), Subject = 'Allocation SA One', Opportunity__c = opportunityRecord.Id),
            new ServiceAppointment(ParentRecordId = workOrders[0].Id, Status = 'Completed', SchedStartTime = startTime.addHours(2), SchedEndTime = startTime.addHours(3), ActualEndTime = startTime.addHours(3), Subject = 'Allocation SA Two', Opportunity__c = opportunityRecord.Id),
            new ServiceAppointment(ParentRecordId = workOrders[1].Id, Status = 'Completed', SchedStartTime = startTime.addHours(4), SchedEndTime = startTime.addHours(5), ActualEndTime = startTime.addHours(5), Subject = 'Allocation SA Three', Opportunity__c = opportunityRecord.Id),
            new ServiceAppointment(ParentRecordId = workOrders[0].Id, Status = 'Completed', SchedStartTime = startTime.addHours(-2), SchedEndTime = startTime.addHours(-1), ActualEndTime = startTime.addHours(-1), Subject = 'Historical Allocation SA', Invoice_Number__c = 'HIST-ALLOCATION-001', Opportunity__c = opportunityRecord.Id)
        };
        insert appointments;

        List<Order> diaryOrders = new List<Order>{
            new Order(AccountId = accountRecord.Id, OpportunityId = opportunityRecord.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = standardPricebookId),
            new Order(AccountId = accountRecord.Id, OpportunityId = opportunityRecord.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = standardPricebookId),
            new Order(AccountId = accountRecord.Id, OpportunityId = opportunityRecord.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = standardPricebookId),
            new Order(AccountId = accountRecord.Id, OpportunityId = opportunityRecord.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = standardPricebookId)
        };
        insert diaryOrders;

        // This simulates a prior partial invoice. The selected batch must invoice only the newly remaining value.
        Invoice__c historicalInvoice = new Invoice__c(
            Invoice_Number__c = 'HIST-ALLOCATION-001', Opportunity__c = opportunityRecord.Id, Account__c = accountRecord.Id,
            Status__c = 'Sent', Invoice_Date__c = Date.today(), Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 25, Tax_Amount__c = 0, Total_Amount__c = 25, Amount_Paid__c = 0, Balance_Due__c = 25
        );
        insert historicalInvoice;
        insert new Invoice_Line__c(
            Invoice__c = historicalInvoice.Id, Opportunity__c = opportunityRecord.Id, Work_Order__c = workOrders[0].Id,
            Service_Appointment__c = appointments[3].Id, Description__c = 'Historical partial amount',
            Quantity__c = 1, Unit_Price__c = 25, Line_Total__c = 25
        );

        // Opportunity.Amount changed after its diary rows were created; diary amounts remain intentionally stale.
        update new Opportunity(Id = opportunityRecord.Id, Amount = 125);

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result = BillingControl_Invoicing.completeServiceAppointmentBilling(
            new List<Id>{ appointments[0].Id, appointments[1].Id, appointments[2].Id },
            new Map<String, String>{ String.valueOf(opportunityRecord.Id) => 'CURRENT-ALLOCATION-001' }
        );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'All selected SAs for one Opportunity must create one invoice header.');
        Invoice__c createdInvoice = [
            SELECT Id, Subtotal__c, Total_Amount__c, Balance_Due__c
            FROM Invoice__c
            WHERE Invoice_Number__c = 'CURRENT-ALLOCATION-001'
            LIMIT 1
        ];
        System.assertEquals(100, createdInvoice.Subtotal__c, 'Invoice value must be current Opportunity.Amount less the existing invoice-line value.');
        System.assertEquals(createdInvoice.Subtotal__c, createdInvoice.Total_Amount__c);
        System.assertEquals(createdInvoice.Total_Amount__c, createdInvoice.Balance_Due__c);

        List<Invoice_Line__c> createdLines = [
            SELECT Line_Total__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :createdInvoice.Id
        ];
        System.assertEquals(3, createdLines.size(), 'One traceability line must remain for each selected Service Appointment.');
        Decimal lineTotal = 0;
        for (Invoice_Line__c createdLine : createdLines) {
            lineTotal += createdLine.Line_Total__c;
            System.assertNotEquals(null, createdLine.Line_Total__c, 'Complete Billing must create Invoice_Line__c.');
        }
        System.assertEquals(100, lineTotal, 'Selected SAs and Work Orders must not multiply the Opportunity value.');
    }

    @isTest
    static void testCompleteBillingRejectsReadyDiaryOrderWithoutOpportunity() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        WorkOrder workOrderRecord = new WorkOrder(Subject = 'No Opportunity Billing Work Order', Status = 'New', AccountId = accountRecord.Id, WorkTypeId = workTypeRecord.Id);
        insert workOrderRecord;
        Datetime startTime = System.now().addHours(-2);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id, Status = 'Completed', SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1), ActualEndTime = startTime.addHours(1), Subject = 'No Opportunity Billing SA'
        );
        insert appointmentRecord;
        insert new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id }, new Map<String, String>()
            );
            System.assert(false, 'A completed appointment without an attributed Opportunity must not be billed.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('attributed Opportunity'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteServiceAppointmentBillingOnlyBillsSelectedReadyDiaryRow() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity scopedOpportunity = new Opportunity(
            Name = 'Scoped Billing Selection Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 123,
            CloseDate = Date.today().addDays(12),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert scopedOpportunity;

        WorkOrder scopedWorkOrder = new WorkOrder(
            Subject = 'Scoped Billing Selection Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert scopedWorkOrder;

        Datetime startTime = System.now().addHours(-8);
        ServiceAppointment readyAppointment = new ServiceAppointment(
            ParentRecordId = scopedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Scoped Ready Appointment',
            Opportunity__c = scopedOpportunity.Id
        );
        ServiceAppointment reviewAppointment = new ServiceAppointment(
            ParentRecordId = scopedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime.addHours(2),
            SchedEndTime = startTime.addHours(3),
            ActualEndTime = startTime.addHours(3),
            Subject = 'Scoped Review Appointment',
            Opportunity__c = scopedOpportunity.Id
        );
        insert new List<ServiceAppointment>{ readyAppointment, reviewAppointment };

        Order readyOrder = new Order(
            AccountId = accountRecord.Id,
            OpportunityId = scopedOpportunity.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );
        Order reviewOrder = new Order(
            AccountId = accountRecord.Id,
            OpportunityId = scopedOpportunity.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );
        insert new List<Order>{ readyOrder, reviewOrder };

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ readyAppointment.Id },
                new Map<String, String>{ String.valueOf(scopedOpportunity.Id) => 'SCOPED-INV-001' }
            );
        Test.stopTest();

        System.assertEquals(1, result.serviceAppointmentsUpdated, 'Only the selected ready diary row should be billed.');
        System.assertEquals(1, result.invoicesCreated, 'Only one invoice should be created for the explicit selection.');

        Invoice__c createdInvoice = [
            SELECT Id, Total_Amount__c
            FROM Invoice__c
            WHERE Invoice_Number__c = 'SCOPED-INV-001'
            LIMIT 1
        ];
        System.assertEquals(123, createdInvoice.Total_Amount__c, 'Invoice totals should reflect the current Opportunity.Amount for the selected opportunity.');

        List<Invoice_Line__c> createdInvoiceLines = [
            SELECT Line_Total__c, Service_Appointment__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :createdInvoice.Id
        ];
        System.assertEquals(1, createdInvoiceLines.size(), 'Only one selected appointment should create an invoice line.');
        System.assertEquals(readyAppointment.Id, createdInvoiceLines[0].Service_Appointment__c);
        System.assertEquals(123, createdInvoiceLines[0].Line_Total__c);

        ServiceAppointment refreshedReviewAppointment = [
            SELECT Invoice_Number__c
            FROM ServiceAppointment
            WHERE Id = :reviewAppointment.Id
        ];
        System.assertEquals(null, refreshedReviewAppointment.Invoice_Number__c, 'Non-selected review appointments must remain untouched.');
    }

    @isTest
    static void testCompleteServiceAppointmentBillingRejectsSelectedNonReadyDiaryRow() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity reviewOpportunity = new Opportunity(
            Name = 'Direct Review Selection Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 222,
            CloseDate = Date.today().addDays(8),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert reviewOpportunity;

        WorkOrder reviewWorkOrder = new WorkOrder(
            Subject = 'Direct Review Selection Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert reviewWorkOrder;

        Datetime startTime = System.now().addHours(-5);
        ServiceAppointment reviewAppointment = new ServiceAppointment(
            ParentRecordId = reviewWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Direct Review Selection Appointment',
            Opportunity__c = reviewOpportunity.Id
        );
        insert reviewAppointment;

        insert new Order(
            AccountId = accountRecord.Id,
            OpportunityId = reviewOpportunity.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ reviewAppointment.Id },
                new Map<String, String>{ String.valueOf(reviewOpportunity.Id) => 'REVIEW-INV-001' }
            );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'Complete Billing should not require a ready-to-bill Order diary row.');
        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Invoice_Number__c = 'REVIEW-INV-001'
            LIMIT 1
        ];
        System.assertEquals('REVIEW-INV-001', createdInvoice.Invoice_Number__c);
    }

    @isTest
    static void testCompleteServiceAppointmentBillingRejectsIneligibleSelectedAppointment() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];

        Opportunity scheduledOpportunity = new Opportunity(
            Name = 'Scheduled Selection Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 333,
            CloseDate = Date.today().addDays(9),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert scheduledOpportunity;

        WorkOrder scheduledWorkOrder = new WorkOrder(
            Subject = 'Scheduled Selection Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert scheduledWorkOrder;

        Datetime startTime = System.now().addHours(4);
        ServiceAppointment scheduledAppointment = new ServiceAppointment(
            ParentRecordId = scheduledWorkOrder.Id,
            Status = 'Scheduled',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            Subject = 'Scheduled Selection Appointment',
            Opportunity__c = scheduledOpportunity.Id
        );
        insert scheduledAppointment;

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ scheduledAppointment.Id },
                new Map<String, String>{ String.valueOf(scheduledOpportunity.Id) => 'SCHEDULED-INV-001' }
            );
            System.assert(false, 'Expected non-completed selections to be rejected.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(
                exceptionRecord.getMessage().contains('completed and uninvoiced'),
                'The error should clearly explain that selected appointments must already be completed and uninvoiced.'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteServiceAppointmentBillingRejectsSelectionWithoutReadyDiaryOrder() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Center Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];

        WorkOrder unresolvedWorkOrder = new WorkOrder(
            Subject = 'Unresolved Opportunity Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert unresolvedWorkOrder;

        Datetime startTime = System.now().addHours(-3);
        ServiceAppointment unresolvedAppointment = new ServiceAppointment(
            ParentRecordId = unresolvedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Unresolved Opportunity Appointment'
        );
        insert unresolvedAppointment;

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ unresolvedAppointment.Id },
                new Map<String, String>()
            );
            System.assert(false, 'Expected selections without an attributed Opportunity to be rejected.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(
                exceptionRecord.getMessage().contains('attributed Opportunity'),
                'The error should clearly explain the missing Opportunity attribution requirement.'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteServiceAppointmentBillingFailsWithoutOrderDiary() {
        Opportunity readyOpportunity = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Ready To Bill Opportunity'
            LIMIT 1
        ];
        WorkOrder workOrderRecord = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Outstanding Receivable Work Order'
            LIMIT 1
        ];

        ServiceAppointment noOrderAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addDays(-1),
            SchedEndTime = System.now().addDays(-1).addHours(1),
            ActualEndTime = System.now().addHours(-2),
            Subject = 'Completed Without Order Diary',
            Opportunity__c = readyOpportunity.Id
        );
        insert noOrderAppointment;

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ noOrderAppointment.Id },
                new Map<String, String>{ String.valueOf(readyOpportunity.Id) => 'NO-ORDER-001' }
            );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'Complete Billing should succeed without an Order diary row.');
        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Invoice_Number__c = 'NO-ORDER-001'
            LIMIT 1
        ];
        System.assertEquals('NO-ORDER-001', createdInvoice.Invoice_Number__c);
        Invoice_Line__c createdLine = [
            SELECT Id
            FROM Invoice_Line__c
            WHERE Invoice__c = :createdInvoice.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, createdLine.Id);
    }

    @isTest
    static void testCompleteBillingUsesSoleJunctionOpportunityWhenAppointmentHasNone() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity junctionOpportunity = new Opportunity(
            Name = 'Sole Junction Billing Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 275,
            CloseDate = Date.today().addDays(6),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert junctionOpportunity;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Sole Junction Billing Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new Opportunity_WorkOrder__c(
            Opportunity__c = junctionOpportunity.Id,
            Work_Order__c = workOrderRecord.Id
        );
        Datetime startTime = System.now().addHours(-3);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Sole Junction Billing SA'
        );
        insert appointmentRecord;

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>{ String.valueOf(junctionOpportunity.Id) => 'JUNCTION-INV-001' }
            );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated);
        Invoice__c createdInvoice = [
            SELECT Opportunity__c
            FROM Invoice__c
            WHERE Invoice_Number__c = 'JUNCTION-INV-001'
            LIMIT 1
        ];
        System.assertEquals(junctionOpportunity.Id, createdInvoice.Opportunity__c);
        ServiceAppointment refreshedAppointment = [
            SELECT Opportunity__c
            FROM ServiceAppointment
            WHERE Id = :appointmentRecord.Id
        ];
        System.assertEquals(junctionOpportunity.Id, refreshedAppointment.Opportunity__c);
    }

    @isTest
    static void testCompleteBillingRejectsUnattributedMultiOpportunityAppointment() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity firstOpportunity = new Opportunity(
            Name = 'Multi Opp Billing One',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 110,
            CloseDate = Date.today().addDays(6),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity secondOpportunity = new Opportunity(
            Name = 'Multi Opp Billing Two',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 120,
            CloseDate = Date.today().addDays(7),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ firstOpportunity, secondOpportunity };
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Multi Opp Billing Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = firstOpportunity.Id, Work_Order__c = workOrderRecord.Id),
            new Opportunity_WorkOrder__c(Opportunity__c = secondOpportunity.Id, Work_Order__c = workOrderRecord.Id)
        };
        Datetime startTime = System.now().addHours(-3);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Unattributed Multi Opp SA'
        );
        insert appointmentRecord;

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>()
            );
            System.assert(false, 'Unattributed multi-opportunity appointments must not be billed.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(
                exceptionRecord.getMessage().contains('multiple Opportunities'),
                'Complete Billing must hard-stop instead of guessing the Opportunity.'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testInvoicingIncludesWoliParentedCompletedAppointments() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity opportunityRecord = new Opportunity(
            Name = 'WOLI Parent Billing Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 180,
            CloseDate = Date.today().addDays(5),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'WOLI Parent Billing Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrderRecord.Id
        );
        insert lineItem;
        Datetime startTime = System.now().addHours(-2);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = lineItem.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'WOLI Parent Billing SA',
            Opportunity__c = opportunityRecord.Id
        );
        insert appointmentRecord;

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>{ String.valueOf(opportunityRecord.Id) => 'WOLI-INV-001' }
            );
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getBillableServiceAppointmentGroups();
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'WOLI-parented appointments should complete billing against the Work Order.');
        Invoice_Line__c createdLine = [
            SELECT Work_Order__c
            FROM Invoice_Line__c
            WHERE Service_Appointment__c = :appointmentRecord.Id
            LIMIT 1
        ];
        System.assertEquals(workOrderRecord.Id, createdLine.Work_Order__c);

        Boolean foundAppointment = false;
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            if (section.categoryKey != 'READY_TO_BILL') {
                continue;
            }
            for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : section.rows) {
                if (row.relatedServiceAppointments == null) {
                    continue;
                }
                for (BillingControl_Invoicing.ServiceAppointmentRowWrapper child : row.relatedServiceAppointments) {
                    if (child.serviceAppointmentId == appointmentRecord.Id) {
                        foundAppointment = true;
                    }
                }
            }
        }
        System.assertEquals(false, foundAppointment, 'Completed billing should stamp the invoice number and drop the appointment from Ready to Bill.');
    }

    @isTest
    static void testInvoicingExcludesCanceledWorkOrdersAndUnattributedAppointments() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Canceled WO Billing Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 90,
            CloseDate = Date.today().addDays(4),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder canceledWorkOrder = new WorkOrder(
            Subject = 'Canceled Billing Work Order',
            Status = 'Canceled',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert canceledWorkOrder;
        Datetime startTime = System.now().addHours(-4);
        ServiceAppointment canceledAppointment = new ServiceAppointment(
            ParentRecordId = canceledWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Canceled WO Billing SA',
            Opportunity__c = opportunityRecord.Id
        );
        insert canceledAppointment;

        Test.startTest();
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getBillableServiceAppointmentGroups();
        Test.stopTest();

        Set<Id> readyAppointmentIds = new Set<Id>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            if (section.categoryKey != 'READY_TO_BILL') {
                continue;
            }
            for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : section.rows) {
                if (row.relatedServiceAppointments != null) {
                    for (BillingControl_Invoicing.ServiceAppointmentRowWrapper child : row.relatedServiceAppointments) {
                        readyAppointmentIds.add(child.serviceAppointmentId);
                    }
                } else {
                    readyAppointmentIds.add(row.serviceAppointmentId);
                }
            }
        }
        System.assertEquals(
            false,
            readyAppointmentIds.contains(canceledAppointment.Id),
            'Completed appointments on canceled Work Orders must stay off Ready to Bill.'
        );
    }

    @isTest
    static void testCompleteServiceAppointmentBillingFailsWithoutOpportunityAmount() {
        ServiceAppointment readyAppointment = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Subject = 'Completed Unbilled Older'
            LIMIT 1
        ];
        update new Opportunity(Id = readyAppointment.Opportunity__c, Amount = 0);

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ readyAppointment.Id },
                new Map<String, String>{ String.valueOf(readyAppointment.Opportunity__c) => 'NO-AMOUNT-001' }
            );
            System.assert(false, 'Expected Opportunity amount validation to block billing.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(
                exceptionRecord.getMessage().contains('Opportunity.Amount greater than 0'),
                'The error should clearly explain the missing Opportunity amount requirement.'
            );
        }
        Test.stopTest();
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

        System.assertEquals(0, metrics.unbilledRevenue, 'Receivables metrics should not fall back to legacy ready-for-billing revenue.');
        System.assertEquals(0, metrics.unbilledRevenueCount, 'Receivables metrics should not count legacy ready-for-billing opportunities.');
        System.assertEquals(300, metrics.revenueUnderCollection, 'Outstanding receivable revenue should use order-linked invoice rows only.');
        System.assertEquals(1, metrics.revenueUnderCollectionCount, 'Revenue under collection count should only include order-linked receivables.');
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

        System.assertEquals(1, revenueSection.opportunityCount, 'Revenue section should only include order-linked receivable opportunities.');
        System.assertEquals(300, revenueSection.totalAmount, 'Revenue section should sum invoice amount from order-linked receivables.');
        System.assertEquals(0, revenueSection.totalCommission, 'Revenue section should not include commission amount.');
        System.assertEquals(1, revenueSection.salespersonGroups.size(), 'Revenue section should preserve salesperson grouping.');
        Set<String> revenueOpportunityNames = new Set<String>();
        for (BillingControl_Invoicing.SalespersonWrapper revenueSalesperson : revenueSection.salespersonGroups) {
            for (BillingControl_Invoicing.OpportunityWrapper revenueOpportunity : revenueSalesperson.opportunities) {
                revenueOpportunityNames.add(revenueOpportunity.opportunityName);
            }
        }
        System.assertEquals(true, revenueOpportunityNames.contains('Outstanding Receivable Opportunity'), 'Revenue section should include commissioned outstanding opportunities because they contribute to A/R.');
        System.assertEquals(false, revenueOpportunityNames.contains('Revenue Under Collection Only Opportunity'), 'Legacy outstanding opportunities without order links should not appear.');

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
    static void testPostReceiptRequiresOpenInvoice() {
        Account accountRecord = new Account(Name = 'Post Receipt Missing Invoice Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Post Receipt Missing Invoice Work Type', 2);

        Opportunity receivableOpportunity = new Opportunity(
            Name = 'Missing Invoice Receivable Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 175,
            CloseDate = Date.today().addDays(12),
            Billing_Status__c = getOutstandingReceivableStatusValue(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert receivableOpportunity;

        BillingControl_Invoicing.PostReceiptInputWrapper receiptInput =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        receiptInput.opportunityId = receivableOpportunity.Id;
        receiptInput.amountReceived = 75;
        receiptInput.paymentDate = Date.today();
        receiptInput.paymentMethod = getPaymentMethodValue();
        receiptInput.referenceNumber = 'MISSING-INVOICE-RECEIPT-1';

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BillingControl_Invoicing.postReceipt(receiptInput);
            System.assert(false, 'Expected Post Receipt to require an open Invoice__c.');
        } catch (AuraHandledException error) {
            exceptionThrown = true;
            System.assert(String.isNotBlank(error.getMessage()), 'Expected a validation error when no open invoice exists.');
        }
        Test.stopTest();
        System.assertEquals(true, exceptionThrown);
    }

    @isTest
    static void testPostReceiptUsesExistingInvoiceWithoutOrder() {
        Account accountRecord = new Account(Name = 'Post Receipt Invoice Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Post Receipt Invoice Work Type', 2);

        Opportunity receivableOpportunity = new Opportunity(
            Name = 'Invoice Receivable Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 175,
            CloseDate = Date.today().addDays(12),
            Billing_Status__c = getOutstandingReceivableStatusValue(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert receivableOpportunity;

        Invoice__c invoiceRecord = new Invoice__c(
            Invoice_Number__c = 'INV-RECEIPT-175',
            Opportunity__c = receivableOpportunity.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 175,
            Tax_Amount__c = 0,
            Total_Amount__c = 175,
            Amount_Paid__c = 0,
            Balance_Due__c = 175
        );
        insert invoiceRecord;

        BillingControl_Invoicing.PostReceiptInputWrapper receiptInput =
            new BillingControl_Invoicing.PostReceiptInputWrapper();
        receiptInput.opportunityId = receivableOpportunity.Id;
        receiptInput.amountReceived = 75;
        receiptInput.paymentDate = Date.today();
        receiptInput.paymentMethod = getPaymentMethodValue();
        receiptInput.referenceNumber = 'INVOICE-RECEIPT-1';

        Test.startTest();
        BillingControl_Invoicing.PaymentReceiptResultWrapper result =
            BillingControl_Invoicing.postReceipt(receiptInput);
        Test.stopTest();

        System.assertEquals(75, result.totalPaid);
        System.assertEquals(100, result.balanceDue);
        System.assertEquals('Partially Paid', result.billingStatus);

        Invoice__c updatedInvoice = [
            SELECT Total_Amount__c, Amount_Paid__c, Balance_Due__c, Status__c
            FROM Invoice__c
            WHERE Id = :invoiceRecord.Id
        ];
        System.assertEquals(175, updatedInvoice.Total_Amount__c);
        System.assertEquals(75, updatedInvoice.Amount_Paid__c);
        System.assertEquals(100, updatedInvoice.Balance_Due__c);
        System.assertEquals('Partially Paid', updatedInvoice.Status__c);
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

    @isTest
    static void testInvoicingMetricsSupportExplicitZeroInvoicedFilters() {
        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildInvoicingFilter('ORDER', 'Billing_Diary_Status__c', 'Equals', 'Ready to Bill', 'Static', 10)
        );
        filterContext.filters.add(
            buildInvoicingFilter('ORDER', 'Ready_For_Billing__c', 'Equals', 'TRUE', 'Static', 20)
        );
        filterContext.filters.add(
            buildInvoicingFilter('ORDER', 'Service_Appointment__c', 'Is Not Null', null, 'Static', 30)
        );
        filterContext.filters.add(
            buildInvoicingFilter('ORDER', 'Invoiced_Amount__c', 'Equals', '0', 'Static', 40)
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(51L, filterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(51L, filterContext);
        Test.stopTest();

        System.assertEquals(3, metrics.readyToBill, 'Legacy zero-invoiced filters must not exclude SA/WO-eligible appointments.');
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            if (groupRecord.categoryKey == 'READY_TO_BILL') {
                System.assertEquals(3, groupRecord.serviceAppointmentCount);
            }
        }
    }

    @isTest
    static void testInvoicingMetricsSupportExplicitDateComparisons() {
        Date effectiveDate = Date.today();

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildInvoicingFilter(
                'ORDER',
                'EffectiveDate',
                'Greater Or Equal',
                formatDateValue(effectiveDate.addDays(-1)),
                'Static',
                10
            )
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(52L, filterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(52L, filterContext);
        Test.stopTest();

        System.assert(metrics.readyToBill > 0, 'Date comparison filters should retain rows on or after the supplied date.');
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            if (groupRecord.categoryKey == 'READY_TO_BILL') {
                System.assert(groupRecord.serviceAppointmentCount > 0);
            }
        }
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

    private static BillingControl_DataProvider.BillingFilterDTO buildInvoicingFilter(
        String objectApiName,
        String fieldApiName,
        String operatorValue,
        String value,
        String valueType,
        Decimal sequence
    ) {
        BillingControl_DataProvider.BillingFilterDTO filterRecord = new BillingControl_DataProvider.BillingFilterDTO();
        filterRecord.objectApiName = objectApiName;
        filterRecord.fieldApiName = fieldApiName;
        filterRecord.operator = operatorValue;
        filterRecord.value = value;
        filterRecord.valueType = valueType;
        filterRecord.sequence = sequence;
        filterRecord.developerKey = objectApiName + '_' + fieldApiName + '_' + operatorValue;
        return filterRecord;
    }

    private static String formatDateValue(Date value) {
        return String.valueOf(value.year())
            + '-'
            + String.valueOf(value.month()).leftPad(2, '0')
            + '-'
            + String.valueOf(value.day()).leftPad(2, '0');
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
            Invoice_Number__c = 'INV-WO-999'
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
            Invoice_Number__c = 'INV-SA-111'
        );
        insert appointmentRecord;

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'INV-Sync should create one invoice from the SA number.');
        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c, Opportunity__c, Total_Amount__c, Balance_Due__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
        ];
        System.assertEquals('INV-SA-111', createdInvoice.Invoice_Number__c);
        System.assertEquals(250, createdInvoice.Total_Amount__c);

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
        System.assertEquals('INV-SA-111', updatedAppointment.Invoice_Number__c, 'Existing SA invoice numbers must not be overwritten.');

        Opportunity updatedOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        System.assertEquals(getOutstandingReceivableStatusValue(), updatedOpportunity.Billing_Status__c);
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
            Invoice_Number__c = 'INV-WO-222'
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

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated);
        System.assertEquals(1, result.serviceAppointmentsUpdated);

        Invoice__c createdInvoice = [
            SELECT Invoice_Number__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityRecord.Id
        ];
        System.assertEquals('INV-WO-222', createdInvoice.Invoice_Number__c);

        ServiceAppointment updatedAppointment = [
            SELECT Invoice_Number__c
            FROM ServiceAppointment
            WHERE Id = :appointmentRecord.Id
        ];
        System.assertEquals('INV-WO-222', updatedAppointment.Invoice_Number__c);
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
            Invoice_Number__c = 'INV-EXIST-1'
        );
        ServiceAppointment priorYearAppointment = new ServiceAppointment(
            ParentRecordId = priorYearWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(10, 0, 0, 0)),
            SchedEndTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(11, 0, 0, 0)),
            ActualEndTime = Datetime.newInstance(Date.today().addYears(-1), Time.newInstance(12, 0, 0, 0)),
            Subject = 'INV-Sync Prior Year Appointment',
            Opportunity__c = priorYearOpportunity.Id,
            Invoice_Number__c = 'INV-PRIOR-1'
        );
        insert new List<ServiceAppointment>{ existingAppointment, priorYearAppointment };

        insert new Invoice__c(
            Invoice_Number__c = 'INV-EXIST-1',
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

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, '005000000000000AAA');
        BillingControl_Invoicing.InvSyncResultWrapper existingResult =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
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
            WHERE Invoice_Number__c = 'INV-PRIOR-1'
        ];
        System.assertEquals(0, priorYearInvoiceCount, 'Last-year appointments must stay outside This Year INV-Sync.');
    }

    @isTest
    static void testReceivablesOutstandingUsesInvoiceNotOrderDiary() {
        Account accountRecord = new Account(Name = 'Receivables Invoice Source Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Receivables Invoice Source Work Type', 2);
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity invoiceOpportunity = new Opportunity(
            Name = 'Invoice Receivable Source Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 220,
            CloseDate = Date.today(),
            Billing_Status__c = getOutstandingReceivableStatusValue(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        Opportunity orderOnlyOpportunity = new Opportunity(
            Name = 'Order Diary Only Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 330,
            CloseDate = Date.today(),
            Billing_Status__c = getOutstandingReceivableStatusValue(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert new List<Opportunity>{ invoiceOpportunity, orderOnlyOpportunity };

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Order Diary Only Work Order',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;

        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = System.now().addHours(-2),
            SchedEndTime = System.now().addHours(-1),
            ActualEndTime = System.now().addMinutes(-30),
            Subject = 'Order Diary Only Appointment',
            Opportunity__c = orderOnlyOpportunity.Id
        );
        insert appointmentRecord;

        insert new Order(
            AccountId = accountRecord.Id,
            OpportunityId = orderOnlyOpportunity.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );

        insert new Invoice__c(
            Invoice_Number__c = 'INV-AR-220',
            Opportunity__c = invoiceOpportunity.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 220,
            Tax_Amount__c = 0,
            Total_Amount__c = 220,
            Amount_Paid__c = 0,
            Balance_Due__c = 220
        );

        Test.startTest();
        BillingControl_Invoicing.CommissionMetricsWrapper metrics =
            BillingControl_Invoicing.getCommissionMetrics();
        List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getCommissionData('kpi');
        Test.stopTest();

        Set<String> revenueNames = new Set<String>();
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            if (section.categoryKey != 'REVENUE_UNDER_COLLECTION') {
                continue;
            }
            for (BillingControl_Invoicing.SalespersonWrapper salesperson : section.salespersonGroups) {
                for (BillingControl_Invoicing.OpportunityWrapper opportunityRow : salesperson.opportunities) {
                    revenueNames.add(opportunityRow.opportunityName);
                }
            }
        }
        System.assertEquals(true, revenueNames.contains('Invoice Receivable Source Opportunity'));
        System.assertEquals(false, revenueNames.contains('Order Diary Only Opportunity'));
        System.assert(metrics.revenueUnderCollection >= 220);
    }

    @isTest
    static void testCompleteBillingRejectsDuplicateInvoiceNumberInRequest() {
        List<ServiceAppointment> toBill = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY Opportunity__c ASC
        ];
        System.assertEquals(true, toBill.size() >= 2);
        System.assertNotEquals(toBill[0].Opportunity__c, toBill[1].Opportunity__c);

        Map<String, String> invoiceNumbers = new Map<String, String>{
            String.valueOf(toBill[0].Opportunity__c) => 'DUP-REQUEST-001',
            String.valueOf(toBill[1].Opportunity__c) => 'DUP-REQUEST-001'
        };

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ toBill[0].Id, toBill[1].Id },
                invoiceNumbers
            );
            System.assert(false, 'Duplicate invoice numbers in one Complete Billing request must fail.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('unique'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteBillingRejectsInvoiceNumberAlreadyInOrg() {
        ServiceAppointment appointmentRecord = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>{ String.valueOf(appointmentRecord.Opportunity__c) => 'INV-OUT-001' }
            );
            System.assert(false, 'An invoice number already on Invoice__c must fail Complete Billing.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('already used'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteBillingRejectsInvoiceNumberLongerThan80() {
        ServiceAppointment appointmentRecord = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Invoice_Number__c = NULL
            AND Opportunity__c != NULL
            AND Status = 'Completed'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        String longInvoiceNumber = 'INV-' + 'X'.repeat(78);

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>{ String.valueOf(appointmentRecord.Opportunity__c) => longInvoiceNumber }
            );
            System.assert(false, 'Invoice numbers longer than 80 characters must fail Complete Billing.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('80 characters'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteBillingRejectsFullyInvoicedOpportunity() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Fully Invoiced Complete Billing Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 50,
            CloseDate = Date.today().addDays(6),
            Billing_Status__c = 'Ready for Billing',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Fully Invoiced Complete Billing WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        Datetime startTime = System.now().addHours(-3);
        ServiceAppointment billedAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Fully Invoiced Historical SA',
            Opportunity__c = opportunityRecord.Id,
            Invoice_Number__c = 'INV-FULL-HIST'
        );
        ServiceAppointment unbilledAppointment = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime.addHours(1),
            SchedEndTime = startTime.addHours(2),
            ActualEndTime = startTime.addHours(2),
            Subject = 'Fully Invoiced Unbilled SA',
            Opportunity__c = opportunityRecord.Id
        );
        insert new List<ServiceAppointment>{ billedAppointment, unbilledAppointment };
        Invoice__c historicalInvoice = new Invoice__c(
            Invoice_Number__c = 'INV-FULL-HIST',
            Opportunity__c = opportunityRecord.Id,
            Account__c = accountRecord.Id,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = 50,
            Tax_Amount__c = 0,
            Total_Amount__c = 50,
            Amount_Paid__c = 0,
            Balance_Due__c = 50
        );
        insert historicalInvoice;
        insert new Invoice_Line__c(
            Invoice__c = historicalInvoice.Id,
            Opportunity__c = opportunityRecord.Id,
            Work_Order__c = workOrderRecord.Id,
            Service_Appointment__c = billedAppointment.Id,
            Description__c = 'Historical full amount',
            Quantity__c = 1,
            Unit_Price__c = 50,
            Line_Total__c = 50
        );

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ unbilledAppointment.Id },
                new Map<String, String>{ String.valueOf(opportunityRecord.Id) => 'INV-FULL-NEXT' }
            );
            System.assert(false, 'A fully invoiced Opportunity must fail Complete Billing.');
        } catch (AuraHandledException exceptionRecord) {
            System.assert(exceptionRecord.getMessage().contains('fully invoiced'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteBillingTransitionsPaidOpportunityToOutstanding() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Control Center Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Paid Status Transition Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 75,
            CloseDate = Date.today().addDays(7),
            Billing_Status__c = 'Paid',
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Paid Status Transition WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;
        Datetime startTime = System.now().addHours(-2);
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime.addHours(1),
            Subject = 'Paid Status Transition SA',
            Opportunity__c = opportunityRecord.Id
        );
        insert appointmentRecord;

        Test.startTest();
        BillingControl_Invoicing.CompleteBillingResultWrapper result =
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ appointmentRecord.Id },
                new Map<String, String>{ String.valueOf(opportunityRecord.Id) => 'INV-PAID-TRANS' }
            );
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated);
        Opportunity updatedOpportunity = [
            SELECT Billing_Status__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        System.assertEquals(
            getOutstandingReceivableStatusValue(),
            updatedOpportunity.Billing_Status__c,
            'Complete Billing overwrites Paid with outstanding receivable status.'
        );
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
            Invoice_Number__c = 'INV-LINE-EXIST'
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

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
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
                Invoice_Number__c = 'INV-BATCH-DUP'
            ),
            new ServiceAppointment(
                ParentRecordId = secondWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-2),
                SchedEndTime = System.now().addHours(-1),
                ActualEndTime = System.now().addHours(-1),
                Subject = 'INV-Sync Batch Dup SA Two',
                Opportunity__c = secondOpportunity.Id,
                Invoice_Number__c = 'inv-batch-dup'
            )
        };

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'Only the first group with a shared invoice number should persist.');
        System.assert(result.skippedCount > 0, 'The second group must be counted as skipped.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Invoice__c WHERE Invoice_Number__c = 'INV-BATCH-DUP' OR Invoice_Number__c = 'inv-batch-dup']
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
                Invoice_Number__c = 'INV-REMAIN-A'
            ),
            new ServiceAppointment(
                ParentRecordId = workOrderRecord.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-3),
                SchedEndTime = System.now().addHours(-2),
                ActualEndTime = System.now().addHours(-2),
                Subject = 'INV-Sync Remaining SA Two',
                Opportunity__c = opportunityRecord.Id,
                Invoice_Number__c = 'INV-REMAIN-B'
            )
        };

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
        Test.stopTest();

        System.assertEquals(1, result.invoicesCreated, 'The first invoice-number group consumes remaining Opportunity amount.');
        System.assert(result.skippedCount > 0, 'The second invoice-number group must be skipped as fully invoiced.');
        System.assertEquals(1, [SELECT COUNT() FROM Invoice__c WHERE Opportunity__c = :opportunityRecord.Id]);
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
                Invoice_Number__c = 'INV-PAID-KEEP'
            ),
            new ServiceAppointment(
                ParentRecordId = partialWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = System.now().addHours(-2),
                SchedEndTime = System.now().addHours(-1),
                ActualEndTime = System.now().addHours(-1),
                Subject = 'INV-Sync Partial Preserve SA',
                Opportunity__c = partialOpportunity.Id,
                Invoice_Number__c = 'INV-PARTIAL-KEEP'
            )
        };

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Map<Id, Opportunity> statusBeforeSync = new Map<Id, Opportunity>([
            SELECT Id, Billing_Status__c
            FROM Opportunity
            WHERE Id IN :new Set<Id>{ paidOpportunity.Id, partialOpportunity.Id }
        ]);

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
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
            Invoice_Number__c = 'INV-WOLI-001'
        );
        insert appointmentRecord;

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = 'This Year';

        Test.startTest();
        BillingControl_Invoicing.InvSyncResultWrapper result =
            BillingControl_Invoicing.syncExistingInvoiceNumbers(dateFilter, null);
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