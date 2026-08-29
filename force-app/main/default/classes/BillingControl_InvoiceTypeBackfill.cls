/**
 * One-time Phase 2 data fill: existing Invoice__c rows receive Balance / Derived.
 * New invoices pick those up from field defaults; this method covers pre-field records.
 */
public inherited sharing class BillingControl_InvoiceTypeBackfill {
    public static final String TYPE_BALANCE = 'Balance';
    public static final String SOURCE_DERIVED = 'Derived';

    public static Integer backfillExistingInvoices() {
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, Invoice_Type__c, Amount_Source__c
            FROM Invoice__c
            WHERE Invoice_Type__c = NULL
            OR Amount_Source__c = NULL
        ];
        for (Invoice__c invoiceRecord : invoicesToUpdate) {
            if (String.isBlank(invoiceRecord.Invoice_Type__c)) {
                invoiceRecord.Invoice_Type__c = TYPE_BALANCE;
            }
            if (String.isBlank(invoiceRecord.Amount_Source__c)) {
                invoiceRecord.Amount_Source__c = SOURCE_DERIVED;
            }
        }
        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
        return invoicesToUpdate.size();
    }
}
