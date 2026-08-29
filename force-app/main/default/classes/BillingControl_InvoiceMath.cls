/**
 * Single authority for Invoice__c paid amount, balance, and status derived from payments.
 */
public inherited sharing class BillingControl_InvoiceMath {
    private static final String STATUS_VOID = 'Void';
    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_PAID = 'Paid';
    private static final String STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String STATUS_SENT = 'Sent';

    public static void recalculate(Set<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> paidByInvoiceId = new Map<Id, Decimal>();
        for (AggregateResult aggregateRow : [
            SELECT Invoice__c invoiceId, SUM(Amount_Received__c) paidAmount
            FROM Invoice_Payment__c
            WHERE Invoice__c IN :invoiceIds
            GROUP BY Invoice__c
        ]) {
            paidByInvoiceId.put(
                (Id) aggregateRow.get('invoiceId'),
                coalesceDecimal((Decimal) aggregateRow.get('paidAmount'))
            );
        }

        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        for (Invoice__c invoiceRecord : [
            SELECT Id, Total_Amount__c, Status__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]) {
            Decimal paidAmount = paidByInvoiceId.containsKey(invoiceRecord.Id)
                ? paidByInvoiceId.get(invoiceRecord.Id)
                : 0;
            Decimal totalAmount = invoiceRecord.Total_Amount__c;
            Decimal balanceDue = totalAmount == null ? null : totalAmount - paidAmount;
            String nextStatus = invoiceRecord.Status__c;

            if (invoiceRecord.Status__c != STATUS_VOID) {
                if (totalAmount == null || totalAmount == 0) {
                    nextStatus = STATUS_DRAFT;
                } else if (balanceDue <= 0) {
                    nextStatus = STATUS_PAID;
                } else if (paidAmount > 0) {
                    nextStatus = STATUS_PARTIALLY_PAID;
                } else {
                    nextStatus = STATUS_SENT;
                }
            }

            invoicesToUpdate.add(new Invoice__c(
                Id = invoiceRecord.Id,
                Amount_Paid__c = paidAmount,
                Balance_Due__c = balanceDue,
                Status__c = nextStatus
            ));
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }

    private static Decimal coalesceDecimal(Decimal value) {
        return value == null ? 0 : value;
    }
}
