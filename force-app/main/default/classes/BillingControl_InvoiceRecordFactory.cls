/**
 * Pure Invoice__c / Invoice_Line__c record builders. Callers own DML, stamping, and status policy.
 */
public inherited sharing class BillingControl_InvoiceRecordFactory {
    private static final String INVOICE_STATUS_SENT = 'Sent';
    private static final String INVOICE_STATUS_DRAFT = 'Draft';
    private static final String TYPE_BALANCE = 'Balance';
    private static final String SOURCE_DERIVED = 'Derived';

    public static Invoice__c buildSentInvoiceHeader(
        String invoiceNumber,
        Id opportunityId,
        Id accountId,
        Decimal totalAmount,
        Date invoiceDate
    ) {
        return buildTypedInvoiceHeader(
            invoiceNumber,
            opportunityId,
            accountId,
            totalAmount,
            invoiceDate,
            null,
            TYPE_BALANCE,
            SOURCE_DERIVED
        );
    }

    public static Invoice__c buildTypedInvoiceHeader(
        String invoiceNumber,
        Id opportunityId,
        Id accountId,
        Decimal totalAmount,
        Date invoiceDate,
        Date dueDate,
        String invoiceType,
        String amountSource
    ) {
        Date effectiveInvoiceDate = invoiceDate != null ? invoiceDate : Date.today();
        Date effectiveDueDate = dueDate != null ? dueDate : effectiveInvoiceDate.addDays(30);
        Boolean pendingExternal = totalAmount == null;
        Decimal amount = pendingExternal ? null : totalAmount;
        return new Invoice__c(
            Invoice_Number__c = invoiceNumber,
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Status__c = pendingExternal ? INVOICE_STATUS_DRAFT : INVOICE_STATUS_SENT,
            Invoice_Date__c = effectiveInvoiceDate,
            Due_Date__c = effectiveDueDate,
            Subtotal__c = amount,
            Tax_Amount__c = pendingExternal ? null : 0,
            Total_Amount__c = amount,
            Amount_Paid__c = 0,
            Balance_Due__c = amount,
            Invoice_Type__c = invoiceType,
            Amount_Source__c = amountSource
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

    public static Invoice_Line__c buildDescriptiveInvoiceLine(
        Id invoiceId,
        Id opportunityId,
        Id workOrderId,
        String description,
        Decimal lineAmount
    ) {
        return new Invoice_Line__c(
            Invoice__c = invoiceId,
            Opportunity__c = opportunityId,
            Work_Order__c = workOrderId,
            Description__c = description,
            Quantity__c = 1,
            Unit_Price__c = lineAmount,
            Line_Total__c = lineAmount
        );
    }
}
