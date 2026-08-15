/**
 * Pure Invoice__c / Invoice_Line__c record builders. Callers own DML, stamping, and status policy.
 */
public inherited sharing class BillingControl_InvoiceRecordFactory {
    private static final String INVOICE_STATUS_SENT = 'Sent';

    public static Invoice__c buildSentInvoiceHeader(
        String invoiceNumber,
        Id opportunityId,
        Id accountId,
        Decimal totalAmount,
        Date invoiceDate
    ) {
        Date effectiveInvoiceDate = invoiceDate != null ? invoiceDate : Date.today();
        Decimal amount = totalAmount != null ? totalAmount : 0;
        return new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Status__c = INVOICE_STATUS_SENT,
            Invoice_Date__c = effectiveInvoiceDate,
            Due_Date__c = effectiveInvoiceDate.addDays(30),
            Subtotal__c = amount,
            Tax_Amount__c = 0,
            Total_Amount__c = amount,
            Amount_Paid__c = 0,
            Balance_Due__c = amount
        );
    }

    public static Invoice_Line__c buildServiceAppointmentInvoiceLine(
        Id invoiceId,
        Id serviceAppointmentId,
        Id opportunityId,
        Id workOrderId,
        Decimal lineAmount
    ) {
        return new Invoice_Line__c(
            Invoice__c = invoiceId,
            Service_Appointment__c = serviceAppointmentId,
            Opportunity__c = opportunityId,
            Work_Order__c = workOrderId,
            Description__c = 'Service Appointment ' + String.valueOf(serviceAppointmentId),
            Quantity__c = 1,
            Unit_Price__c = lineAmount,
            Line_Total__c = lineAmount
        );
    }
}
