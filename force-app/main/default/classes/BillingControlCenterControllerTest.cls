@isTest
private class BillingControlCenterControllerTest {
    @testSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'Billing Controller Test Account');
        insert accountRecord;

        WorkType installType = TestDataFactory.createWorkType('Controller Install', 2);
        WorkType completionType = TestDataFactory.createWorkType('Controller Completion', 3);

        List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Processed Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Prospecting',
                Amount = 150,
                CloseDate = Date.today().addDays(10),
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'In Progress Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Qualification',
                Amount = 250,
                CloseDate = Date.today().addDays(12),
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Activated Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 300,
                CloseDate = Date.today().addDays(15),
                Work_Type__c = completionType.Id,
                Do_not_create_Work_Order__c = true
            )
        };
        insert opportunities;

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'In Progress Work Order',
                Status = 'In Progress',
                AccountId = accountRecord.Id,
                WorkTypeId = installType.Id
            ),
            new WorkOrder(
                Subject = 'Completed Work Order',
                Status = 'Completed',
                AccountId = accountRecord.Id,
                WorkTypeId = completionType.Id
            ),
            new WorkOrder(
                Subject = 'Closed Work Order',
                Status = 'Closed',
                AccountId = accountRecord.Id,
                WorkTypeId = completionType.Id
            )
        };
        insert workOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[1].Id,
                Work_Order__c = workOrders[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[2].Id,
                Work_Order__c = workOrders[1].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = opportunities[2].Id,
                Work_Order__c = workOrders[2].Id
            )
        };

        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(
            Name = 'Billing Controller Product',
            IsActive = true
        );
        insert productRecord;

        PricebookEntry standardEntry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert standardEntry;

        List<Order> orders = new List<Order>{
            new Order(
                Name = 'Processed Order',
                AccountId = accountRecord.Id,
                OpportunityId = opportunities[0].Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = standardPricebookId
            ),
            new Order(
                Name = 'In Progress Order',
                AccountId = accountRecord.Id,
                OpportunityId = opportunities[1].Id,
                EffectiveDate = Date.today().addDays(1),
                Status = 'Draft',
                Pricebook2Id = standardPricebookId
            ),
            new Order(
                Name = 'Unbilled Order',
                AccountId = accountRecord.Id,
                OpportunityId = opportunities[2].Id,
                EffectiveDate = Date.today().addDays(2),
                Status = 'Draft',
                Pricebook2Id = standardPricebookId
            ),
            new Order(
                Name = 'Processed No Opportunity Order',
                AccountId = accountRecord.Id,
                EffectiveDate = Date.today().addDays(3),
                Status = 'Draft',
                Pricebook2Id = standardPricebookId
            ),
            new Order(
                Name = 'Draft Order',
                AccountId = accountRecord.Id,
                OpportunityId = opportunities[0].Id,
                EffectiveDate = Date.today().addDays(4),
                Status = 'Draft',
                Pricebook2Id = standardPricebookId
            )
        };
        insert orders;

        insert new List<OrderItem>{
            new OrderItem(OrderId = orders[0].Id, Quantity = 1, UnitPrice = 150, PricebookEntryId = standardEntry.Id),
            new OrderItem(OrderId = orders[1].Id, Quantity = 1, UnitPrice = 250, PricebookEntryId = standardEntry.Id),
            new OrderItem(OrderId = orders[2].Id, Quantity = 1, UnitPrice = 300, PricebookEntryId = standardEntry.Id),
            new OrderItem(OrderId = orders[3].Id, Quantity = 1, UnitPrice = 50, PricebookEntryId = standardEntry.Id),
            new OrderItem(OrderId = orders[4].Id, Quantity = 1, UnitPrice = 999, PricebookEntryId = standardEntry.Id)
        };

        orders[0].Status = 'Activated';
        orders[0].CompanyAuthorizedById = UserInfo.getUserId();
        orders[0].CompanyAuthorizedDate = Date.today();
        orders[1].Status = 'Activated';
        orders[1].CompanyAuthorizedById = UserInfo.getUserId();
        orders[1].CompanyAuthorizedDate = Date.today();
        orders[2].Status = 'Activated';
        orders[2].CompanyAuthorizedById = UserInfo.getUserId();
        orders[2].CompanyAuthorizedDate = Date.today();
        orders[3].Status = 'Activated';
        orders[3].CompanyAuthorizedById = UserInfo.getUserId();
        orders[3].CompanyAuthorizedDate = Date.today();
        update new List<Order>{ orders[0], orders[1], orders[2], orders[3] };
    }

    @isTest
    static void testGetKpisPipelineBucketsClosedWon() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Controller Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType WHERE Name = 'Controller Install' LIMIT 1];

        List<Opportunity> pipelineOpportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'KPI Unscheduled No Work Order',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 100,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'KPI Unscheduled For Clearance',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 200,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'KPI Scheduled Appointments Booked',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 300,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'KPI In Progress Service Appointment',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 400,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'KPI Precedence In Progress Over Unscheduled',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 500,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        };
        insert pipelineOpportunities;

        List<WorkOrder> pipelineWorkOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'KPI WO For Clearance',
                Status = 'For Clearance',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'KPI WO Appointments Booked Scheduled',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'KPI WO Appointments Booked In Progress',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'KPI WO For Appointment Booking',
                Status = 'For Appointment Booking',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'KPI WO Appointments Booked Precedence',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            )
        };
        insert pipelineWorkOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[1].Id,
                Work_Order__c = pipelineWorkOrders[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[2].Id,
                Work_Order__c = pipelineWorkOrders[1].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[3].Id,
                Work_Order__c = pipelineWorkOrders[2].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[4].Id,
                Work_Order__c = pipelineWorkOrders[3].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[4].Id,
                Work_Order__c = pipelineWorkOrders[4].Id
            )
        };

        Datetime scheduleStart = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        Datetime scheduleEnd = Datetime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[1].Id,
                Status = 'Scheduled',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'KPI SA Scheduled'
            ),
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[2].Id,
                Status = 'In Progress',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'KPI SA In Progress'
            ),
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[4].Id,
                Status = 'In Progress',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'KPI SA Precedence In Progress'
            ),
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[1].Id,
                Status = 'Completed',
                SchedStartTime = scheduleStart.addDays(-1),
                SchedEndTime = scheduleEnd.addDays(-1),
                ActualEndTime = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0)),
                Subject = 'KPI SA Completed Today'
            )
        };

        Test.startTest();
        BillingControl_Orders.KpiWrapper result = BillingControl_Orders.getKpis();
        Test.stopTest();

        System.assertEquals(2, result.unscheduledCount, 'Unscheduled should include each work order in unscheduled statuses.');
        System.assertEquals(700, result.unscheduledRevenue, 'Unscheduled revenue should use opportunity amount for each unscheduled work order row.');

        System.assertEquals(
            3,
            result.scheduledCount,
            'Scheduled Work should include work orders with at least one Scheduled/In Progress service appointment.'
        );
        System.assertEquals(1200, result.scheduledRevenue, 'Scheduled Work revenue should sum opportunity amount for each matching work order.');

        System.assertEquals(
            3,
            result.scheduledTodayCount,
            'Scheduled for Today should include Scheduled/In Progress service appointments with schedule date today.'
        );
        System.assertEquals(1200, result.scheduledTodayRevenue);

        System.assertEquals(1, result.completedTodayCount, 'Completed Today should include completed service appointments with ActualEndTime today.');
        System.assertEquals(300, result.completedTodayRevenue);
    }

    @isTest
    static void testGetKpisExcludesClosedWonWithOnlyCompletedWorkOrders() {
        BillingControl_Orders.KpiWrapper result = BillingControl_Orders.getKpis();

        System.assertEquals(
            0,
            result.unscheduledCount + result.scheduledCount + result.scheduledTodayCount + result.completedTodayCount,
            'Closed Won tied only to non-matching statuses/dates should not appear in any Orders KPI bucket.'
        );
        System.assertEquals(
            0,
            result.unscheduledRevenue + result.scheduledRevenue + result.scheduledTodayRevenue + result.completedTodayRevenue,
            'Pipeline revenue should be zero when no Closed Won matches unscheduled, scheduled, scheduled today, or completed today rules.'
        );
    }

    @isTest
    static void testGetBucketWorkOrdersAlwaysReturnsFourSectionsWhenEmpty() {
        List<BillingControl_Orders.BucketSectionWrapper> sections = BillingControl_Orders.getBucketWorkOrders();
        System.assertEquals(4, sections.size(), 'Orders bucket response must always include the four fixed KPI sections.');

        Map<String, Integer> countsByBucket = new Map<String, Integer>();
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            countsByBucket.put(sectionRecord.bucketKey, sectionRecord.rows.size());
        }

        System.assertEquals(0, countsByBucket.get('UNSCHEDULED'));
        System.assertEquals(0, countsByBucket.get('SCHEDULED'));
        System.assertEquals(0, countsByBucket.get('SCHEDULED_TODAY'));
        System.assertEquals(0, countsByBucket.get('COMPLETED_TODAY'));
    }

    @isTest
    static void testGetBucketWorkOrdersDirectClassification() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Controller Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType WHERE Name = 'Controller Install' LIMIT 1];

        Opportunity drillOpp = new Opportunity(
            Name = 'Drilldown Closed Won',
            AccountId = accountRecord.Id,
            StageName = 'Closed Won',
            Amount = 777,
            CloseDate = Date.today(),
            Work_Type__c = workTypeRecord.Id,
            Do_not_create_Work_Order__c = true
        );
        insert drillOpp;

        List<WorkOrder> drillWorkOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'Drill Unscheduled',
                Status = 'For Clearance',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill Scheduled',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill In Progress',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill Precedence IP Over Scheduled',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill Excluded Completed',
                Status = 'Completed',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            )
        };
        insert drillWorkOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(Opportunity__c = drillOpp.Id, Work_Order__c = drillWorkOrders[0].Id),
            new Opportunity_WorkOrder__c(Opportunity__c = drillOpp.Id, Work_Order__c = drillWorkOrders[1].Id),
            new Opportunity_WorkOrder__c(Opportunity__c = drillOpp.Id, Work_Order__c = drillWorkOrders[2].Id),
            new Opportunity_WorkOrder__c(Opportunity__c = drillOpp.Id, Work_Order__c = drillWorkOrders[3].Id),
            new Opportunity_WorkOrder__c(Opportunity__c = drillOpp.Id, Work_Order__c = drillWorkOrders[4].Id)
        };

        Datetime scheduleStart = Datetime.newInstance(Date.today(), Time.newInstance(13, 0, 0, 0));
        Datetime scheduleEnd = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = drillWorkOrders[1].Id,
                Status = 'Scheduled',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill SA Scheduled'
            ),
            new ServiceAppointment(
                ParentRecordId = drillWorkOrders[2].Id,
                Status = 'In Progress',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill SA In Progress'
            ),
            new ServiceAppointment(
                ParentRecordId = drillWorkOrders[3].Id,
                Status = 'Scheduled',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill SA Both Scheduled'
            ),
            new ServiceAppointment(
                ParentRecordId = drillWorkOrders[3].Id,
                Status = 'In Progress',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill SA Both In Progress'
            ),
            new ServiceAppointment(
                ParentRecordId = drillWorkOrders[4].Id,
                Status = 'Completed',
                SchedStartTime = scheduleStart.addDays(-1),
                SchedEndTime = scheduleEnd.addDays(-1),
                ActualEndTime = Datetime.newInstance(Date.today(), Time.newInstance(15, 0, 0, 0)),
                Subject = 'Drill SA Completed Today'
            )
        };

        Test.startTest();
        List<BillingControl_Orders.BucketSectionWrapper> sections = BillingControl_Orders.getBucketWorkOrders();
        Test.stopTest();

        System.assertEquals(4, sections.size(), 'Four bucket sections should always be returned.');

        Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>> rowsByBucket = new Map<String, List<BillingControl_Orders.WorkOrderRowWrapper>>();
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            rowsByBucket.put(sectionRecord.bucketKey, sectionRecord.rows);
        }

        System.assertEquals(
            1,
            rowsByBucket.get('UNSCHEDULED').size(),
            'For Clearance work order should appear in the unscheduled bucket.'
        );
        System.assertEquals('For Clearance', rowsByBucket.get('UNSCHEDULED')[0].status);
        System.assertNotEquals(
            null,
            rowsByBucket.get('UNSCHEDULED')[0].createdDate,
            'Create date should be populated from the work order.'
        );

        System.assertEquals(3, rowsByBucket.get('SCHEDULED').size(), 'Scheduled Work should include work orders having any Scheduled/In Progress service appointment.');
        Set<String> scheduledSubjects = new Set<String>();
        for (BillingControl_Orders.WorkOrderRowWrapper row : rowsByBucket.get('SCHEDULED')) {
            scheduledSubjects.add(row.subject);
        }
        System.assertEquals(true, scheduledSubjects.contains('Drill Scheduled'));
        System.assertEquals(true, scheduledSubjects.contains('Drill In Progress'));
        System.assertEquals(true, scheduledSubjects.contains('Drill Precedence IP Over Scheduled'));

        System.assertEquals(4, rowsByBucket.get('SCHEDULED_TODAY').size(), 'Scheduled for Today should return one row per matching service appointment.');
        for (BillingControl_Orders.WorkOrderRowWrapper row : rowsByBucket.get('SCHEDULED_TODAY')) {
            System.assertNotEquals(null, row.serviceAppointmentId, 'Scheduled for Today rows must be service-appointment driven.');
            System.assertEquals('Appointments Booked', row.status, 'Scheduled for Today rows should display Work Order status.');
            System.assertNotEquals(null, row.serviceAppointmentDisplay);
        }

        System.assertEquals(1, rowsByBucket.get('COMPLETED_TODAY').size(), 'Completed Today should return one row per completed-today service appointment.');
        System.assertNotEquals(null, rowsByBucket.get('COMPLETED_TODAY')[0].serviceAppointmentId);
        System.assertEquals('Completed', rowsByBucket.get('COMPLETED_TODAY')[0].status);

        Set<Id> allReturnedWorkOrderIds = new Set<Id>();
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            for (BillingControl_Orders.WorkOrderRowWrapper row : sectionRecord.rows) {
                allReturnedWorkOrderIds.add(row.workOrderId);
            }
        }
        System.assertEquals(
            true,
            allReturnedWorkOrderIds.contains(drillWorkOrders[4].Id),
            'Completed-today service appointments should surface their parent work order in the completed-today bucket.'
        );
    }

    @isTest
    static void testGetBucketWorkOrdersMatchesPipelineKpiData() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'Billing Controller Test Account' LIMIT 1];
        WorkType workTypeRecord = [SELECT Id FROM WorkType WHERE Name = 'Controller Install' LIMIT 1];

        List<Opportunity> pipelineOpportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Drill KPI For Clearance',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 200,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Drill KPI Scheduled',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 300,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Drill KPI In Progress',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 400,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        };
        insert pipelineOpportunities;

        List<WorkOrder> pipelineWorkOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'Drill KPI WO For Clearance',
                Status = 'For Clearance',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill KPI WO Scheduled',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Drill KPI WO In Progress',
                Status = 'Appointments Booked',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            )
        };
        insert pipelineWorkOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[0].Id,
                Work_Order__c = pipelineWorkOrders[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[1].Id,
                Work_Order__c = pipelineWorkOrders[1].Id
            ),
            new Opportunity_WorkOrder__c(
                Opportunity__c = pipelineOpportunities[2].Id,
                Work_Order__c = pipelineWorkOrders[2].Id
            )
        };

        Datetime scheduleStart = Datetime.newInstance(Date.today(), Time.newInstance(16, 0, 0, 0));
        Datetime scheduleEnd = Datetime.newInstance(Date.today(), Time.newInstance(17, 0, 0, 0));
        insert new List<ServiceAppointment>{
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[1].Id,
                Status = 'Scheduled',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill KPI SA Scheduled'
            ),
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[2].Id,
                Status = 'In Progress',
                SchedStartTime = scheduleStart,
                SchedEndTime = scheduleEnd,
                Subject = 'Drill KPI SA In Progress'
            ),
            new ServiceAppointment(
                ParentRecordId = pipelineWorkOrders[2].Id,
                Status = 'Completed',
                SchedStartTime = scheduleStart.addDays(-1),
                SchedEndTime = scheduleEnd.addDays(-1),
                ActualEndTime = Datetime.newInstance(Date.today(), Time.newInstance(18, 0, 0, 0)),
                Subject = 'Drill KPI SA Completed Today'
            )
        };

        List<BillingControl_Orders.BucketSectionWrapper> sections = BillingControl_Orders.getBucketWorkOrders();
        Map<String, Integer> countsByBucket = new Map<String, Integer>();
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            countsByBucket.put(sectionRecord.bucketKey, sectionRecord.rows.size());
        }

        System.assertEquals(1, countsByBucket.get('UNSCHEDULED'));
        System.assertEquals(2, countsByBucket.get('SCHEDULED'));
        System.assertEquals(2, countsByBucket.get('SCHEDULED_TODAY'));
        System.assertEquals(1, countsByBucket.get('COMPLETED_TODAY'));
    }
}