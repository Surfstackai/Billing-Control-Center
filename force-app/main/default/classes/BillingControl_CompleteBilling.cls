/**
 * Interactive Complete Billing command. Fail-fast validation stays in this class.
 */
public with sharing class BillingControl_CompleteBilling {
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';

    public static BillingControl_Invoicing.CompleteBillingResultWrapper completeServiceAppointmentBilling(
        List<Id> serviceAppointmentIds,
        Map<String, String> invoiceNumberByOpportunityId
    ) {
        BillingControl_Invoicing.CompleteBillingResultWrapper result = new BillingControl_Invoicing.CompleteBillingResultWrapper();
        result.invoicesCreated = 0;
        result.serviceAppointmentsUpdated = 0;
        result.invoiceGroups = new List<BillingControl_Invoicing.InvoiceGroupResultWrapper>();

        if (serviceAppointmentIds == null || serviceAppointmentIds.isEmpty()) {
            return result;
        }

        List<ServiceAppointment> lockedAppointments = [
            SELECT Id,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.AccountId,
                Opportunity__r.Billing_Status__c,
                ParentRecordId,
                Invoice_Number__c,
                Status
            FROM ServiceAppointment
            WHERE Id IN :serviceAppointmentIds
            AND Status = :SERVICE_APPOINTMENT_STATUS_COMPLETED
            AND Invoice_Number__c = NULL
            FOR UPDATE
        ];

        Set<Id> requestedAppointmentIds = new Set<Id>(serviceAppointmentIds);
        Set<Id> lockedAppointmentIds = new Map<Id, ServiceAppointment>(lockedAppointments).keySet();
        if (lockedAppointmentIds.size() != requestedAppointmentIds.size()) {
            List<String> ineligibleSelections = new List<String>();
            for (Id requestedAppointmentId : requestedAppointmentIds) {
                if (!lockedAppointmentIds.contains(requestedAppointmentId)) {
                    ineligibleSelections.add(String.valueOf(requestedAppointmentId));
                }
            }
            throw BillingControl_Invoicing.buildHandledException(
                'Complete Billing requires selected Service Appointments to be completed and uninvoiced. Ineligible selections: '
                + String.join(ineligibleSelections, ', ')
                + '.'
            );
        }

        List<ServiceAppointment> appointmentsToBill = new List<ServiceAppointment>(lockedAppointments);
        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(appointmentsToBill);
        Map<Id, Id> effectiveOpportunityByAppointmentId = resolveAttributedOpportunitiesForBilling(
            appointmentsToBill,
            workOrderIdByAppointmentId
        );
        Map<Id, List<ServiceAppointment>> appointmentsByOpportunityId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointment : appointmentsToBill) {
            Id opportunityId = effectiveOpportunityByAppointmentId.get(appointment.Id);
            if (!appointmentsByOpportunityId.containsKey(opportunityId)) {
                appointmentsByOpportunityId.put(opportunityId, new List<ServiceAppointment>());
            }
            appointmentsByOpportunityId.get(opportunityId).add(appointment);
        }

        Set<Id> resolvedOpportunityIds = new Set<Id>(appointmentsByOpportunityId.keySet());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, Billing_Status__c, AccountId, Amount
            FROM Opportunity
            WHERE Id IN :resolvedOpportunityIds
            FOR UPDATE
        ]);

        Map<Id, Decimal> historicalInvoiceTotalByOpportunityId = BillingControl_Invoicing.queryHistoricalInvoiceTotalByOpportunityId(
            resolvedOpportunityIds
        );
        Map<Id, Decimal> invoiceTotalByOpportunityId = new Map<Id, Decimal>();
        Map<Id, Decimal> invoiceLineAmountByAppointmentId = new Map<Id, Decimal>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            Decimal opportunityAmount = opportunityRecord != null ? opportunityRecord.Amount : null;
            if (opportunityAmount == null || opportunityAmount <= 0) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Complete Billing requires Opportunity.Amount greater than 0 for Opportunity '
                    + String.valueOf(opportunityId)
                    + '.'
                );
            }

            Decimal historicalInvoiceTotal = historicalInvoiceTotalByOpportunityId.containsKey(opportunityId)
                ? historicalInvoiceTotalByOpportunityId.get(opportunityId)
                : 0;
            Decimal invoiceTotal = opportunityAmount - historicalInvoiceTotal;
            if (invoiceTotal <= 0) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Complete Billing cannot create additional invoice value for Opportunity '
                    + String.valueOf(opportunityId)
                    + ' because its current Opportunity.Amount has already been fully invoiced.'
                );
            }
            invoiceTotalByOpportunityId.put(opportunityId, invoiceTotal);
            invoiceLineAmountByAppointmentId.putAll(
                BillingControl_Invoicing.allocateInvoiceTotalAcrossAppointments(invoiceTotal, appointmentsByOpportunityId.get(opportunityId))
            );
        }

        Integer invoiceSequence = 1;
        Map<Id, String> invoiceNumberResolvedByOpportunityId = new Map<Id, String>();
        Set<String> invoiceNumbersForUniqueness = new Set<String>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            String invoiceNumber = resolveInvoiceNumberForBilling(
                opportunityId,
                invoiceNumberByOpportunityId,
                invoiceSequence
            );
            invoiceSequence++;

            if (invoiceNumber.length() > 80) {
                throw BillingControl_Invoicing.buildHandledException('Invoice number must be 80 characters or fewer.');
            }
            if (invoiceNumbersForUniqueness.contains(invoiceNumber)) {
                throw BillingControl_Invoicing.buildHandledException('Each invoice number in this batch must be unique.');
            }
            invoiceNumbersForUniqueness.add(invoiceNumber);
            invoiceNumberResolvedByOpportunityId.put(opportunityId, invoiceNumber);
        }

        if (!invoiceNumbersForUniqueness.isEmpty()) {
            Integer existingInvoiceCount = [
                SELECT COUNT()
                FROM Invoice__c
                WHERE Invoice_Number__c IN :invoiceNumbersForUniqueness
            ];
            if (existingInvoiceCount > 0) {
                throw BillingControl_Invoicing.buildHandledException(
                    'One or more invoice numbers are already used on another invoice. Enter a different number.'
                );
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        Map<Id, Invoice__c> invoiceByOpportunityId = new Map<Id, Invoice__c>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            String invoiceNumber = invoiceNumberResolvedByOpportunityId.get(opportunityId);
            Decimal invoiceTotal = invoiceTotalByOpportunityId.get(opportunityId);
            List<ServiceAppointment> groupedAppointments = appointmentsByOpportunityId.get(opportunityId);

            Opportunity headerOpportunity = opportunityById.get(opportunityId);
            Invoice__c invoiceRecord = BillingControl_InvoiceRecordFactory.buildSentInvoiceHeader(
                invoiceNumber,
                opportunityId,
                headerOpportunity != null ? headerOpportunity.AccountId : null,
                invoiceTotal,
                Date.today()
            );
            invoicesToInsert.add(invoiceRecord);
            invoiceByOpportunityId.put(opportunityId, invoiceRecord);

            BillingControl_Invoicing.InvoiceGroupResultWrapper invoiceGroup = new BillingControl_Invoicing.InvoiceGroupResultWrapper();
            invoiceGroup.opportunityId = opportunityId;
            invoiceGroup.opportunityName = headerOpportunity != null ? headerOpportunity.Name : null;
            invoiceGroup.invoiceNumber = invoiceNumber;
            invoiceGroup.serviceAppointmentCount = groupedAppointments.size();
            result.invoiceGroups.add(invoiceGroup);
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }

        List<Invoice_Line__c> invoiceLinesToInsert = new List<Invoice_Line__c>();
        List<ServiceAppointment> serviceAppointmentsToUpdate = new List<ServiceAppointment>();
        for (Id opportunityId : appointmentsByOpportunityId.keySet()) {
            Invoice__c invoiceRecord = invoiceByOpportunityId.get(opportunityId);
            if (invoiceRecord == null || invoiceRecord.Id == null) {
                continue;
            }

            for (ServiceAppointment appointment : appointmentsByOpportunityId.get(opportunityId)) {
                Decimal invoiceLineAmount = invoiceLineAmountByAppointmentId.get(appointment.Id);
                invoiceLinesToInsert.add(
                    BillingControl_InvoiceRecordFactory.buildServiceAppointmentInvoiceLine(
                        invoiceRecord.Id,
                        appointment.Id,
                        opportunityId,
                        workOrderIdByAppointmentId.get(appointment.Id),
                        invoiceLineAmount
                    )
                );

                appointment.Invoice_Number__c = invoiceRecord.Invoice_Number__c;
                if (appointment.Opportunity__c == null) {
                    appointment.Opportunity__c = effectiveOpportunityByAppointmentId.get(appointment.Id);
                }
                serviceAppointmentsToUpdate.add(appointment);
            }
        }

        if (!invoiceLinesToInsert.isEmpty()) {
            insert invoiceLinesToInsert;
        }

        if (!serviceAppointmentsToUpdate.isEmpty()) {
            update serviceAppointmentsToUpdate;
        }

        Set<Id> opportunityIdsToUpdate = new Set<Id>();
        for (ServiceAppointment appointmentRecord : serviceAppointmentsToUpdate) {
            Id effectiveOpportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            if (effectiveOpportunityId != null) {
                opportunityIdsToUpdate.add(effectiveOpportunityId);
            }
        }

        String billedStatusForUpdate = BillingControl_Invoicing.getOutstandingReceivableStatusForUpdate();
        if (!opportunityIdsToUpdate.isEmpty()) {
            List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
            for (Opportunity opportunityRecord : [
                SELECT Id, Billing_Status__c
                FROM Opportunity
                WHERE Id IN :opportunityIdsToUpdate
            ]) {
                if (opportunityRecord.Billing_Status__c == billedStatusForUpdate) {
                    continue;
                }
                opportunitiesToUpdate.add(new Opportunity(
                    Id = opportunityRecord.Id,
                    Billing_Status__c = billedStatusForUpdate
                ));
            }
            if (!opportunitiesToUpdate.isEmpty()) {
                update opportunitiesToUpdate;
            }
        }

        result.invoicesCreated = result.invoiceGroups.size();
        result.serviceAppointmentsUpdated = serviceAppointmentsToUpdate.size();
        return result;
    }

    public static Map<Id, Id> resolveAttributedOpportunitiesForBilling(
        List<ServiceAppointment> appointmentsToBill,
        Map<Id, Id> workOrderIdByAppointmentId
    ) {
        Map<Id, Id> opportunityIdByAppointmentId = new Map<Id, Id>();
        if (appointmentsToBill == null || appointmentsToBill.isEmpty()) {
            return opportunityIdByAppointmentId;
        }

        Set<Id> workOrderIds = new Set<Id>(workOrderIdByAppointmentId.values());
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = BillingControl_Invoicing.queryJunctionsByWorkOrderId(workOrderIds);
        for (ServiceAppointment appointmentRecord : appointmentsToBill) {
            Id workOrderId = workOrderIdByAppointmentId.get(appointmentRecord.Id);
            Id opportunityId = BillingControl_Attribution.resolveAttributedOpportunityId(
                appointmentRecord,
                junctionsByWorkOrderId.get(workOrderId)
            );
            if (opportunityId == null) {
                Integer junctionCount = 0;
                List<Opportunity_WorkOrder__c> junctions = junctionsByWorkOrderId.get(workOrderId);
                if (junctions != null) {
                    Set<Id> uniqueOpportunityIds = new Set<Id>();
                    for (Opportunity_WorkOrder__c junctionRecord : junctions) {
                        if (junctionRecord.Opportunity__c != null) {
                            uniqueOpportunityIds.add(junctionRecord.Opportunity__c);
                        }
                    }
                    junctionCount = uniqueOpportunityIds.size();
                }
                if (junctionCount > 1) {
                    throw BillingControl_Invoicing.buildHandledException(
                        'Complete Billing cannot attribute Service Appointment '
                        + String.valueOf(appointmentRecord.Id)
                        + ' because the Work Order has multiple Opportunities and the appointment has no Opportunity.'
                    );
                }
                throw BillingControl_Invoicing.buildHandledException(
                    'Complete Billing requires an attributed Opportunity for Service Appointment '
                    + String.valueOf(appointmentRecord.Id)
                    + '.'
                );
            }
            opportunityIdByAppointmentId.put(appointmentRecord.Id, opportunityId);
        }
        return opportunityIdByAppointmentId;
    }

    public static String resolveInvoiceNumberForBilling(
        Id opportunityId,
        Map<String, String> invoiceNumberByOpportunityId,
        Integer sequenceForAuto
    ) {
        if (invoiceNumberByOpportunityId != null) {
            String explicit = invoiceNumberByOpportunityId.get(String.valueOf(opportunityId));
            if (!String.isBlank(explicit)) {
                return explicit.trim();
            }
        }
        return buildInvoiceNumber(opportunityId, sequenceForAuto);
    }

    public static String buildInvoiceNumber(Id opportunityId, Integer sequence) {
        String opportunityKey = String.valueOf(opportunityId);
        if (opportunityKey.length() > 5) {
            opportunityKey = opportunityKey.substring(opportunityKey.length() - 5, opportunityKey.length());
        }
        String sequenceValue = String.valueOf(sequence).leftPad(2, '0');
        return 'INV-' + Datetime.now().formatGMT('yyyyMMdd') + '-' + opportunityKey + '-' + sequenceValue;
    }

}
