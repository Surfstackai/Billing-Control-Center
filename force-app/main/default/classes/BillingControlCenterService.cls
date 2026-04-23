/**
 * Backward-compatible shim after class rename to BillingControl_Invoicing.
 * Keeps legacy Aura/LWC imports working while callers migrate.
 */
public with sharing class BillingControlCenterService {
    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.OpportunityWrapper> getReadyForBillingOpportunities() {
        return BillingControl_Invoicing.getReadyForBillingOpportunities();
    }

    @AuraEnabled
    public static List<BillingControl_Invoicing.OpportunityWrapper> getAwaitingBillingOpportunities() {
        return BillingControl_Invoicing.getAwaitingBillingOpportunities();
    }

    @AuraEnabled
    public static List<BillingControl_Invoicing.OpportunityWrapper> getOutstandingReceivableOpportunities() {
        return BillingControl_Invoicing.getOutstandingReceivableOpportunities();
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.OpportunityBillingMetricsWrapper getOpportunityBillingMetrics() {
        return BillingControl_Invoicing.getOpportunityBillingMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.BillingControlMetricsWrapper getServiceAppointmentBillingMetrics() {
        return BillingControl_Invoicing.getServiceAppointmentBillingMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper> getBillableServiceAppointmentGroups() {
        return BillingControl_Invoicing.getBillableServiceAppointmentGroups();
    }

    @AuraEnabled
    public static BillingControl_Invoicing.CompleteBillingResultWrapper completeServiceAppointmentBilling(
        List<Id> serviceAppointmentIds,
        Map<String, String> invoiceNumberByOpportunityId
    ) {
        return BillingControl_Invoicing.completeServiceAppointmentBilling(
            serviceAppointmentIds,
            invoiceNumberByOpportunityId
        );
    }

    @AuraEnabled
    public static BillingControl_Invoicing.BillingControlMetricsWrapper getBillingControlMetrics() {
        return BillingControl_Invoicing.getBillingControlMetrics();
    }

    @AuraEnabled
    public static BillingControl_Invoicing.PaymentReceiptResultWrapper postReceipt(BillingControl_Invoicing.PostReceiptInputWrapper input) {
        return BillingControl_Invoicing.postReceipt(input);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.CommissionMetricsWrapper getCommissionMetrics() {
        return BillingControl_Invoicing.getCommissionMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.SalespersonWrapper> getCommissionData(String subtabType) {
        return BillingControl_Invoicing.getCommissionData(subtabType);
    }

    @AuraEnabled
    public static void updateCommissionPaid(List<Id> commissionIds) {
        BillingControl_Invoicing.updateCommissionPaid(commissionIds);
    }

    @AuraEnabled
    public static BillingControl_Invoicing.CommissionResultWrapper createCommissionRecords(
        List<BillingControl_Invoicing.CommissionInputWrapper> inputs
    ) {
        return BillingControl_Invoicing.createCommissionRecords(inputs);
    }
}