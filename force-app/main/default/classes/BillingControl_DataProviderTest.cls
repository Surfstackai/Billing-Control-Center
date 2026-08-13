@IsTest
private class BillingControl_DataProviderTest {
    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'Billing Control Provider Test Account');
        insert accountRecord;

        WorkType workTypeRecord = TestDataFactory.createWorkType('Provider Install', 2);
        Id standardPricebookId = Test.getStandardPricebookId();

        List<Opportunity> opportunities = new List<Opportunity>{
            buildOpportunity(accountRecord.Id, workTypeRecord.Id, 'Provider Draft Opportunity', 100, Date.today()),
            buildOpportunity(accountRecord.Id, workTypeRecord.Id, 'Provider Ready Opportunity', 200, Date.today().addDays(1)),
            buildOpportunity(accountRecord.Id, workTypeRecord.Id, 'Provider Receivable Opportunity', 300, Date.today().addDays(2)),
            buildOpportunity(accountRecord.Id, workTypeRecord.Id, 'Provider Paid Opportunity', 400, Date.today().addDays(3)),
            buildOpportunity(accountRecord.Id, workTypeRecord.Id, 'Provider Unscheduled Opportunity', 150, Date.today().addDays(4))
        };
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            workOrders.add(new WorkOrder(
                Subject = 'Provider WO ' + indexValue,
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ));
        }
        insert workOrders;

        List<ServiceAppointment> appointments = new List<ServiceAppointment>();
        for (Integer indexValue = 0; indexValue < 4; indexValue++) {
            Datetime startTime = System.now().addDays(-indexValue - 1);
            appointments.add(new ServiceAppointment(
                ParentRecordId = workOrders[indexValue].Id,
                Status = 'Completed',
                SchedStartTime = startTime,
                SchedEndTime = startTime.addHours(1),
                ActualEndTime = startTime,
                Subject = 'Provider SA ' + indexValue,
                Opportunity__c = opportunities[indexValue].Id
            ));
        }
        appointments.add(new ServiceAppointment(
            ParentRecordId = workOrders[4].Id,
            Status = 'None',
            Subject = 'Provider Unscheduled SA',
            Opportunity__c = opportunities[4].Id
        ));
        insert appointments;

        List<Opportunity_WorkOrder__c> junctions = new List<Opportunity_WorkOrder__c>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            junctions.add(new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[indexValue].Id,
                Work_Order__c = workOrders[indexValue].Id
            ));
        }
        insert junctions;
        Set<Id> setupWorkOrderIds = new Set<Id>();
        for (WorkOrder workOrderRecord : workOrders) {
            setupWorkOrderIds.add(workOrderRecord.Id);
        }
        WorkOrderLedgerService.backfillWorkOrders(setupWorkOrderIds);

        List<Order> orders = new List<Order>{
            buildOrder(accountRecord.Id, opportunities[0].Id, standardPricebookId, workOrders[0].Id, appointments[0].Id, 'Draft', false, 100, 0, 0, Date.today()),
            buildOrder(accountRecord.Id, opportunities[1].Id, standardPricebookId, workOrders[1].Id, appointments[1].Id, 'Ready to Bill', true, 200, 0, 0, Date.today().addDays(1)),
            buildOrder(accountRecord.Id, opportunities[2].Id, standardPricebookId, workOrders[2].Id, appointments[2].Id, 'Ready to Bill', false, 300, 300, 0, Date.today().addDays(2)),
            buildOrder(accountRecord.Id, opportunities[3].Id, standardPricebookId, workOrders[3].Id, appointments[3].Id, 'Paid', false, 400, 400, 400, Date.today().addDays(3)),
            buildOrder(accountRecord.Id, opportunities[4].Id, standardPricebookId, workOrders[4].Id, appointments[4].Id, 'Draft', false, 150, 0, 0, Date.today().addDays(4))
        };
        insert orders;

        insertRuntimeConfig();

        Invoice__c receivableInvoice = buildInvoice(accountRecord.Id, opportunities[2].Id, 300, 'INV-PROVIDER-REC');
        Invoice__c paidInvoice = buildInvoice(accountRecord.Id, opportunities[3].Id, 400, 'INV-PROVIDER-PAID');
        insert new List<Invoice__c>{ receivableInvoice, paidInvoice };

        insert new List<Invoice_Line__c>{
            new Invoice_Line__c(
                Invoice__c = receivableInvoice.Id,
                Opportunity__c = opportunities[2].Id,
                Work_Order__c = workOrders[2].Id,
                Service_Appointment__c = appointments[2].Id,
                Billing_Order__c = orders[2].Id,
                Description__c = 'Provider Receivable Line',
                Quantity__c = 1,
                Unit_Price__c = 300,
                Line_Total__c = 300
            ),
            new Invoice_Line__c(
                Invoice__c = paidInvoice.Id,
                Opportunity__c = opportunities[3].Id,
                Work_Order__c = workOrders[3].Id,
                Service_Appointment__c = appointments[3].Id,
                Billing_Order__c = orders[3].Id,
                Description__c = 'Provider Paid Line',
                Quantity__c = 1,
                Unit_Price__c = 400,
                Line_Total__c = 400
            )
        };

        insert new List<Commission__c>{
            new Commission__c(
                Opportunity__c = opportunities[2].Id,
                Billing_Order__c = orders[2].Id,
                Sales_Person__c = UserInfo.getUserId(),
                Commission_Rate__c = 10,
                Commission_Paid__c = 0,
                Unique_Key__c = 'provider-earned-' + String.valueOf(orders[2].Id).right(6)
            ),
            new Commission__c(
                Opportunity__c = opportunities[3].Id,
                Billing_Order__c = orders[3].Id,
                Sales_Person__c = UserInfo.getUserId(),
                Commission_Rate__c = 10,
                Commission_Paid__c = 5,
                Unique_Key__c = 'provider-payable-' + String.valueOf(orders[3].Id).right(6)
            )
        };
    }

    @IsTest
    static void activeDatasetsDispatchWithoutDml() {
        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(1L);
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(1L);
        BillingControl_DataProvider.ReceivablesRuntimeDataDTO receivablesData =
            BillingControl_DataProvider.getReceivablesRuntimeData();
        BillingControl_Orders.KpiWrapper kpiData = BillingControl_Orders.getOrdersKpiData();
        List<BillingControl_Orders.OrderRowWrapper> emptyOrders = BillingControl_Orders.getOrders();
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(dmlBefore, dmlAfter);
        System.assertEquals(2, ordersData.filterContext.filters.size());
        System.assertEquals(4, invoicingData.filterContext.filters.size());
        System.assertEquals(0, emptyOrders.size());
        System.assertEquals(1, kpiData.unscheduledCount);
        System.assertEquals(1, findOrdersSection(ordersData.bucketSections, 'UNSCHEDULED').rows.size());
        System.assert(
            kpiData.completedThisWeekCount >= 1,
            'Completed appointments with active diary statuses appear in Completed This Week.'
        );
        System.assert(
            kpiData.completedThisMonthCount >= kpiData.completedThisWeekCount,
            'Completed This Month includes Completed This Week when both fall in the current month.'
        );
        System.assertEquals(0, kpiData.noOpportunityCount);
        System.assertEquals(4, invoicingData.metrics.readyToBill, 'Eligibility is driven by related SA/WO values, not legacy diary flags.');
        System.assertEquals(1, receivablesData.metrics.revenueUnderCollectionCount);
    }

    @IsTest
    static void missingFiltersDoNotBreakRetrieval() {
        List<Billing_Center_Filter_Config__c> invoicingFilters = [
            SELECT Id, Is_Active__c
            FROM Billing_Center_Filter_Config__c
            WHERE Dataset_Config__r.Developer_Key__c = 'INVOICING_SERVICE_APPOINTMENTS'
        ];
        for (Billing_Center_Filter_Config__c filterRecord : invoicingFilters) {
            filterRecord.Is_Active__c = false;
        }
        update invoicingFilters;

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(11L);
        Test.stopTest();

        System.assertEquals(0, invoicingData.filterContext.filters.size());
        System.assertEquals(4, invoicingData.metrics.readyToBill, 'Disabling legacy configuration must not change SA/WO eligibility.');
    }

    @IsTest
    static void missingDatasetReturnsEmptyWithWarnings() {
        Billing_Center_Dataset_Config__c ordersDataset = [
            SELECT Id, Is_Active__c
            FROM Billing_Center_Dataset_Config__c
            WHERE Developer_Key__c = 'ORDERS_WORK_ORDERS'
            LIMIT 1
        ];
        ordersDataset.Is_Active__c = false;
        update ordersDataset;

        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(2L);
        Test.stopTest();

        System.assertEquals(0, countOrderRows(ordersData.bucketSections));
        System.assert(String.join(ordersData.warnings, ' ').contains('Work Order Ledger dataset missing or invalid.'));
        System.assert(String.join(ordersData.warnings, ' ').contains('Legacy fallback disabled.'));
    }

    @IsTest
    static void unsupportedHandlerReturnsEmptyWithWarning() {
        Billing_Center_Dataset_Config__c invoicingDataset = [
            SELECT Id, Apex_Handler_Key__c
            FROM Billing_Center_Dataset_Config__c
            WHERE Developer_Key__c = 'INVOICING_SERVICE_APPOINTMENTS'
            LIMIT 1
        ];
        invoicingDataset.Apex_Handler_Key__c = 'Unsupported.Handler';
        update invoicingDataset;

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(3L);
        Test.stopTest();

        System.assertEquals(0, invoicingData.metrics.readyToBill);
        System.assert(String.join(invoicingData.warnings, ' ').contains('Unsupported.Handler'));
        System.assert(String.join(invoicingData.warnings, ' ').contains('Legacy fallback disabled.'));
    }

    @IsTest
    static void unsupportedOperatorAndInvalidFieldGenerateWarnings() {
        Id ordersTabId = [SELECT Id FROM Billing_Center_Tab_Config__c WHERE Developer_Key__c = 'ORDERS' LIMIT 1].Id;
        Id receivablesTabId = [SELECT Id FROM Billing_Center_Tab_Config__c WHERE Developer_Key__c = 'RECEIVABLES' LIMIT 1].Id;
        Id ordersDatasetId = [SELECT Id FROM Billing_Center_Dataset_Config__c WHERE Developer_Key__c = 'ORDERS_WORK_ORDERS' LIMIT 1].Id;
        Id invoicesDatasetId = [SELECT Id FROM Billing_Center_Dataset_Config__c WHERE Developer_Key__c = 'RECEIVABLES_INVOICES' LIMIT 1].Id;

        insert new List<Billing_Center_Filter_Config__c>{
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = ordersTabId,
                Dataset_Config__c = ordersDatasetId,
                Developer_Key__c = 'ORDERS_BAD_OPERATOR',
                Label__c = 'Bad Operator',
                Is_Active__c = true,
                Sequence__c = 99,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Billing_Diary_Status__c',
                Operator__c = 'Contains',
                Value__c = 'Draft',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = receivablesTabId,
                Dataset_Config__c = invoicesDatasetId,
                Developer_Key__c = 'RECEIVABLES_INVALID_FIELD',
                Label__c = 'Invalid Field',
                Is_Active__c = true,
                Sequence__c = 50,
                Object_API_Name__c = 'Invoice__c',
                Field_API_Name__c = 'Status__c',
                Operator__c = 'Equals',
                Value__c = 'Draft',
                Value_Type__c = 'Static'
            )
        };

        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(12L);
        BillingControl_DataProvider.ReceivablesRuntimeDataDTO receivablesData =
            BillingControl_DataProvider.getReceivablesRuntimeData();
        Test.stopTest();

        System.assert(String.join(ordersData.warnings, ' ').contains('unsupported operator'));
        System.assert(String.join(receivablesData.warnings, ' ').contains('unsupported field'));
    }

    @IsTest
    static void providerDateAndReceivableFiltersApplyToRuntimeData() {
        Id receivablesTabId = [SELECT Id FROM Billing_Center_Tab_Config__c WHERE Developer_Key__c = 'RECEIVABLES' LIMIT 1].Id;
        Id invoicesDatasetId = [SELECT Id FROM Billing_Center_Dataset_Config__c WHERE Developer_Key__c = 'RECEIVABLES_INVOICES' LIMIT 1].Id;
        Id commissionsDatasetId = [SELECT Id FROM Billing_Center_Dataset_Config__c WHERE Developer_Key__c = 'RECEIVABLES_COMMISSIONS' LIMIT 1].Id;

        insert new List<Billing_Center_Filter_Config__c>{
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = receivablesTabId,
                Dataset_Config__c = invoicesDatasetId,
                Developer_Key__c = 'RECEIVABLES_EFFECTIVE_LIMIT',
                Label__c = 'Effective Date Limit',
                Is_Active__c = true,
                Sequence__c = 10,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'EffectiveDate',
                Operator__c = 'Less Or Equal',
                Value__c = String.valueOf(Date.today().addDays(1)),
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = receivablesTabId,
                Dataset_Config__c = commissionsDatasetId,
                Developer_Key__c = 'RECEIVABLES_COMMISSION_PAID_GT_ZERO',
                Label__c = 'Commission Paid Above Zero',
                Is_Active__c = true,
                Sequence__c = 10,
                Object_API_Name__c = 'Commission__c',
                Field_API_Name__c = 'Commission_Paid__c',
                Operator__c = 'Greater Than',
                Value__c = '0',
                Value_Type__c = 'Static'
            )
        };

        BillingControl_DataProvider.BillingDateFilterDTO ordersDateFilter =
            buildDateFilter('Custom', formatDateValue(Date.today()), formatDateValue(Date.today()));
        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(31L, ordersDateFilter);
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(31L);
        BillingControl_DataProvider.ReceivablesRuntimeDataDTO receivablesData =
            BillingControl_DataProvider.getReceivablesRuntimeData(31L, null);
        Test.stopTest();

        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : ordersData.bucketSections) {
            for (BillingControl_Orders.WorkOrderRowWrapper row : sectionRecord.rows) {
                System.assertEquals(Date.today(), row.createdDate == null ? null : row.createdDate.date());
            }
        }
        System.assertEquals(4, invoicingData.metrics.readyToBill, 'Invoicing does not apply the page date filter.');
        System.assertEquals(0, receivablesData.metrics.revenueUnderCollectionCount);
        System.assertEquals(1, receivablesData.metrics.commissionPayableCount);
    }

    @IsTest
    static void invalidCustomDateFilterWarnsSafely() {
        BillingControl_DataProvider.BillingDateFilterDTO invalidDateFilter =
            buildDateFilter('Custom', String.valueOf(Date.today().addDays(5)), String.valueOf(Date.today()));

        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(32L, invalidDateFilter);
        Test.stopTest();

        System.assert(String.join(ordersData.warnings, ' ').contains('start date must be on or before end date'));
    }

    @IsTest
    static void lastYearDateFilterIsSupported() {
        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO lastYearData =
            BillingControl_DataProvider.getOrdersRuntimeData(33L, buildDateFilter('Last Year', null, null));
        Test.stopTest();

        System.assertEquals(
            false,
            String.join(lastYearData.warnings, ' ').contains('Unsupported date filter key')
        );
    }

    @IsTest
    static void directOrdersFilterOverloadsApplySupportedFilters() {
        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'ORDERS';
        filterContext.datasetKey = 'ORDERS_WORK_ORDERS';
        filterContext.filters.add(buildFilter('STATUS_EQUALS', 'Order', 'Billing_Diary_Status__c', 'Equals', 'Draft', 'Static', 10));
        filterContext.filters.add(buildFilter('CREATED_PRESENT', 'Order', 'CreatedDate', 'Is Not Null', null, 'Static', 20));

        Test.startTest();
        List<BillingControl_Orders.BucketSectionWrapper> sections =
            BillingControl_Orders.getBucketWorkOrders(21L, filterContext);
        BillingControl_Orders.KpiWrapper filteredKpis = BillingControl_Orders.getKpis(21L, filterContext);
        Test.stopTest();

        System.assertEquals(
            1,
            findOrdersSection(sections, 'UNSCHEDULED').rows.size(),
            'Draft diary with blank Scheduled Start lands in Unscheduled Work.'
        );
        System.assertEquals(1, filteredKpis.unscheduledCount);
        System.assert(
            filteredKpis.completedThisWeekCount >= 1,
            'Draft completed appointments still surface in Completed This Week.'
        );
    }

    @IsTest
    static void ordersKpisAndFiltersCoverSchedStartBuckets() {
        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'ORDERS';
        filterContext.datasetKey = 'ORDERS_WORK_ORDERS';
        filterContext.filters.add(
            buildFilter('READY_PRESENT', 'Order', 'Ready_For_Billing__c', 'Equals', 'FALSE', 'Static', 10)
        );
        filterContext.filters.add(
            buildFilter('STAGE_PRESENT', 'Opportunity', 'StageName', 'Equals', 'Closed Won', 'Static', 20)
        );

        Test.startTest();
        BillingControl_Orders.KpiWrapper noFilterKpis = BillingControl_Orders.getKpis();
        BillingControl_Orders.KpiWrapper filteredKpis = BillingControl_Orders.getKpis(91L, filterContext);
        List<BillingControl_Orders.BucketSectionWrapper> sections =
            BillingControl_Orders.getBucketWorkOrders();
        Test.stopTest();

        System.assert(noFilterKpis.unscheduledCount >= 1);
        System.assert(filteredKpis.unscheduledCount >= 1);
        System.assertEquals(1, findOrdersSection(sections, 'UNSCHEDULED').rows.size());
        System.assertNotEquals(null, findOrdersSection(sections, 'COMPLETED_THIS_WEEK'));
        System.assertNotEquals(null, findOrdersSection(sections, 'COMPLETED_THIS_MONTH'));
        System.assertNotEquals(null, findOrdersSection(sections, 'NO_OPPORTUNITY'));
        System.assert(noFilterKpis.completedThisWeekCount >= 1);
        System.assert(noFilterKpis.completedThisMonthCount >= 1);
        System.assertEquals(0, noFilterKpis.noOpportunityCount);
    }

    @IsTest
    static void ordersBucketsFollowEarliestStartAndExcludeCompleted() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity scheduledOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Provider Scheduled Opportunity',
            175,
            Date.today().addDays(10)
        );
        Opportunity todayOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Provider Scheduled Today Opportunity',
            185,
            Date.today()
        );
        insert new List<Opportunity>{ scheduledOpportunity, todayOpportunity };

        WorkOrder scheduledWorkOrder = new WorkOrder(
            Subject = 'Provider Scheduled WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder todayWorkOrder = new WorkOrder(
            Subject = 'Provider Scheduled Today WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert new List<WorkOrder>{ scheduledWorkOrder, todayWorkOrder };

        Datetime nextWeekStart = Datetime.newInstance(Date.today().addDays(7), Time.newInstance(9, 0, 0, 0));
        Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        ServiceAppointment scheduledAppointment = new ServiceAppointment(
            ParentRecordId = scheduledWorkOrder.Id,
            Status = 'Scheduled',
            EarliestStartTime = nextWeekStart,
            DueDate = nextWeekStart.addDays(1),
            SchedStartTime = nextWeekStart,
            SchedEndTime = nextWeekStart.addHours(1),
            Subject = 'Provider Scheduled SA',
            Opportunity__c = scheduledOpportunity.Id
        );
        ServiceAppointment todayAppointment = new ServiceAppointment(
            ParentRecordId = todayWorkOrder.Id,
            Status = 'Scheduled',
            EarliestStartTime = todayStart,
            DueDate = todayStart.addDays(1),
            SchedStartTime = todayStart,
            SchedEndTime = todayStart.addHours(1),
            Subject = 'Provider Scheduled Today SA',
            Opportunity__c = todayOpportunity.Id
        );
        insert new List<ServiceAppointment>{ scheduledAppointment, todayAppointment };

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Work_Order__c = scheduledWorkOrder.Id,
                Opportunity__c = scheduledOpportunity.Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = todayWorkOrder.Id,
                Opportunity__c = todayOpportunity.Id
            )
        };
        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{ scheduledWorkOrder.Id, todayWorkOrder.Id }
        );

        insert new List<Order>{
            buildOrder(
                accountRecord.Id,
                scheduledOpportunity.Id,
                standardPricebookId,
                scheduledWorkOrder.Id,
                scheduledAppointment.Id,
                'Draft',
                false,
                175,
                0,
                0,
                Date.today().addDays(10)
            ),
            buildOrder(
                accountRecord.Id,
                todayOpportunity.Id,
                standardPricebookId,
                todayWorkOrder.Id,
                todayAppointment.Id,
                'Draft',
                false,
                185,
                0,
                0,
                Date.today()
            )
        };

        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(77L);
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(77L);
        Test.stopTest();

        BillingControl_Orders.BucketSectionWrapper unscheduledSection = findOrdersSection(
            ordersData.bucketSections,
            'UNSCHEDULED'
        );
        BillingControl_Orders.BucketSectionWrapper scheduledSection = findOrdersSection(
            ordersData.bucketSections,
            'SCHEDULED'
        );
        BillingControl_Orders.BucketSectionWrapper scheduledTodaySection = findOrdersSection(
            ordersData.bucketSections,
            'SCHEDULED_TODAY'
        );
        BillingControl_Orders.BucketSectionWrapper completedThisWeekSection = findOrdersSection(
            ordersData.bucketSections,
            'COMPLETED_THIS_WEEK'
        );
        BillingControl_Orders.BucketSectionWrapper noOpportunitySection = findOrdersSection(
            ordersData.bucketSections,
            'NO_OPPORTUNITY'
        );

        System.assertEquals(1, unscheduledSection.rows.size());
        System.assertEquals(1, scheduledSection.rows.size());
        System.assertEquals(1, scheduledTodaySection.rows.size());
        System.assertNotEquals(null, completedThisWeekSection);
        System.assertEquals(0, noOpportunitySection.rows.size());
        System.assertEquals(scheduledWorkOrder.Id, scheduledSection.rows[0].workOrderId);
        System.assertEquals(todayWorkOrder.Id, scheduledTodaySection.rows[0].workOrderId);
        System.assertEquals(4, invoicingData.metrics.readyToBill);

        Set<Id> scheduledAppointmentIds = new Set<Id>{
            scheduledAppointment.Id,
            todayAppointment.Id
        };
        for (Order orderRecord : [
            SELECT Status
            FROM Order
            WHERE Service_Appointment__c IN :scheduledAppointmentIds
        ]) {
            System.assertEquals('Draft', orderRecord.Status);
        }
    }

    @IsTest
    static void ordersBucketsCoverCompletedWindowsAndNoOpportunity() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        WorkOrder noOpportunityWorkOrder = new WorkOrder(
            Subject = 'No Opportunity WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert noOpportunityWorkOrder;

        Datetime weekActualEnd = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        ServiceAppointment noOpportunityAppointment = new ServiceAppointment(
            ParentRecordId = noOpportunityWorkOrder.Id,
            Status = 'None',
            Subject = 'No Opportunity SA'
        );
        insert noOpportunityAppointment;

        Order noOpportunityOrder = buildOrder(
            accountRecord.Id,
            null,
            standardPricebookId,
            noOpportunityWorkOrder.Id,
            noOpportunityAppointment.Id,
            'Draft',
            false,
            0,
            0,
            0,
            Date.today()
        );
        insert noOpportunityOrder;

        Opportunity completedOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Completed Window Opportunity',
            225,
            Date.today()
        );
        insert completedOpportunity;

        WorkOrder completedWorkOrder = new WorkOrder(
            Subject = 'Completed Window WO',
            Status = 'Completed',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert completedWorkOrder;

        ServiceAppointment completedAppointment = new ServiceAppointment(
            ParentRecordId = completedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = weekActualEnd.addHours(-2),
            SchedEndTime = weekActualEnd.addHours(-1),
            ActualEndTime = weekActualEnd,
            Subject = 'Completed Window SA'
        );
        insert completedAppointment;

        insert new Opportunity_WorkOrder__c(
            Work_Order__c = completedWorkOrder.Id,
            Opportunity__c = completedOpportunity.Id
        );
        WorkOrderLedgerService.backfillWorkOrders(
            new Set<Id>{ noOpportunityWorkOrder.Id, completedWorkOrder.Id }
        );

        insert buildOrder(
            accountRecord.Id,
            completedOpportunity.Id,
            standardPricebookId,
            completedWorkOrder.Id,
            completedAppointment.Id,
            'Ready to Bill',
            true,
            225,
            0,
            0,
            Date.today()
        );

        Test.startTest();
        BillingControl_DataProvider.OrdersRuntimeDataDTO ordersData =
            BillingControl_DataProvider.getOrdersRuntimeData(88L);
        Test.stopTest();

        BillingControl_Orders.BucketSectionWrapper completedThisWeekSection = findOrdersSection(
            ordersData.bucketSections,
            'COMPLETED_THIS_WEEK'
        );
        BillingControl_Orders.BucketSectionWrapper completedThisMonthSection = findOrdersSection(
            ordersData.bucketSections,
            'COMPLETED_THIS_MONTH'
        );
        BillingControl_Orders.BucketSectionWrapper noOpportunitySection = findOrdersSection(
            ordersData.bucketSections,
            'NO_OPPORTUNITY'
        );

        System.assert(ordersData.kpis.completedThisWeekCount >= 1);
        System.assert(ordersData.kpis.completedThisMonthCount >= 1);
        System.assert(
            ordersData.kpis.completedThisWeekRevenue >= 225,
            'Completed KPI revenue uses Opportunity Amount.'
        );
        System.assertEquals(1, noOpportunitySection.rows.size());
        System.assertEquals(noOpportunityWorkOrder.Id, noOpportunitySection.rows[0].workOrderId);
        System.assertEquals(null, noOpportunitySection.rows[0].opportunityAmount);
        System.assertEquals(0, ordersData.kpis.noOpportunityRevenue);
        System.assert(
            completedThisWeekSection.rows.size() >= 1,
            'Completed This Week should include appointments with Actual End in the current week.'
        );
        System.assert(
            completedThisMonthSection.rows.size() >= completedThisWeekSection.rows.size(),
            'Completed This Month should at least cover Completed This Week within the same month.'
        );
    }

    @IsTest
    static void invoicingInvMarkersAreCaseInsensitive() {
        System.assertEquals(true, BillingControl_Invoicing.containsExcludedInvoicingMarker('INV-90033'));
        System.assertEquals(true, BillingControl_Invoicing.containsExcludedInvoicingMarker('Inv 90033'));
        System.assertEquals(true, BillingControl_Invoicing.containsExcludedInvoicingMarker('inspection'));
        System.assertEquals(false, BillingControl_Invoicing.containsExcludedInvoicingMarker('Overhaul'));
        System.assertEquals(false, BillingControl_Invoicing.containsExcludedInvoicingMarker(null));
        System.assertEquals(false, BillingControl_Invoicing.containsExcludedInvoicingMarker(''));
    }

    @IsTest
    static void invoicingKeepsPartiallyMarkedWorkOrdersUninvoiced() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Datetime completionTime = System.now().addHours(-3);

        Opportunity mixedOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Mixed INV Opportunity',
            500,
            Date.today()
        );
        insert mixedOpportunity;

        WorkOrder mixedWorkOrder = new WorkOrder(
            Subject = 'Mixed INV WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert mixedWorkOrder;

        ServiceAppointment markedAppointment = new ServiceAppointment(
            ParentRecordId = mixedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime,
            Subject = 'Marked INV SA',
            Invoice_Number__c = 'Inv 90033',
            Opportunity__c = mixedOpportunity.Id
        );
        ServiceAppointment blankAppointment = new ServiceAppointment(
            ParentRecordId = mixedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime.addMinutes(-10),
            Subject = 'Blank INV SA',
            Opportunity__c = mixedOpportunity.Id
        );
        insert new List<ServiceAppointment>{ markedAppointment, blankAppointment };

        insert new List<Order>{
            buildOrder(
                accountRecord.Id,
                mixedOpportunity.Id,
                standardPricebookId,
                mixedWorkOrder.Id,
                markedAppointment.Id,
                'Ready to Bill',
                true,
                500,
                0,
                0,
                Date.today()
            ),
            buildOrder(
                accountRecord.Id,
                mixedOpportunity.Id,
                standardPricebookId,
                mixedWorkOrder.Id,
                blankAppointment.Id,
                'Ready to Bill',
                true,
                500,
                0,
                0,
                Date.today()
            )
        };

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO mixedData =
            BillingControl_DataProvider.getInvoicingRuntimeData(201L);
        Test.stopTest();

        Set<Id> mixedAppointmentIds = new Set<Id>();
        Set<String> mixedInvoiceNumbers = new Set<String>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : mixedData.groups) {
            if (groupRecord.categoryKey != 'READY_TO_BILL') {
                continue;
            }
            for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : groupRecord.rows) {
                if (row.workOrderId == mixedWorkOrder.Id) {
                    System.assertEquals(UserInfo.getName(), row.ownerName);
                    if (row.relatedServiceAppointments != null) {
                        for (BillingControl_Invoicing.ServiceAppointmentRowWrapper child : row.relatedServiceAppointments) {
                            mixedAppointmentIds.add(child.serviceAppointmentId);
                            if (String.isNotBlank(child.invoiceNumber)) {
                                mixedInvoiceNumbers.add(child.invoiceNumber);
                            }
                        }
                    } else {
                        mixedAppointmentIds.add(row.serviceAppointmentId);
                        if (String.isNotBlank(row.invoiceNumber)) {
                            mixedInvoiceNumbers.add(row.invoiceNumber);
                        }
                    }
                }
            }
        }
        System.assert(
            mixedAppointmentIds.contains(markedAppointment.Id) && mixedAppointmentIds.contains(blankAppointment.Id),
            'A work order stays uninvoiced until every completed service appointment has an INV value.'
        );
        System.assert(
            mixedInvoiceNumbers.contains('Inv 90033'),
            'Invoice Number column should surface the Service Appointment INV value.'
        );
    }

    @IsTest
    static void invoicingExcludesFullyMarkedAndWorkOrderInv() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Datetime completionTime = System.now().addHours(-4);

        Opportunity billedOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Fully Billed INV Opportunity',
            275,
            Date.today()
        );
        Opportunity workOrderInvOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'WO INV Opportunity',
            325,
            Date.today()
        );
        insert new List<Opportunity>{ billedOpportunity, workOrderInvOpportunity };

        WorkOrder billedWorkOrder = new WorkOrder(
            Subject = 'Fully Billed INV WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder workOrderInvWorkOrder = new WorkOrder(
            Subject = 'WO INV Number WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'INV-90069'
        );
        insert new List<WorkOrder>{ billedWorkOrder, workOrderInvWorkOrder };

        ServiceAppointment billedAppointmentOne = new ServiceAppointment(
            ParentRecordId = billedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime,
            Subject = 'Fully Billed SA 1',
            Invoice_Number__c = 'Inv 90001',
            Opportunity__c = billedOpportunity.Id
        );
        ServiceAppointment billedAppointmentTwo = new ServiceAppointment(
            ParentRecordId = billedWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime.addMinutes(-5),
            Subject = 'Fully Billed SA 2',
            Invoice_Number__c = 'INV-90002',
            Opportunity__c = billedOpportunity.Id
        );
        ServiceAppointment workOrderInvAppointment = new ServiceAppointment(
            ParentRecordId = workOrderInvWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime.addMinutes(-8),
            Subject = 'WO INV SA',
            Opportunity__c = workOrderInvOpportunity.Id
        );
        insert new List<ServiceAppointment>{
            billedAppointmentOne,
            billedAppointmentTwo,
            workOrderInvAppointment
        };

        insert new List<Order>{
            buildOrder(
                accountRecord.Id,
                billedOpportunity.Id,
                standardPricebookId,
                billedWorkOrder.Id,
                billedAppointmentOne.Id,
                'Ready to Bill',
                true,
                275,
                0,
                0,
                Date.today()
            ),
            buildOrder(
                accountRecord.Id,
                billedOpportunity.Id,
                standardPricebookId,
                billedWorkOrder.Id,
                billedAppointmentTwo.Id,
                'Ready to Bill',
                true,
                275,
                0,
                0,
                Date.today()
            ),
            buildOrder(
                accountRecord.Id,
                workOrderInvOpportunity.Id,
                standardPricebookId,
                workOrderInvWorkOrder.Id,
                workOrderInvAppointment.Id,
                'Ready to Bill',
                true,
                325,
                0,
                0,
                Date.today()
            )
        };

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(202L);
        Test.stopTest();

        Set<Id> readyAppointmentIds = new Set<Id>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : invoicingData.groups) {
            if (groupRecord.categoryKey != 'READY_TO_BILL') {
                continue;
            }
            for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : groupRecord.rows) {
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
            readyAppointmentIds.contains(billedAppointmentOne.Id) || readyAppointmentIds.contains(billedAppointmentTwo.Id),
            'Work orders with INV on every completed service appointment are billed.'
        );
        System.assertEquals(
            false,
            readyAppointmentIds.contains(workOrderInvAppointment.Id),
            'A work order Invoice Number containing INV bills the whole work order.'
        );
    }

    @IsTest
    static void invoicingEligibilityCoversMissingWorkOrderAndBlankSiblings() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Datetime completionTime = System.now().addHours(-5);

        Opportunity orphanOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Orphan WO Opportunity',
            180,
            Date.today()
        );
        insert orphanOpportunity;

        WorkOrder unusedWorkOrder = new WorkOrder(
            Subject = 'Unused Parent WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        WorkOrder appointmentWorkOrder = new WorkOrder(
            Subject = 'Appointment Parent WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id,
            Invoice_Number__c = 'Overhaul'
        );
        insert new List<WorkOrder>{ unusedWorkOrder, appointmentWorkOrder };

        ServiceAppointment orphanAppointment = new ServiceAppointment(
            ParentRecordId = appointmentWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime,
            Subject = 'No Order WO SA',
            Opportunity__c = orphanOpportunity.Id
        );
        ServiceAppointment mismatchedAppointment = new ServiceAppointment(
            ParentRecordId = appointmentWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = completionTime.addHours(-2),
            SchedEndTime = completionTime.addHours(-1),
            ActualEndTime = completionTime.addMinutes(-4),
            Subject = 'Mismatched WO SA',
            Opportunity__c = orphanOpportunity.Id
        );
        insert new List<ServiceAppointment>{ orphanAppointment, mismatchedAppointment };

        insert new List<Order>{
            buildOrder(
                accountRecord.Id,
                orphanOpportunity.Id,
                standardPricebookId,
                null,
                orphanAppointment.Id,
                'Ready to Bill',
                true,
                180,
                0,
                0,
                Date.today()
            ),
            buildOrder(
                accountRecord.Id,
                orphanOpportunity.Id,
                standardPricebookId,
                unusedWorkOrder.Id,
                mismatchedAppointment.Id,
                'Ready to Bill',
                true,
                180,
                0,
                0,
                Date.today()
            )
        };

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(203L);
        Test.stopTest();

        Set<Id> readyAppointmentIds = new Set<Id>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : invoicingData.groups) {
            if (groupRecord.categoryKey != 'READY_TO_BILL') {
                continue;
            }
            for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : groupRecord.rows) {
                if (row.relatedServiceAppointments != null) {
                    for (BillingControl_Invoicing.ServiceAppointmentRowWrapper child : row.relatedServiceAppointments) {
                        readyAppointmentIds.add(child.serviceAppointmentId);
                    }
                } else {
                    readyAppointmentIds.add(row.serviceAppointmentId);
                }
            }
        }

        System.assert(
            readyAppointmentIds.contains(orphanAppointment.Id),
            'Completed appointments without a work order stay uninvoiced when they have no INV marker.'
        );
        System.assert(
            readyAppointmentIds.contains(mismatchedAppointment.Id),
            'Orders whose work order has no completed siblings stay uninvoiced.'
        );
    }

    @IsTest
    static void directInvoicingFilterOverloadsSupportOrderEffectiveDate() {
        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildFilter('INVOICING_EFFECTIVE_PRESENT', 'Order', 'EffectiveDate', 'Is Not Null', null, 'Static', 10)
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(41L, filterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(41L, filterContext);
        Test.stopTest();

        System.assertEquals(4, metrics.readyToBill, 'The effective-date fixture contains four SA/WO-eligible diaries.');
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            if (groupRecord.categoryKey == 'READY_TO_BILL') {
                System.assertEquals(4, groupRecord.serviceAppointmentCount);
            }
        }
    }

    @IsTest
    static void directInvoicingFiltersSupportNullInvoiceAndDateComparisons() {
        Order filteredOrder = [
            SELECT Id, EffectiveDate, Invoiced_Amount__c
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertNotEquals(null, filteredOrder.EffectiveDate);
        System.assertEquals(0, filteredOrder.Invoiced_Amount__c);

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildFilter('INVOICING_ZERO_INVOICE', 'Order', 'Invoiced_Amount__c', 'Equals', '0', 'Static', 10)
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(42L, filterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(42L, filterContext);
        Test.stopTest();

        System.assertEquals(4, metrics.readyToBill, 'Legacy Invoiced Amount and Effective Date filters do not exclude SA/WO-eligible records.');
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            if (groupRecord.categoryKey == 'READY_TO_BILL') {
                System.assertEquals(4, groupRecord.serviceAppointmentCount);
                System.assert(groupRecord.totalBillableAmount > 0);
            }
        }
    }

    @IsTest
    static void directInvoicingGroupsRowsByWorkOrderButKeepsServiceAppointmentCounts() {
        Order readyOrder = [
            SELECT Id, AccountId, OpportunityId, Work_Order__c, EffectiveDate
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        WorkOrder readyWorkOrder = [
            SELECT Id, WorkTypeId
            FROM WorkOrder
            WHERE Id = :readyOrder.Work_Order__c
            LIMIT 1
        ];
        Id standardPricebookId = Test.getStandardPricebookId();

        List<ServiceAppointment> groupedAppointments = new List<ServiceAppointment>();
        for (Integer indexValue = 0; indexValue < 2; indexValue++) {
            Datetime completionDateTime = Datetime.newInstance(
                readyOrder.EffectiveDate,
                Time.newInstance(11 + indexValue, 0, 0, 0)
            );
            groupedAppointments.add(new ServiceAppointment(
                ParentRecordId = readyWorkOrder.Id,
                Status = 'Completed',
                SchedStartTime = completionDateTime,
                SchedEndTime = completionDateTime.addHours(1),
                ActualEndTime = completionDateTime,
                Subject = 'Grouped Ready SA ' + indexValue,
                Opportunity__c = readyOrder.OpportunityId
            ));
        }
        insert groupedAppointments;

        List<Order> groupedOrders = new List<Order>();
        for (Integer indexValue = 0; indexValue < groupedAppointments.size(); indexValue++) {
            groupedOrders.add(
                buildOrder(
                    readyOrder.AccountId,
                    readyOrder.OpportunityId,
                    standardPricebookId,
                    readyWorkOrder.Id,
                    groupedAppointments[indexValue].Id,
                    'Ready to Bill',
                    true,
                    150 + indexValue,
                    0,
                    0,
                    readyOrder.EffectiveDate
                )
            );
        }
        insert groupedOrders;

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildFilter('READY_ONLY', 'Order', 'Billing_Diary_Status__c', 'Equals', 'Ready to Bill', 'Static', 10)
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(43L, filterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(43L, filterContext);
        Test.stopTest();

        BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper readyToBillGroup = findInvoicingGroup(
            groups,
            'READY_TO_BILL'
        );

        System.assertNotEquals(null, readyToBillGroup);
        System.assertEquals(6, metrics.readyToBill);
        System.assertEquals(6, readyToBillGroup.serviceAppointmentCount);
        System.assertEquals(4, readyToBillGroup.rows.size());
        BillingControl_Invoicing.ServiceAppointmentRowWrapper groupedWorkOrderRow;
        for (BillingControl_Invoicing.ServiceAppointmentRowWrapper row : readyToBillGroup.rows) {
            if (row.workOrderId == readyWorkOrder.Id) groupedWorkOrderRow = row;
        }
        System.assertNotEquals(null, groupedWorkOrderRow);
        System.assertEquals(3, groupedWorkOrderRow.relatedServiceAppointments.size());
        System.assertEquals(3, groupedWorkOrderRow.serviceAppointmentCount);
        System.assertEquals(UserInfo.getName(), groupedWorkOrderRow.ownerName);
    }

    @IsTest
    static void activeInvoicingConfigTreatsNullInvoiceAmountAsUninvoiced() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Opportunity nullInvoiceOpportunity = buildOpportunity(
            accountRecord.Id,
            workTypeRecord.Id,
            'Provider Config Null Invoice Opportunity',
            650,
            Date.today().addDays(10)
        );
        insert nullInvoiceOpportunity;

        WorkOrder nullInvoiceWorkOrder = new WorkOrder(
            Subject = 'Provider Config Null Invoice WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert nullInvoiceWorkOrder;

        Datetime startTime = System.now().addHours(-6);
        ServiceAppointment nullInvoiceAppointment = new ServiceAppointment(
            ParentRecordId = nullInvoiceWorkOrder.Id,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = startTime.addHours(1),
            ActualEndTime = startTime,
            Subject = 'Provider Config Null Invoice SA',
            Opportunity__c = nullInvoiceOpportunity.Id
        );
        insert nullInvoiceAppointment;

        insert new Order(
            AccountId = accountRecord.Id,
            OpportunityId = nullInvoiceOpportunity.Id,
            EffectiveDate = Date.today().addDays(10),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId,
            Work_Order__c = nullInvoiceWorkOrder.Id,
            Service_Appointment__c = nullInvoiceAppointment.Id,
            Technician__c = UserInfo.getUserId(),
            Billing_Diary_Status__c = 'Ready to Bill',
            Ready_For_Billing__c = true,
            Billable_Amount__c = 650
        );

        Test.startTest();
        BillingControl_DataProvider.InvoicingRuntimeDataDTO invoicingData =
            BillingControl_DataProvider.getInvoicingRuntimeData(88L);
        Test.stopTest();

        System.assertEquals(
            5,
            invoicingData.metrics.readyToBill,
            'Eligibility must include SA/WO-eligible records regardless of legacy Invoiced Amount configuration.'
        );
    }

    @IsTest
    static void directOrdersCapRowsButKeepAggregateTotals() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Date bulkEffectiveDate = Date.today().addDays(45);

        createBulkDraftOrderData(
            accountRecord.Id,
            workTypeRecord.Id,
            standardPricebookId,
            bulkEffectiveDate,
            501,
            'Provider Bulk Draft'
        );

        BillingControl_DataProvider.BillingFilterContextDTO ordersFilterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        ordersFilterContext.tabKey = 'ORDERS';
        ordersFilterContext.datasetKey = 'ORDERS_WORK_ORDERS';
        ordersFilterContext.filters.add(
            buildFilter(
                'ORDERS_DRAFT_ONLY',
                'Order',
                'Billing_Diary_Status__c',
                'Equals',
                'Draft',
                'Static',
                5
            )
        );

        Test.startTest();
        List<BillingControl_Orders.BucketSectionWrapper> sections =
            BillingControl_Orders.getBucketWorkOrders(901L, ordersFilterContext);
        BillingControl_Orders.KpiWrapper kpis = BillingControl_Orders.getKpis(901L, ordersFilterContext);
        Test.stopTest();

        BillingControl_Orders.BucketSectionWrapper unscheduledSection = findOrdersSection(
            sections,
            'UNSCHEDULED'
        );

        System.assertNotEquals(null, unscheduledSection);
        System.assertEquals(500, unscheduledSection.rows.size());
        System.assertEquals(502, kpis.unscheduledCount);
        System.assert(kpis.unscheduledCount > unscheduledSection.rows.size());
        System.assert(
            String.join(ordersFilterContext.runtimeWarnings, ' ').contains(
                'Showing first 500 records. Narrow the date filter/search for more specific results.'
            )
        );
    }

    @IsTest
    static void directInvoicingCapRowsButKeepAggregateTotals() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Date bulkEffectiveDate = Date.today().addDays(45);

        createBulkReadyToBillData(
            accountRecord.Id,
            workTypeRecord.Id,
            standardPricebookId,
            bulkEffectiveDate,
            501,
            'Provider Bulk Ready'
        );

        BillingControl_DataProvider.BillingFilterContextDTO invoicingFilterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        invoicingFilterContext.tabKey = 'INVOICING';
        invoicingFilterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        invoicingFilterContext.filters.add(
            buildFilter(
                'INVOICING_EFFECTIVE_START',
                'Order',
                'EffectiveDate',
                'Greater Or Equal',
                formatDateValue(bulkEffectiveDate),
                'Static',
                10
            )
        );
        invoicingFilterContext.filters.add(
            buildFilter(
                'INVOICING_EFFECTIVE_END',
                'Order',
                'EffectiveDate',
                'Less Or Equal',
                formatDateValue(bulkEffectiveDate),
                'Static',
                20
            )
        );

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(902L, invoicingFilterContext);
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups =
            BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(902L, invoicingFilterContext);
        Test.stopTest();

        BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper readyToBillGroup = findInvoicingGroup(
            groups,
            'READY_TO_BILL'
        );

        System.assertNotEquals(null, readyToBillGroup);
        System.assertEquals(500, readyToBillGroup.serviceAppointmentCount);
        System.assertEquals(501, metrics.readyToBill);
        System.assert(metrics.readyToBill > readyToBillGroup.serviceAppointmentCount);
        System.assert(
            String.join(invoicingFilterContext.runtimeWarnings, ' ').contains(
                'Showing first 500 records. Narrow the date filter/search for more specific results.'
            )
        );
    }

    @IsTest
    static void runtimeDataReceivablesCapRowsButKeepAggregateTotals() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Billing Control Provider Test Account'
            LIMIT 1
        ];
        WorkType workTypeRecord = [SELECT Id FROM WorkType LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();
        Date bulkEffectiveDate = Date.today().addDays(60);

        createBulkReceivableData(
            accountRecord.Id,
            workTypeRecord.Id,
            standardPricebookId,
            bulkEffectiveDate,
            501,
            'Provider Bulk Receivable'
        );

        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            buildDateFilter('Custom', formatDateValue(bulkEffectiveDate), formatDateValue(bulkEffectiveDate));

        Test.startTest();
        BillingControl_DataProvider.ReceivablesRuntimeDataDTO receivablesData =
            BillingControl_DataProvider.getReceivablesRuntimeData(903L, dateFilter);
        Test.stopTest();

        BillingControl_Invoicing.CommissionKpiCategoryWrapper revenueSection = findReceivablesSection(
            receivablesData.sections,
            'REVENUE_UNDER_COLLECTION'
        );

        System.assertNotEquals(null, revenueSection);
        System.assertEquals(500, revenueSection.opportunityCount);
        System.assertEquals(501, receivablesData.metrics.revenueUnderCollectionCount);
        System.assert(receivablesData.metrics.revenueUnderCollectionCount > revenueSection.opportunityCount);
        System.assert(
            String.join(receivablesData.warnings, ' ').contains(
                'Showing first 500 records. Narrow the date filter/search for more specific results.'
            )
        );
    }

    private static void insertRuntimeConfig() {
        Billing_Center_Tab_Config__c ordersTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'ORDERS',
            Label__c = 'Work Order Ledger',
            Is_Active__c = true,
            Display_Order__c = 10,
            View_Type__c = 'Grouped Table',
            Default_Date_Filter__c = 'This Year'
        );
        Billing_Center_Tab_Config__c invoicingTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'INVOICING',
            Label__c = 'Invoicing',
            Is_Active__c = true,
            Display_Order__c = 20,
            View_Type__c = 'Table',
            Default_Date_Filter__c = 'This Month'
        );
        Billing_Center_Tab_Config__c receivablesTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'RECEIVABLES',
            Label__c = 'Receivables',
            Is_Active__c = true,
            Display_Order__c = 30,
            View_Type__c = 'Tabset',
            Default_Date_Filter__c = 'This Month'
        );
        insert new List<Billing_Center_Tab_Config__c>{ ordersTab, invoicingTab, receivablesTab };

        insert new List<Billing_Center_Dataset_Config__c>{
            new Billing_Center_Dataset_Config__c(
                Developer_Key__c = 'ORDERS_WORK_ORDERS',
                Label__c = 'Orders Work Orders',
                Is_Active__c = true,
                Data_Source_Type__c = 'Apex Handler',
                Apex_Handler_Key__c = 'BillingControl_WorkOrderLedger.getBucketWorkOrders',
                Source_Object_API_Name__c = 'Work_Order_Ledger__c'
            ),
            new Billing_Center_Dataset_Config__c(
                Developer_Key__c = 'INVOICING_SERVICE_APPOINTMENTS',
                Label__c = 'Invoicing Service Appointments',
                Is_Active__c = true,
                Data_Source_Type__c = 'Apex Handler',
                Apex_Handler_Key__c = 'BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh',
                Source_Object_API_Name__c = 'ServiceAppointment'
            ),
            new Billing_Center_Dataset_Config__c(
                Developer_Key__c = 'RECEIVABLES_INVOICES',
                Label__c = 'Receivables Invoices',
                Is_Active__c = true,
                Data_Source_Type__c = 'Apex Handler',
                Apex_Handler_Key__c = 'BillingControl_Invoicing.getCommissionData',
                Source_Object_API_Name__c = 'Invoice_Line__c'
            ),
            new Billing_Center_Dataset_Config__c(
                Developer_Key__c = 'RECEIVABLES_COMMISSIONS',
                Label__c = 'Receivables Commissions',
                Is_Active__c = true,
                Data_Source_Type__c = 'Apex Handler',
                Apex_Handler_Key__c = 'BillingControl_Invoicing.getCommissionData',
                Source_Object_API_Name__c = 'Commission__c'
            )
        };

        insert new List<Billing_Center_Section_Config__c>{
            new Billing_Center_Section_Config__c(
                Tab_Config__c = ordersTab.Id,
                Developer_Key__c = 'UNSCHEDULED',
                Label__c = 'Unscheduled',
                Is_Active__c = true,
                Display_Order__c = 10,
                Section_Type__c = 'Accordion',
                Dataset_Key__c = 'ORDERS_WORK_ORDERS'
            ),
            new Billing_Center_Section_Config__c(
                Tab_Config__c = invoicingTab.Id,
                Developer_Key__c = 'READY_TO_INVOICE',
                Label__c = 'Ready to Invoice',
                Is_Active__c = true,
                Display_Order__c = 10,
                Section_Type__c = 'Table',
                Dataset_Key__c = 'INVOICING_SERVICE_APPOINTMENTS'
            ),
            new Billing_Center_Section_Config__c(
                Tab_Config__c = receivablesTab.Id,
                Developer_Key__c = 'INVOICES',
                Label__c = 'Invoices',
                Is_Active__c = true,
                Display_Order__c = 10,
                Section_Type__c = 'Table',
                Dataset_Key__c = 'RECEIVABLES_INVOICES'
            ),
            new Billing_Center_Section_Config__c(
                Tab_Config__c = receivablesTab.Id,
                Developer_Key__c = 'COMMISSIONS',
                Label__c = 'Commissions',
                Is_Active__c = true,
                Display_Order__c = 20,
                Section_Type__c = 'Table',
                Dataset_Key__c = 'RECEIVABLES_COMMISSIONS'
            )
        };

        Map<String, Id> datasetIdByKey = new Map<String, Id>();
        for (Billing_Center_Dataset_Config__c datasetRecord : [
            SELECT Id, Developer_Key__c
            FROM Billing_Center_Dataset_Config__c
            WHERE Developer_Key__c IN (
                'ORDERS_WORK_ORDERS',
                'INVOICING_SERVICE_APPOINTMENTS',
                'RECEIVABLES_INVOICES',
                'RECEIVABLES_COMMISSIONS'
            )
        ]) {
            datasetIdByKey.put(datasetRecord.Developer_Key__c, datasetRecord.Id);
        }

        insert new List<Billing_Center_Filter_Config__c>{
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = ordersTab.Id,
                Dataset_Config__c = datasetIdByKey.get('ORDERS_WORK_ORDERS'),
                Developer_Key__c = 'ORDERS_STATUS_ACTIVE',
                Label__c = 'Active Statuses',
                Is_Active__c = true,
                Sequence__c = 10,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Billing_Diary_Status__c',
                Operator__c = 'In',
                Value__c = 'Draft;Ready to Bill',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = ordersTab.Id,
                Dataset_Config__c = datasetIdByKey.get('ORDERS_WORK_ORDERS'),
                Developer_Key__c = 'ORDERS_CREATED_PRESENT',
                Label__c = 'Created Present',
                Is_Active__c = true,
                Sequence__c = 20,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'CreatedDate',
                Operator__c = 'Is Not Null',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = invoicingTab.Id,
                Dataset_Config__c = datasetIdByKey.get('INVOICING_SERVICE_APPOINTMENTS'),
                Developer_Key__c = 'INVOICING_STATUS_READY',
                Label__c = 'Ready Status',
                Is_Active__c = true,
                Sequence__c = 10,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Billing_Diary_Status__c',
                Operator__c = 'Equals',
                Value__c = 'Ready to Bill',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = invoicingTab.Id,
                Dataset_Config__c = datasetIdByKey.get('INVOICING_SERVICE_APPOINTMENTS'),
                Developer_Key__c = 'INVOICING_READY_TRUE',
                Label__c = 'Ready True',
                Is_Active__c = true,
                Sequence__c = 20,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Ready_For_Billing__c',
                Operator__c = 'Equals',
                Value__c = 'TRUE',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = invoicingTab.Id,
                Dataset_Config__c = datasetIdByKey.get('INVOICING_SERVICE_APPOINTMENTS'),
                Developer_Key__c = 'INVOICING_APPT_PRESENT',
                Label__c = 'Appointment Present',
                Is_Active__c = true,
                Sequence__c = 30,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Service_Appointment__c',
                Operator__c = 'Is Not Null',
                Value_Type__c = 'Static'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = invoicingTab.Id,
                Dataset_Config__c = datasetIdByKey.get('INVOICING_SERVICE_APPOINTMENTS'),
                Developer_Key__c = 'INVOICING_ZERO_INVOICED',
                Label__c = 'Zero Invoiced',
                Is_Active__c = true,
                Sequence__c = 40,
                Object_API_Name__c = 'Order',
                Field_API_Name__c = 'Invoiced_Amount__c',
                Operator__c = 'Equals',
                Value__c = '0',
                Value_Type__c = 'Static'
            )
        };
    }

    private static Opportunity buildOpportunity(
        Id accountId,
        Id workTypeId,
        String name,
        Decimal amount,
        Date closeDate
    ) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Closed Won',
            Amount = amount,
            CloseDate = closeDate,
            Work_Type__c = workTypeId,
            Do_not_create_Work_Order__c = true
        );
    }

    private static Order buildOrder(
        Id accountId,
        Id opportunityId,
        Id pricebookId,
        Id workOrderId,
        Id serviceAppointmentId,
        String diaryStatus,
        Boolean readyForBilling,
        Decimal billableAmount,
        Decimal invoicedAmount,
        Decimal receivedAmount,
        Date effectiveDate
    ) {
        return new Order(
            AccountId = accountId,
            OpportunityId = opportunityId,
            EffectiveDate = effectiveDate,
            Status = 'Draft',
            Pricebook2Id = pricebookId,
            Work_Order__c = workOrderId,
            Service_Appointment__c = serviceAppointmentId,
            Technician__c = UserInfo.getUserId(),
            Billing_Diary_Status__c = diaryStatus,
            Ready_For_Billing__c = readyForBilling,
            Billable_Amount__c = billableAmount,
            Invoiced_Amount__c = invoicedAmount,
            Received_Amount__c = receivedAmount
        );
    }

    private static Invoice__c buildInvoice(Id accountId, Id opportunityId, Decimal amount, String invoiceNumber) {
        return new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Status__c = 'Sent',
            Invoice_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Subtotal__c = amount,
            Tax_Amount__c = 0,
            Total_Amount__c = amount,
            Amount_Paid__c = 0,
            Balance_Due__c = amount
        );
    }

    private static void createBulkReadyToBillData(
        Id accountId,
        Id workTypeId,
        Id standardPricebookId,
        Date effectiveDate,
        Integer recordCount,
        String prefix
    ) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer indexValue = 0; indexValue < recordCount; indexValue++) {
            opportunities.add(
                buildOpportunity(
                    accountId,
                    workTypeId,
                    prefix + ' Opportunity ' + indexValue,
                    100 + indexValue,
                    effectiveDate
                )
            );
        }
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            workOrders.add(new WorkOrder(
                Subject = prefix + ' WO ' + indexValue,
                Status = 'New',
                AccountId = accountId,
                WorkTypeId = workTypeId
            ));
        }
        insert workOrders;

        List<ServiceAppointment> appointments = new List<ServiceAppointment>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            Datetime completionDateTime = Datetime.newInstance(
                effectiveDate,
                Time.newInstance(9, 0, 0, 0)
            );
            appointments.add(new ServiceAppointment(
                ParentRecordId = workOrders[indexValue].Id,
                Status = 'Completed',
                SchedStartTime = completionDateTime,
                SchedEndTime = completionDateTime.addHours(1),
                ActualEndTime = completionDateTime,
                Subject = prefix + ' SA ' + indexValue,
                Opportunity__c = opportunities[indexValue].Id
            ));
        }
        insert appointments;

        List<Order> orders = new List<Order>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            orders.add(
                buildOrder(
                    accountId,
                    opportunities[indexValue].Id,
                    standardPricebookId,
                    workOrders[indexValue].Id,
                    appointments[indexValue].Id,
                    'Ready to Bill',
                    true,
                    100 + indexValue,
                    0,
                    0,
                    effectiveDate
                )
            );
        }
        insert orders;
    }

    private static void createBulkDraftOrderData(
        Id accountId,
        Id workTypeId,
        Id standardPricebookId,
        Date effectiveDate,
        Integer recordCount,
        String prefix
    ) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer indexValue = 0; indexValue < recordCount; indexValue++) {
            opportunities.add(
                buildOpportunity(
                    accountId,
                    workTypeId,
                    prefix + ' Opportunity ' + indexValue,
                    50 + indexValue,
                    effectiveDate
                )
            );
        }
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            workOrders.add(new WorkOrder(
                Subject = prefix + ' WO ' + indexValue,
                Status = 'New',
                AccountId = accountId,
                WorkTypeId = workTypeId
            ));
        }
        insert workOrders;

        List<ServiceAppointment> appointments = new List<ServiceAppointment>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            appointments.add(new ServiceAppointment(
                ParentRecordId = workOrders[indexValue].Id,
                Status = 'None',
                Subject = prefix + ' SA ' + indexValue,
                Opportunity__c = opportunities[indexValue].Id
            ));
        }
        insert appointments;

        List<Order> orders = new List<Order>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            orders.add(
                buildOrder(
                    accountId,
                    opportunities[indexValue].Id,
                    standardPricebookId,
                    workOrders[indexValue].Id,
                    appointments[indexValue].Id,
                    'Draft',
                    false,
                    50 + indexValue,
                    0,
                    0,
                    effectiveDate
                )
            );
        }
        insert orders;
    }

    private static void createBulkReceivableData(
        Id accountId,
        Id workTypeId,
        Id standardPricebookId,
        Date effectiveDate,
        Integer recordCount,
        String prefix
    ) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer indexValue = 0; indexValue < recordCount; indexValue++) {
            opportunities.add(
                buildOpportunity(
                    accountId,
                    workTypeId,
                    prefix + ' Opportunity ' + indexValue,
                    200 + indexValue,
                    effectiveDate
                )
            );
        }
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            workOrders.add(new WorkOrder(
                Subject = prefix + ' WO ' + indexValue,
                Status = 'New',
                AccountId = accountId,
                WorkTypeId = workTypeId
            ));
        }
        insert workOrders;

        List<ServiceAppointment> appointments = new List<ServiceAppointment>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            Datetime completionDateTime = Datetime.newInstance(
                effectiveDate,
                Time.newInstance(10, 0, 0, 0)
            );
            appointments.add(new ServiceAppointment(
                ParentRecordId = workOrders[indexValue].Id,
                Status = 'Completed',
                SchedStartTime = completionDateTime,
                SchedEndTime = completionDateTime.addHours(1),
                ActualEndTime = completionDateTime,
                Subject = prefix + ' SA ' + indexValue,
                Opportunity__c = opportunities[indexValue].Id
            ));
        }
        insert appointments;

        List<Order> orders = new List<Order>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            orders.add(
                buildOrder(
                    accountId,
                    opportunities[indexValue].Id,
                    standardPricebookId,
                    workOrders[indexValue].Id,
                    appointments[indexValue].Id,
                    'On Hold',
                    true,
                    200 + indexValue,
                    200 + indexValue,
                    0,
                    effectiveDate
                )
            );
        }
        insert orders;

        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            invoices.add(
                buildInvoice(
                    accountId,
                    opportunities[indexValue].Id,
                    200 + indexValue,
                    prefix.replace(' ', '-') + '-INV-' + indexValue
                )
            );
        }
        insert invoices;

        List<Invoice_Line__c> invoiceLines = new List<Invoice_Line__c>();
        for (Integer indexValue = 0; indexValue < opportunities.size(); indexValue++) {
            invoiceLines.add(new Invoice_Line__c(
                Invoice__c = invoices[indexValue].Id,
                Opportunity__c = opportunities[indexValue].Id,
                Work_Order__c = workOrders[indexValue].Id,
                Service_Appointment__c = appointments[indexValue].Id,
                Billing_Order__c = orders[indexValue].Id,
                Description__c = prefix + ' Line ' + indexValue,
                Quantity__c = 1,
                Unit_Price__c = 200 + indexValue,
                Line_Total__c = 200 + indexValue
            ));
        }
        insert invoiceLines;
    }

    private static Integer countOrderRows(List<BillingControl_Orders.BucketSectionWrapper> sections) {
        Integer rowCount = 0;
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            rowCount += sectionRecord.rows.size();
        }
        return rowCount;
    }

    private static BillingControl_DataProvider.BillingFilterDTO buildFilter(
        String developerKey,
        String objectApiName,
        String fieldApiName,
        String operatorValue,
        String value,
        String valueType,
        Decimal sequence
    ) {
        BillingControl_DataProvider.BillingFilterDTO filterRecord = new BillingControl_DataProvider.BillingFilterDTO();
        filterRecord.developerKey = developerKey;
        filterRecord.objectApiName = objectApiName;
        filterRecord.fieldApiName = fieldApiName;
        filterRecord.operator = operatorValue;
        filterRecord.value = value;
        filterRecord.valueType = valueType;
        filterRecord.sequence = sequence;
        return filterRecord;
    }

    private static BillingControl_DataProvider.BillingDateFilterDTO buildDateFilter(
        String filterKey,
        String startDate,
        String endDate
    ) {
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter =
            new BillingControl_DataProvider.BillingDateFilterDTO();
        dateFilter.filterKey = filterKey;
        dateFilter.startDate = startDate;
        dateFilter.endDate = endDate;
        return dateFilter;
    }

    private static Integer countInvoicingRows(
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups
    ) {
        Integer rowCount = 0;
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            rowCount += groupRecord.serviceAppointmentCount;
        }
        return rowCount;
    }

    private static String formatDateValue(Date value) {
        return String.valueOf(value.year())
            + '-'
            + String.valueOf(value.month()).leftPad(2, '0')
            + '-'
            + String.valueOf(value.day()).leftPad(2, '0');
    }

    private static BillingControl_Orders.BucketSectionWrapper findOrdersSection(
        List<BillingControl_Orders.BucketSectionWrapper> sections,
        String bucketKey
    ) {
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            if (sectionRecord.bucketKey == bucketKey) {
                return sectionRecord;
            }
        }
        return null;
    }

    private static BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper findInvoicingGroup(
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups,
        String categoryKey
    ) {
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            if (groupRecord.categoryKey == categoryKey) {
                return groupRecord;
            }
        }
        return null;
    }

    private static BillingControl_Invoicing.CommissionKpiCategoryWrapper findReceivablesSection(
        List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections,
        String categoryKey
    ) {
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper sectionRecord : sections) {
            if (sectionRecord.categoryKey == categoryKey) {
                return sectionRecord;
            }
        }
        return null;
    }

}