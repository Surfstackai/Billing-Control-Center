/**
 * Compute-on-read Opportunity invoice aggregates. Excludes void invoices and
 * pending-external headers with a null total from invoiced / AR outstanding.
 */
public inherited sharing class BillingControl_OpportunityFinancials {
    private static final String INVOICE_STATUS_VOID = 'Void';

    public class Snapshot {
        public Id opportunityId;
        public Decimal invoicedTotal;
        public Decimal paidTotal;
        public Decimal outstanding;
        public Boolean paidInFull;
        public Integer invoiceCount;
    }

    public static Map<Id, Snapshot> load(Set<Id> opportunityIds) {
        Map<Id, Snapshot> snapshotByOpportunityId = new Map<Id, Snapshot>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return snapshotByOpportunityId;
        }

        for (Id opportunityId : opportunityIds) {
            snapshotByOpportunityId.put(opportunityId, emptySnapshot(opportunityId));
        }

        for (AggregateResult aggregateRow : [
            SELECT Opportunity__c opportunityId,
                   SUM(Total_Amount__c) invoicedTotal,
                   SUM(Amount_Paid__c) paidTotal,
                   COUNT(Id) invoiceCount
            FROM Invoice__c
            WHERE Opportunity__c IN :opportunityIds
            AND Status__c != :INVOICE_STATUS_VOID
            AND Total_Amount__c != NULL
            GROUP BY Opportunity__c
        ]) {
            Id opportunityId = (Id) aggregateRow.get('opportunityId');
            Snapshot snapshot = snapshotByOpportunityId.get(opportunityId);
            if (snapshot == null) {
                snapshot = emptySnapshot(opportunityId);
                snapshotByOpportunityId.put(opportunityId, snapshot);
            }
            snapshot.invoicedTotal = coalesceDecimal((Decimal) aggregateRow.get('invoicedTotal'));
            snapshot.paidTotal = coalesceDecimal((Decimal) aggregateRow.get('paidTotal'));
            snapshot.outstanding = snapshot.invoicedTotal - snapshot.paidTotal;
            snapshot.invoiceCount = integerValue(aggregateRow.get('invoiceCount'));
            snapshot.paidInFull = false;
        }

        for (Opportunity opportunityRecord : [
            SELECT Id, Amount
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]) {
            Snapshot snapshot = snapshotByOpportunityId.get(opportunityRecord.Id);
            if (snapshot == null) {
                continue;
            }
            Decimal quotedAmount = coalesceDecimal(opportunityRecord.Amount);
            snapshot.paidInFull =
                snapshot.invoicedTotal > 0
                && snapshot.outstanding <= 0
                && quotedAmount > 0
                && snapshot.invoicedTotal >= quotedAmount;
        }

        applyUnbilledCompletedWorkGate(snapshotByOpportunityId);
        return snapshotByOpportunityId;
    }

    private static void applyUnbilledCompletedWorkGate(Map<Id, Snapshot> snapshotByOpportunityId) {
        Set<Id> opportunityIds = snapshotByOpportunityId.keySet();
        if (opportunityIds.isEmpty()) {
            return;
        }
        List<ServiceAppointment> completedAppointments = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Status = 'Completed'
            AND Opportunity__c IN :opportunityIds
        ];
        if (completedAppointments.isEmpty()) {
            return;
        }
        Set<Id> billedIds = BillingControl_BillingTruth.billedAppointmentIds(
            new Map<Id, ServiceAppointment>(completedAppointments).keySet()
        );
        Set<Id> opportunityIdsWithUnbilledWork = new Set<Id>();
        for (ServiceAppointment appointmentRecord : completedAppointments) {
            if (!billedIds.contains(appointmentRecord.Id) && appointmentRecord.Opportunity__c != null) {
                opportunityIdsWithUnbilledWork.add(appointmentRecord.Opportunity__c);
            }
        }
        for (Id opportunityId : opportunityIdsWithUnbilledWork) {
            Snapshot snapshot = snapshotByOpportunityId.get(opportunityId);
            if (snapshot != null) {
                snapshot.paidInFull = false;
            }
        }
    }

    private static Snapshot emptySnapshot(Id opportunityId) {
        Snapshot snapshot = new Snapshot();
        snapshot.opportunityId = opportunityId;
        snapshot.invoicedTotal = 0;
        snapshot.paidTotal = 0;
        snapshot.outstanding = 0;
        snapshot.paidInFull = false;
        snapshot.invoiceCount = 0;
        return snapshot;
    }

    private static Decimal coalesceDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Integer integerValue(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        return ((Decimal) value).intValue();
    }
}
