@IsTest
private class BillingControl_ReadyToBillKpiTest {
    @IsTest
    static void readinessSectionsCountUniqueOpportunities() {
        WorkOrderLedgerAutomationControl.disableForTests();
        Account accountRecord = new Account(Name = 'Ready To Bill KPI Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Ready To Bill KPI Type', 1);

        Opportunity opportunityToday = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'KPI Today Opp', 10000);
        Opportunity opportunityThisWeek = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'KPI Week Opp', 5000);
        Opportunity opportunityOlder = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'KPI Older Opp', 2000);
        Opportunity opportunityNoAmount = insertOpportunity(accountRecord.Id, workTypeRecord.Id, 'KPI Null Amount Opp', null);

        List<WorkOrder> workOrders = new List<WorkOrder>();
        for (Integer indexValue = 0; indexValue < 6; indexValue++) {
            workOrders.add(new WorkOrder(
                Subject = 'KPI WO ' + indexValue,
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ));
        }
        insert workOrders;

        Date todayDate = Date.today();
        Date weekStart = todayDate.toStartOfWeek();
        Date earlierThisWeek = weekStart < todayDate ? weekStart : null;
        Date lastWeek = weekStart.addDays(-1);
        Datetime todayEnd = Datetime.newInstance(todayDate, Time.newInstance(14, 0, 0, 0));
        Datetime lastWeekEnd = Datetime.newInstance(lastWeek, Time.newInstance(14, 0, 0, 0));

        List<ServiceAppointment> appointments = new List<ServiceAppointment>{
            buildCompletedAppointment(workOrders[0].Id, opportunityToday.Id, todayEnd.addHours(-2), todayEnd, 'KPI Today SA 1'),
            buildCompletedAppointment(workOrders[1].Id, opportunityToday.Id, todayEnd.addHours(-1), todayEnd, 'KPI Today SA 2'),
            buildCompletedAppointment(workOrders[2].Id, opportunityToday.Id, todayEnd.addMinutes(-30), todayEnd, 'KPI Today SA 3'),
            buildCompletedAppointment(
                workOrders[3].Id,
                opportunityNoAmount.Id,
                todayEnd.addHours(-3),
                todayEnd,
                'KPI Today Null Amount SA'
            ),
            buildCompletedAppointment(
                workOrders[4].Id,
                opportunityOlder.Id,
                lastWeekEnd.addHours(-1),
                lastWeekEnd,
                'KPI Older SA'
            )
        };
        if (earlierThisWeek != null) {
            Datetime weekEndTime = Datetime.newInstance(earlierThisWeek, Time.newInstance(11, 0, 0, 0));
            appointments.add(
                buildCompletedAppointment(
                    workOrders[5].Id,
                    opportunityThisWeek.Id,
                    weekEndTime.addHours(-1),
                    weekEndTime,
                    'KPI Earlier This Week SA'
                )
            );
        }
        insert appointments;

        Test.startTest();
        BillingControl_Invoicing.BillingControlMetricsWrapper metrics =
            BillingControl_Invoicing.getServiceAppointmentBillingMetrics();
        List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sections =
            BillingControl_Invoicing.getBillableServiceAppointmentGroups();
        Test.stopTest();

        Integer expectedReadyToBill = earlierThisWeek == null ? 3 : 4;
        System.assertEquals(
            expectedReadyToBill,
            metrics.balancesReadyCount,
            'Quoted and missing-amount Opportunities with unbilled visits are Ready to Bill.'
        );
        System.assertEquals(1, metrics.needsReviewCount, 'Null Amount Opportunity is Needs Review.');
        System.assertEquals(expectedReadyToBill, metrics.readyToBill, 'Unique Opportunities across readiness reasons.');

        Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> sectionByKey =
            new Map<String, BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper>();
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
        }
        System.assertEquals(4, sections.size());
        System.assertEquals(false, sectionByKey.containsKey('BLOCKED'));
        System.assertEquals(
            expectedReadyToBill,
            sectionByKey.get('BALANCES_READY').opportunityRows.size()
        );
        System.assertEquals(1, sectionByKey.get('NEEDS_REVIEW').opportunityRows.size());
        System.assertEquals(true, collectOpportunityIds(sectionByKey.get('BALANCES_READY')).contains(opportunityToday.Id));
        System.assertEquals(1, countMatches(sectionByKey.get('BALANCES_READY'), opportunityToday.Id));
    }

    private static Integer countMatches(
        BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section,
        Id opportunityId
    ) {
        Integer matchCount = 0;
        for (Id rowOpportunityId : collectOpportunityIds(section)) {
            if (rowOpportunityId == opportunityId) {
                matchCount++;
            }
        }
        return matchCount;
    }

    private static Set<Id> collectOpportunityIds(
        BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper section
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (section == null || section.opportunityRows == null) {
            return opportunityIds;
        }
        for (BillingControl_BillingReadiness.OpportunityRow row : section.opportunityRows) {
            opportunityIds.add(row.opportunityId);
        }
        return opportunityIds;
    }

    private static Opportunity insertOpportunity(Id accountId, Id workTypeId, String name, Decimal amount) {
        Opportunity opportunityRecord = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            Amount = amount,
            CloseDate = Date.today().addDays(10),
            Work_Type__c = workTypeId,
            Do_not_create_Work_Order__c = true
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static ServiceAppointment buildCompletedAppointment(
        Id workOrderId,
        Id opportunityId,
        Datetime startTime,
        Datetime endTime,
        String subject
    ) {
        return new ServiceAppointment(
            ParentRecordId = workOrderId,
            Status = 'Completed',
            SchedStartTime = startTime,
            SchedEndTime = endTime,
            ActualEndTime = endTime,
            Subject = subject,
            Opportunity__c = opportunityId
        );
    }
}
