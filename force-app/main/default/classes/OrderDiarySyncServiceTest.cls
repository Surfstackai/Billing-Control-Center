@IsTest
private class OrderDiarySyncServiceTest {
    @IsTest
    static void deriveOperationalStateFollowsEarliestStartAndCompleted() {
        OrderDiarySyncService.OrderDiaryOperationalState unscheduledState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'None', null, null, 0, 0);
        System.assertEquals(OrderDiarySyncService.getDraftStatusValue(), unscheduledState.billingDiaryStatus);
        System.assertEquals(false, unscheduledState.readyForBilling);

        Datetime scheduledStart = Datetime.newInstance(Date.today().addDays(3), Time.newInstance(9, 0, 0, 0));
        OrderDiarySyncService.OrderDiaryOperationalState blankSchedStartState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'None', null, null, 0, 0);
        System.assertEquals(OrderDiarySyncService.getDraftStatusValue(), blankSchedStartState.billingDiaryStatus);

        OrderDiarySyncService.OrderDiaryOperationalState scheduledState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'Scheduled', null, scheduledStart, 0, 0);
        System.assertEquals(OrderDiarySyncService.getForReviewStatusValue(), scheduledState.billingDiaryStatus);
        System.assertEquals(false, scheduledState.readyForBilling);

        OrderDiarySyncService.OrderDiaryOperationalState completedState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'Completed', System.now(), scheduledStart, 0, 0);
        System.assertEquals(OrderDiarySyncService.getReadyToBillStatusValue(), completedState.billingDiaryStatus);
        System.assertEquals(true, completedState.readyForBilling);

        OrderDiarySyncService.OrderDiaryOperationalState holdState =
            OrderDiarySyncService.deriveOperationalState(null, 'Waiting on parts', 'Scheduled', null, scheduledStart, 0, 0);
        System.assertEquals(OrderDiarySyncService.getOnHoldStatusValue(), holdState.billingDiaryStatus);
        System.assertEquals(false, holdState.readyForBilling);

        OrderDiarySyncService.OrderDiaryOperationalState invoicedState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'Completed', System.now(), scheduledStart, 250, 0);
        System.assertEquals(OrderDiaryFinancialSyncService.getInvoicedStatusValue(), invoicedState.billingDiaryStatus);
        System.assertEquals(false, invoicedState.readyForBilling);

        OrderDiarySyncService.OrderDiaryOperationalState paidState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'Completed', System.now(), scheduledStart, 250, 250);
        System.assertEquals(OrderDiaryFinancialSyncService.getPaidStatusValue(), paidState.billingDiaryStatus);

        OrderDiarySyncService.OrderDiaryOperationalState legacySignatureState =
            OrderDiarySyncService.deriveOperationalState(null, null, 'None', null, 0, 0);
        System.assertEquals(OrderDiarySyncService.getDraftStatusValue(), legacySignatureState.billingDiaryStatus);
    }

    @IsTest
    static void hasRelevantChangeHelpersDetectWatchedFields() {
        ServiceAppointment oldAppointment = new ServiceAppointment(
            Status = 'None',
            EarliestStartTime = null,
            SchedStartTime = null
        );
        ServiceAppointment newAppointment = new ServiceAppointment(
            Status = 'None',
            EarliestStartTime = System.now(),
            SchedStartTime = System.now()
        );
        System.assertEquals(
            true,
            OrderDiarySyncService.hasRelevantServiceAppointmentChanges(newAppointment, oldAppointment)
        );
        System.assertEquals(
            false,
            OrderDiarySyncService.hasRelevantServiceAppointmentChanges(oldAppointment, oldAppointment)
        );

        WorkOrder oldWorkOrder = new WorkOrder(AccountId = null);
        WorkOrder newWorkOrder = new WorkOrder(AccountId = UserInfo.getUserId());
        System.assertEquals(true, OrderDiarySyncService.hasRelevantWorkOrderChanges(newWorkOrder, oldWorkOrder));
        System.assertEquals(false, OrderDiarySyncService.hasRelevantWorkOrderChanges(oldWorkOrder, oldWorkOrder));

        Opportunity_WorkOrder__c oldJunction = new Opportunity_WorkOrder__c();
        Opportunity_WorkOrder__c newJunction = new Opportunity_WorkOrder__c();
        System.assertEquals(
            false,
            OrderDiarySyncService.hasRelevantOpportunityWorkOrderChanges(oldJunction, newJunction)
        );
    }

    @IsTest
    static void invocableAndWorkOrderSyncEntryPointsAreSafe() {
        OrderDiarySyncService.syncServiceAppointmentsInvocable(null);
        OrderDiarySyncService.syncWorkOrdersInvocable(null);
        OrderDiarySyncService.syncOpportunityWorkOrdersInvocable(null);
        OrderDiarySyncService.syncServiceAppointmentIds(new Set<Id>());
        OrderDiarySyncService.syncWorkOrderIds(new Set<Id>());

        OrderDiarySyncService.ServiceAppointmentRequest appointmentRequest =
            new OrderDiarySyncService.ServiceAppointmentRequest();
        OrderDiarySyncService.WorkOrderRequest workOrderRequest = new OrderDiarySyncService.WorkOrderRequest();
        OrderDiarySyncService.OpportunityWorkOrderRequest opportunityRequest =
            new OrderDiarySyncService.OpportunityWorkOrderRequest();
        OrderDiarySyncService.syncServiceAppointmentsInvocable(
            new List<OrderDiarySyncService.ServiceAppointmentRequest>{ appointmentRequest }
        );
        OrderDiarySyncService.syncWorkOrdersInvocable(
            new List<OrderDiarySyncService.WorkOrderRequest>{ workOrderRequest }
        );
        OrderDiarySyncService.syncOpportunityWorkOrdersInvocable(
            new List<OrderDiarySyncService.OpportunityWorkOrderRequest>{ opportunityRequest }
        );
    }

    @IsTest
    static void syncCreatesDraftOrderAndStampsDiaryFromEarliestStart() {
        Account accountRecord = new Account(Name = 'Order Diary Sync Account');
        insert accountRecord;
        WorkType workTypeRecord = TestDataFactory.createWorkType('Order Diary Sync Install', 2);

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Order Diary Sync WO',
            Status = 'New',
            AccountId = accountRecord.Id,
            WorkTypeId = workTypeRecord.Id
        );
        insert workOrderRecord;

        Datetime earliestStart = Datetime.newInstance(Date.today().addDays(5), Time.newInstance(8, 0, 0, 0));
        ServiceAppointment appointmentRecord = new ServiceAppointment(
            ParentRecordId = workOrderRecord.Id,
            Status = 'Scheduled',
            EarliestStartTime = earliestStart,
            DueDate = earliestStart.addDays(1),
            SchedStartTime = earliestStart,
            SchedEndTime = earliestStart.addHours(1),
            Subject = 'Order Diary Sync SA'
        );
        insert appointmentRecord;

        Test.startTest();
        OrderDiarySyncService.syncServiceAppointmentIds(new Set<Id>{ appointmentRecord.Id }, false);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Order WHERE Service_Appointment__c = :appointmentRecord.Id]
        );
        OrderDiarySyncService.syncServiceAppointmentIds(new Set<Id>{ appointmentRecord.Id }, true);
        OrderDiarySyncService.syncServiceAppointmentIds(new Set<Id>{ appointmentRecord.Id });
        OrderDiarySyncService.syncWorkOrderIds(new Set<Id>{ workOrderRecord.Id });
        Test.stopTest();

        Order syncedOrder = [
            SELECT Status, Billing_Diary_Status__c, Ready_For_Billing__c
            FROM Order
            WHERE Service_Appointment__c = :appointmentRecord.Id
            LIMIT 1
        ];
        System.assertEquals('Draft', syncedOrder.Status);
        System.assertEquals(OrderDiarySyncService.getForReviewStatusValue(), syncedOrder.Billing_Diary_Status__c);
        System.assertEquals(false, syncedOrder.Ready_For_Billing__c);
        System.assertNotEquals(null, OrderDiarySyncService.getNeedsReviewStatusValue());
        System.assertNotEquals(null, OrderDiarySyncService.getReviewedStatusValue());
    }
}
