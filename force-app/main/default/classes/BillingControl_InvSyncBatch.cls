/**
 * Date/owner-scoped INV-Sync backfill. Processes completed Service Appointments whose
 * coalesced SA/WO invoice number contains inv or inspection and creates Invoice__c rows
 * without writing Order.
 */
public with sharing class BillingControl_InvSyncBatch implements Database.Batchable<ServiceAppointment>, Database.Stateful {
    private BillingControl_BillingFilters.BillingDateFilterDTO dateFilter;
    private String opportunityOwnerId;

    public BillingControl_InvSyncBatch(
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        this.dateFilter = dateFilter;
        this.opportunityOwnerId = opportunityOwnerId;
    }

    public Iterable<ServiceAppointment> start(Database.BatchableContext context) {
        return BillingControl_InvSync.queryInvSyncCandidateAppointments(dateFilter);
    }

    public void execute(Database.BatchableContext context, List<ServiceAppointment> scope) {
        BillingControl_InvSync.processInvSyncAppointments(scope, opportunityOwnerId);
    }

    public void finish(Database.BatchableContext context) {
    }
}
