@IsTest
private class BillingControlCenterControllerShimTest {
    @IsTest
    static void delegatesToRenamedControllerMethods() {
        Test.startTest();
        BillingControl_Orders.KpiWrapper kpis = BillingControlCenterController.getKpis();
        List<BillingControl_Orders.BucketSectionWrapper> buckets = BillingControlCenterController.getBucketWorkOrders();
        List<BillingControl_Orders.OrderRowWrapper> orders = BillingControlCenterController.getOrders();
        Test.stopTest();

        System.assert(kpis != null, 'KPI wrapper should be returned.');
        System.assert(buckets != null, 'Bucket rows should be returned.');
        System.assert(orders != null, 'Order rows should be returned.');
    }
}