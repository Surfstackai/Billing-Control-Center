@IsTest
private class BillingControlCenterControllerTest {
    @IsTest
    static void testGetKpisDelegatesToBillingControlOrders() {
        Test.startTest();
        String controllerJson = JSON.serialize(BillingControlCenterController.getKpis());
        String directJson = JSON.serialize(BillingControl_Orders.getKpis());
        Test.stopTest();

        System.assertEquals(
            directJson,
            controllerJson,
            'BillingControlCenterController.getKpis should delegate to BillingControl_Orders.getKpis.'
        );
    }

    @IsTest
    static void testGetBucketWorkOrdersDelegatesToBillingControlOrders() {
        Test.startTest();
        String controllerJson = JSON.serialize(BillingControlCenterController.getBucketWorkOrders());
        String directJson = JSON.serialize(BillingControl_Orders.getBucketWorkOrders());
        Test.stopTest();

        System.assertEquals(
            directJson,
            controllerJson,
            'BillingControlCenterController.getBucketWorkOrders should delegate to BillingControl_Orders.getBucketWorkOrders.'
        );
    }

    @IsTest
    static void testGetOrdersDelegatesToBillingControlOrders() {
        Test.startTest();
        String controllerJson = JSON.serialize(BillingControlCenterController.getOrders());
        String directJson = JSON.serialize(BillingControl_Orders.getOrders());
        Test.stopTest();

        System.assertEquals(
            directJson,
            controllerJson,
            'BillingControlCenterController.getOrders should delegate to BillingControl_Orders.getOrders.'
        );
    }
}