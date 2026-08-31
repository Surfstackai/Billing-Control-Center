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

    public static Decimal paid(Decimal paidAmount) {
        return paidAmount == null ? 0 : paidAmount;
    }

    /**
     * Read-side remaining given a total and payments. Null total is treated as 0.
     * Does not replace {@link #recalculate} write semantics (null Total_Amount__c keeps null Balance_Due__c).
     */
    public static Decimal remaining(Decimal totalAmount, Decimal paidAmount) {
        Decimal total = totalAmount == null ? 0 : totalAmount;
        return total - paid(paidAmount);
    }

    public static Decimal remainingToInvoice(Decimal opportunityAmount, Decimal invoicedTotal) {
        if (opportunityAmount == null) {
            return 0;
        }
        Decimal remaining = opportunityAmount - (invoicedTotal == null ? 0 : invoicedTotal);
        return remaining < 0 ? 0 : remaining.setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal coalesceDecimal(Decimal value) {
        return value == null ? 0 : value;
    }
}
