@IsTest
private class BillingControl_ReadyToBillKpiTest {
    @IsTest
    static void readyToBillPeriodKpisDeduplicateOpportunityAmount() {
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
        Test.stopTest();

        Integer expectedTodayCount = 4;
        Decimal expectedTodayAmount = 10000;
        Integer expectedWeekCount = earlierThisWeek == null ? 4 : 5;
        Decimal expectedWeekAmount = earlierThisWeek == null ? 10000 : 15000;
        Integer expectedLaterCount = earlierThisWeek == null ? 5 : 6;
        Decimal expectedLaterAmount = earlierThisWeek == null ? 12000 : 17000;

        System.assertEquals(expectedTodayCount, metrics.completedTodayCount, 'Today counts Ready to Bill Service Appointments.');
        System.assertEquals(expectedTodayAmount, metrics.completedTodayAmount, 'Today amounts are unique by Opportunity.');
        System.assertEquals(expectedWeekCount, metrics.completedThisWeekCount, 'This Week includes Completed Today.');
        System.assertEquals(expectedWeekAmount, metrics.completedThisWeekAmount, 'This Week amounts are unique by Opportunity.');
        System.assertEquals(expectedLaterCount, metrics.completedLaterCount, 'Completed Later includes every Ready to Bill record.');
        System.assertEquals(expectedLaterAmount, metrics.completedLaterAmount, 'Completed Later amounts are unique by Opportunity.');
        System.assertEquals(metrics.readyToBill, metrics.completedLaterCount);
        System.assertEquals(metrics.unbilledRevenue, metrics.completedLaterAmount);
        System.assertEquals(true, metrics.completedTodayCount <= metrics.completedThisWeekCount);
        System.assertEquals(true, metrics.completedThisWeekCount <= metrics.completedLaterCount);
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
