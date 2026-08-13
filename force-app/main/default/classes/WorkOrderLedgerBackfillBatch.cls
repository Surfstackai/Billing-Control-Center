public without sharing class WorkOrderLedgerBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String MODE_OPEN = 'OPEN';
    public static final String MODE_DATE_RANGE = 'DATE_RANGE';
    public static final String MODE_IDS = 'IDS';

    private String mode;
    private Set<Id> workOrderIds;
    private Datetime rangeStart;
    private Datetime rangeEnd;
    @TestVisible
    private Integer processedCount = 0;

    public WorkOrderLedgerBackfillBatch() {
        this.mode = MODE_OPEN;
    }

    public WorkOrderLedgerBackfillBatch(Set<Id> scopedWorkOrderIds) {
        this.mode = MODE_IDS;
        this.workOrderIds = scopedWorkOrderIds == null ? new Set<Id>() : scopedWorkOrderIds;
    }

    public WorkOrderLedgerBackfillBatch(Datetime rangeStart, Datetime rangeEnd) {
        this.mode = MODE_DATE_RANGE;
        this.rangeStart = rangeStart;
        this.rangeEnd = rangeEnd;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Set<String> closedStatuses = WorkOrderLedgerService.getClosedWorkOrderStatusValues();
        if (mode == MODE_IDS) {
            return Database.getQueryLocator([
                SELECT Id
                FROM WorkOrder
                WHERE Id IN :workOrderIds
            ]);
        }
        if (mode == MODE_DATE_RANGE) {
            return Database.getQueryLocator([
                SELECT Id
                FROM WorkOrder
                WHERE CreatedDate >= :rangeStart
                AND CreatedDate <= :rangeEnd
            ]);
        }
        if (closedStatuses.isEmpty()) {
            return Database.getQueryLocator([
                SELECT Id
                FROM WorkOrder
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM WorkOrder
            WHERE Status NOT IN :closedStatuses
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> scopedIds = new Set<Id>();
        for (SObject record : scope) {
            scopedIds.add(record.Id);
        }
        WorkOrderLedgerService.backfillWorkOrders(scopedIds);
        processedCount += scopedIds.size();
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'Work Order Ledger backfill processed ' + processedCount + ' Work Orders.');
    }
}
