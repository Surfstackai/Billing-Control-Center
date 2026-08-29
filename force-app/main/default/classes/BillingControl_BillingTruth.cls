/**
 * Authoritative billed-or-not check: a Service Appointment is billed when a line
 * links it to a non-void Invoice__c. Text fields are never consulted.
 */
public inherited sharing class BillingControl_BillingTruth {
    private static final String INVOICE_STATUS_VOID = 'Void';

    public static Set<Id> billedAppointmentIds(Set<Id> appointmentIds) {
        Set<Id> billedIds = new Set<Id>();
        if (appointmentIds == null || appointmentIds.isEmpty()) {
            return billedIds;
        }

        for (Invoice_Line__c invoiceLineRecord : [
            SELECT Service_Appointment__c
            FROM Invoice_Line__c
            WHERE Service_Appointment__c IN :appointmentIds
            AND Invoice__r.Status__c != :INVOICE_STATUS_VOID
        ]) {
            if (invoiceLineRecord.Service_Appointment__c != null) {
                billedIds.add(invoiceLineRecord.Service_Appointment__c);
            }
        }
        return billedIds;
    }
}
