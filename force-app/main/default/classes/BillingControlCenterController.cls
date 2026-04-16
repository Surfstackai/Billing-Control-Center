/**
 * Backward-compatible shim after class rename to BillingControl_Orders.
 * Keeps legacy Aura/LWC imports working while callers migrate.
 */
public with sharing class BillingControlCenterController {
    @AuraEnabled(cacheable=true)
    public static BillingControl_Orders.KpiWrapper getKpis() {
        return BillingControl_Orders.getKpis();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Orders.BucketSectionWrapper> getBucketWorkOrders() {
        return BillingControl_Orders.getBucketWorkOrders();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Orders.OrderRowWrapper> getOrders() {
        return BillingControl_Orders.getOrders();
    }
}