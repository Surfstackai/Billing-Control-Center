/**
 * Interactive Complete Billing command. Groups selected appointments by attributed
 * Opportunity and calls BillingControl_InvoiceService for each invoice.
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
            FOR UPDATE
        ];

        Set<Id> requestedAppointmentIds = new Set<Id>(serviceAppointmentIds);
        Set<Id> lockedAppointmentIds = new Map<Id, ServiceAppointment>(lockedAppointments).keySet();
        Set<Id> billedAppointmentIds = BillingControl_BillingTruth.billedAppointmentIds(lockedAppointmentIds);
        List<String> ineligibleSelections = new List<String>();
        List<ServiceAppointment> appointmentsToBill = new List<ServiceAppointment>();
        for (Id requestedAppointmentId : requestedAppointmentIds) {
            if (!lockedAppointmentIds.contains(requestedAppointmentId)) {
                ineligibleSelections.add(String.valueOf(requestedAppointmentId));
            }
        }
        for (ServiceAppointment appointmentRecord : lockedAppointments) {
            if (
                appointmentRecord.Status != SERVICE_APPOINTMENT_STATUS_COMPLETED
                || billedAppointmentIds.contains(appointmentRecord.Id)
            ) {
                ineligibleSelections.add(String.valueOf(appointmentRecord.Id));
                continue;
            }
            appointmentsToBill.add(appointmentRecord);
        }
        if (!ineligibleSelections.isEmpty()) {
            throw BillingControl_Invoicing.buildHandledException(
                'Complete Billing requires selected Service Appointments to be completed and uninvoiced. Ineligible selections: '
                + String.join(ineligibleSelections, ', ')
                + '.'
            );
        }

        Map<Id, Id> workOrderIdByAppointmentId = BillingControl_Attribution.resolveWorkOrderIdsForAppointments(appointmentsToBill);
        Map<Id, Id> effectiveOpportunityByAppointmentId = resolveAttributedOpportunitiesForBilling(
            appointmentsToBill,
            workOrderIdByAppointmentId
        );
        Map<Id, List<ServiceAppointment>> appointmentsByOpportunityId = new Map<Id, List<ServiceAppointment>>();
        for (ServiceAppointment appointmentRecord : appointmentsToBill) {
            Id opportunityId = effectiveOpportunityByAppointmentId.get(appointmentRecord.Id);
            if (!appointmentsByOpportunityId.containsKey(opportunityId)) {
                appointmentsByOpportunityId.put(opportunityId, new List<ServiceAppointment>());
            }
            appointmentsByOpportunityId.get(opportunityId).add(appointmentRecord);
        }

        Set<Id> resolvedOpportunityIds = new Set<Id>(appointmentsByOpportunityId.keySet());
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, Amount
            FROM Opportunity
            WHERE Id IN :resolvedOpportunityIds
        ]);
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> financialsByOpportunityId =
            BillingControl_OpportunityFinancials.load(resolvedOpportunityIds);

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
            String uniquenessKey = invoiceNumber.toLowerCase();
            if (invoiceNumbersForUniqueness.contains(uniquenessKey)) {
                throw BillingControl_Invoicing.buildHandledException('Each invoice number in this batch must be unique.');
            }
            invoiceNumbersForUniqueness.add(uniquenessKey);
            invoiceNumberResolvedByOpportunityId.put(opportunityId, invoiceNumber);
        }

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
            BillingControl_OpportunityFinancials.Snapshot snapshot = financialsByOpportunityId.get(opportunityId);
            Decimal invoicedTotal = snapshot == null ? 0 : snapshot.invoicedTotal;
            Decimal invoiceTotal = opportunityAmount - invoicedTotal;
            if (invoiceTotal <= 0) {
                throw BillingControl_Invoicing.buildHandledException(
                    'Complete Billing cannot create additional invoice value for Opportunity '
                    + String.valueOf(opportunityId)
                    + ' because its current Opportunity.Amount has already been fully invoiced.'
                );
            }

            List<ServiceAppointment> groupedAppointments = appointmentsByOpportunityId.get(opportunityId);
            BillingControl_InvoiceService.InvoiceRequest invoiceRequest = new BillingControl_InvoiceService.InvoiceRequest();
            invoiceRequest.opportunityId = opportunityId;
            invoiceRequest.invoiceType = 'Balance';
            invoiceRequest.invoiceAmount = invoiceTotal;
            invoiceRequest.invoiceNumber = invoiceNumberResolvedByOpportunityId.get(opportunityId);
            invoiceRequest.serviceAppointmentIds = new List<Id>(new Map<Id, ServiceAppointment>(groupedAppointments).keySet());
            invoiceRequest.acceptFullRemaining = true;
            invoiceRequest.acceptVariance = false;
            invoiceRequest.amountPendingExternal = false;
            invoiceRequest.updateOperationalAttribution = false;
            invoiceRequest.amountSource = 'Derived';
            BillingControl_InvoiceService.InvoiceResult createdInvoice =
                BillingControl_InvoiceService.createInvoice(invoiceRequest);

            BillingControl_Invoicing.InvoiceGroupResultWrapper invoiceGroup = new BillingControl_Invoicing.InvoiceGroupResultWrapper();
            invoiceGroup.opportunityId = opportunityId;
            invoiceGroup.opportunityName = opportunityRecord.Name;
            invoiceGroup.invoiceNumber = createdInvoice.invoiceNumber;
            invoiceGroup.serviceAppointmentCount = groupedAppointments.size();
            result.invoiceGroups.add(invoiceGroup);
            result.serviceAppointmentsUpdated += groupedAppointments.size();
        }

        result.invoicesCreated = result.invoiceGroups.size();
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
        Map<Id, List<Opportunity_WorkOrder__c>> junctionsByWorkOrderId = BillingControl_Attribution.queryJunctionsByWorkOrderId(workOrderIds);
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
