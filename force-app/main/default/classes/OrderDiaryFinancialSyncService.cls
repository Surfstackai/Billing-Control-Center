public without sharing class OrderDiaryFinancialSyncService {
    private static final String ORDER_DIARY_STATUS_INVOICED = 'Invoiced';
    private static final String ORDER_DIARY_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String ORDER_DIARY_STATUS_PAID = 'Paid';

    private static String cachedInvoicedStatus;
    private static String cachedPartiallyPaidStatus;
    private static String cachedPaidStatus;

    public static void recalculateForOrderIds(Set<Id> orderIds) {
        recalculate(orderIds, new Set<Id>());
    }

    public static void recalculateForInvoiceIds(Set<Id> invoiceIds) {
        recalculate(new Set<Id>(), invoiceIds);
    }

    public static String getInvoicedStatusValue() {
        if (cachedInvoicedStatus == null) {
            cachedInvoicedStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_INVOICED, ORDER_DIARY_STATUS_PARTIALLY_PAID, ORDER_DIARY_STATUS_PAID }
            );
        }
        return cachedInvoicedStatus;
    }

    public static String getPartiallyPaidStatusValue() {
        if (cachedPartiallyPaidStatus == null) {
            cachedPartiallyPaidStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_PARTIALLY_PAID, ORDER_DIARY_STATUS_INVOICED, ORDER_DIARY_STATUS_PAID }
            );
        }
        return cachedPartiallyPaidStatus;
    }

    public static String getPaidStatusValue() {
        if (cachedPaidStatus == null) {
            cachedPaidStatus = preferredPicklistValue(
                Order.Billing_Diary_Status__c,
                new List<String>{ ORDER_DIARY_STATUS_PAID, ORDER_DIARY_STATUS_PARTIALLY_PAID, ORDER_DIARY_STATUS_INVOICED }
            );
        }
        return cachedPaidStatus;
    }

    private static void recalculate(Set<Id> seedOrderIds, Set<Id> seedInvoiceIds) {
        Set<Id> orderIds = seedOrderIds == null ? new Set<Id>() : new Set<Id>(seedOrderIds);
        Set<Id> invoiceIds = seedInvoiceIds == null ? new Set<Id>() : new Set<Id>(seedInvoiceIds);
        if (orderIds.isEmpty() && invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> invoicedAmountByOrderId = new Map<Id, Decimal>();
        Map<Id, Set<Id>> orderIdsByInvoiceId = new Map<Id, Set<Id>>();
        List<Invoice_Line__c> invoiceLines = [
            SELECT Id, Invoice__c, Billing_Order__c, Line_Total__c
            FROM Invoice_Line__c
            WHERE (Billing_Order__c IN :orderIds AND Billing_Order__c != null)
            OR (Invoice__c IN :invoiceIds AND Invoice__c != null)
        ];
        for (Invoice_Line__c invoiceLineRecord : invoiceLines) {
            if (invoiceLineRecord.Billing_Order__c != null) {
                orderIds.add(invoiceLineRecord.Billing_Order__c);
                Decimal currentInvoicedAmount = invoicedAmountByOrderId.containsKey(invoiceLineRecord.Billing_Order__c)
                    ? invoicedAmountByOrderId.get(invoiceLineRecord.Billing_Order__c)
                    : 0;
                invoicedAmountByOrderId.put(
                    invoiceLineRecord.Billing_Order__c,
                    currentInvoicedAmount + (invoiceLineRecord.Line_Total__c != null ? invoiceLineRecord.Line_Total__c : 0)
                );
            }
            if (invoiceLineRecord.Invoice__c != null && invoiceLineRecord.Billing_Order__c != null) {
                invoiceIds.add(invoiceLineRecord.Invoice__c);
                if (!orderIdsByInvoiceId.containsKey(invoiceLineRecord.Invoice__c)) {
                    orderIdsByInvoiceId.put(invoiceLineRecord.Invoice__c, new Set<Id>());
                }
                orderIdsByInvoiceId.get(invoiceLineRecord.Invoice__c).add(invoiceLineRecord.Billing_Order__c);
            }
        }

        Map<Id, Decimal> receivedAmountByOrderId = new Map<Id, Decimal>();
        if (!invoiceIds.isEmpty()) {
            for (Invoice_Payment__c paymentRecord : [
                SELECT Id, Invoice__c, Amount_Received__c
                FROM Invoice_Payment__c
                WHERE Invoice__c IN :invoiceIds
            ]) {
                Set<Id> linkedOrderIds = orderIdsByInvoiceId.get(paymentRecord.Invoice__c);
                if (linkedOrderIds == null || linkedOrderIds.size() != 1) {
                    continue;
                }
                for (Id linkedOrderId : linkedOrderIds) {
                    orderIds.add(linkedOrderId);
                    Decimal currentReceivedAmount = receivedAmountByOrderId.containsKey(linkedOrderId)
                        ? receivedAmountByOrderId.get(linkedOrderId)
                        : 0;
                    receivedAmountByOrderId.put(
                        linkedOrderId,
                        currentReceivedAmount + (paymentRecord.Amount_Received__c != null ? paymentRecord.Amount_Received__c : 0)
                    );
                }
            }
        }

        if (orderIds.isEmpty()) {
            return;
        }

        List<Order> ordersToUpdate = new List<Order>();
        for (Order orderRecord : [
            SELECT Id,
                Billing_Diary_Status__c,
                Review_Status__c,
                Billing_Hold_Reason__c,
                Service_Appointment__r.Status,
                Service_Appointment__r.ActualEndTime,
                Ready_For_Billing__c,
                Invoiced_Amount__c,
                Received_Amount__c
            FROM Order
            WHERE Id IN :orderIds
        ]) {
            Decimal safeInvoicedAmount = normalizeCurrency(invoicedAmountByOrderId.get(orderRecord.Id));
            Decimal safeReceivedAmount = normalizeCurrency(receivedAmountByOrderId.get(orderRecord.Id));

            Order updateRecord = new Order(
                Id = orderRecord.Id,
                Invoiced_Amount__c = safeInvoicedAmount,
                Received_Amount__c = safeReceivedAmount
            );

            if (safeInvoicedAmount > 0) {
                updateRecord.Billing_Diary_Status__c = safeReceivedAmount >= safeInvoicedAmount
                    ? getPaidStatusValue()
                    : (safeReceivedAmount > 0 ? getPartiallyPaidStatusValue() : getInvoicedStatusValue());
                updateRecord.Ready_For_Billing__c = false;
            } else {
                OrderDiarySyncService.OrderDiaryOperationalState operationalState = OrderDiarySyncService.deriveOperationalState(
                    orderRecord.Review_Status__c,
                    orderRecord.Billing_Hold_Reason__c,
                    orderRecord.Service_Appointment__r != null ? orderRecord.Service_Appointment__r.Status : null,
                    orderRecord.Service_Appointment__r != null ? orderRecord.Service_Appointment__r.ActualEndTime : null,
                    safeInvoicedAmount,
                    safeReceivedAmount
                );
                updateRecord.Billing_Diary_Status__c = operationalState.billingDiaryStatus;
                updateRecord.Ready_For_Billing__c = operationalState.readyForBilling;
                if (!String.isBlank(operationalState.reviewStatus)) {
                    updateRecord.Review_Status__c = operationalState.reviewStatus;
                }
            }

            if (
                hasValueChanged(orderRecord.Invoiced_Amount__c, updateRecord.Invoiced_Amount__c)
                || hasValueChanged(orderRecord.Received_Amount__c, updateRecord.Received_Amount__c)
                || orderRecord.Billing_Diary_Status__c != updateRecord.Billing_Diary_Status__c
                || orderRecord.Ready_For_Billing__c != updateRecord.Ready_For_Billing__c
                || (
                    !String.isBlank(updateRecord.Review_Status__c)
                    && orderRecord.Review_Status__c != updateRecord.Review_Status__c
                )
            ) {
                ordersToUpdate.add(updateRecord);
            }
        }

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }

    private static Decimal normalizeCurrency(Decimal value) {
        return value == null ? 0 : value.setScale(2);
    }

    private static Boolean hasValueChanged(Decimal currentValue, Decimal newValue) {
        return normalizeCurrency(currentValue) != normalizeCurrency(newValue);
    }

    private static String preferredPicklistValue(Schema.SObjectField fieldToken, List<String> preferredValues) {
        List<Schema.PicklistEntry> activeEntries = new List<Schema.PicklistEntry>();
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry != null && entry.isActive()) {
                activeEntries.add(entry);
            }
        }
        for (String preferredValue : preferredValues) {
            for (Schema.PicklistEntry entry : activeEntries) {
                if (normalizeValue(entry.getValue()) == normalizeValue(preferredValue)) {
                    return entry.getValue();
                }
            }
        }
        return activeEntries.isEmpty() ? null : activeEntries[0].getValue();
    }

    private static String normalizeValue(String value) {
        return String.isBlank(value) ? null : value.trim().toUpperCase();
    }
}