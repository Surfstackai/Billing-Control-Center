@IsTest
private class BillingControlCenterServiceShimTest {
    @IsTest
    static void delegatesToRenamedServiceMethods() {
        Test.startTest();
        List<BillingControl_Invoicing.OpportunityWrapper> ready = BillingControlCenterService.getReadyForBillingOpportunities();
        List<BillingControl_Invoicing.OpportunityWrapper> awaiting = BillingControlCenterService.getAwaitingBillingOpportunities();
        List<BillingControl_Invoicing.OpportunityWrapper> outstanding = BillingControlCenterService.getOutstandingReceivableOpportunities();
        BillingControl_Invoicing.OpportunityBillingMetricsWrapper opportunityMetrics = BillingControlCenterService.getOpportunityBillingMetrics();
        BillingControl_Invoicing.BillingControlMetricsWrapper saMetrics = BillingControlCenterService.getServiceAppointmentBillingMetrics();
        List<BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper> groups = BillingControlCenterService.getBillableServiceAppointmentGroups();
        BillingControl_Invoicing.CompleteBillingResultWrapper completeResult = BillingControlCenterService.completeServiceAppointmentBilling(
            new List<Id>(),
            null
        );
        BillingControl_Invoicing.BillingControlMetricsWrapper billingMetrics = BillingControlCenterService.getBillingControlMetrics();
        BillingControl_Invoicing.CommissionMetricsWrapper commissionMetrics = BillingControlCenterService.getCommissionMetrics();
        List<BillingControl_Invoicing.SalespersonWrapper> commissionData = BillingControlCenterService.getCommissionData('earned');
        BillingControlCenterService.updateCommissionPaid(new List<Id>());
        BillingControl_Invoicing.CommissionResultWrapper commissionResult = BillingControlCenterService.createCommissionRecords(
            new List<BillingControl_Invoicing.CommissionInputWrapper>()
        );

        Boolean threwExpected = false;
        try {
            BillingControlCenterService.postReceipt(null);
        } catch (Exception expectedException) {
            threwExpected = true;
        }
        Test.stopTest();

        System.assertNotEquals(null, ready, 'Ready list should be returned.');
        System.assertNotEquals(null, awaiting, 'Awaiting list should be returned.');
        System.assertNotEquals(null, outstanding, 'Outstanding list should be returned.');
        System.assertNotEquals(null, opportunityMetrics, 'Opportunity metrics should be returned.');
        System.assertNotEquals(null, saMetrics, 'Service appointment metrics should be returned.');
        System.assertNotEquals(null, groups, 'Service appointment groups should be returned.');
        System.assertNotEquals(null, completeResult, 'Complete billing result should be returned.');
        System.assertNotEquals(null, billingMetrics, 'Billing metrics should be returned.');
        System.assertNotEquals(null, commissionMetrics, 'Commission metrics should be returned.');
        System.assertNotEquals(null, commissionData, 'Commission data should be returned.');
        System.assertNotEquals(null, commissionResult, 'Commission result should be returned.');
        System.assertEquals(true, threwExpected, 'postReceipt(null) should throw validation error.');
    }
}