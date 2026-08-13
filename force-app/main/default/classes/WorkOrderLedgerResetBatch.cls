public without sharing class WorkOrderLedgerResetBatch implements Database.Batchable<SObject> {
    private Boolean runBackfillAfter;

    public WorkOrderLedgerResetBatch() {
        this(true);
    }

    public WorkOrderLedgerResetBatch(Boolean runBackfillAfter) {
        this.runBackfillAfter = runBackfillAfter;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Work_Order_Ledger__c
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        delete scope;
    }

    public void finish(Database.BatchableContext context) {
        if (runBackfillAfter == true) {
            Database.executeBatch(new WorkOrderLedgerBackfillBatch(), 20);
        }
    }
}
