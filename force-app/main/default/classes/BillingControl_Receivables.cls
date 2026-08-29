/**
 * Receivables, receipts, and commission commands for Billing Control Center.
 */
public with sharing class BillingControl_Receivables {
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';
    private static final String OUTSTANDING_RECEIVABLE = 'Billed (Outstanding Receivable)';
    private static final String OUTSTANDING_RECEIVABLES = 'Billed (Outstanding Receivables)';
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final String KPI_CATEGORY_REVENUE_UNDER_COLLECTION = 'REVENUE_UNDER_COLLECTION';
    private static final String KPI_CATEGORY_COMMISSION_EARNED = 'COMMISSION_EARNED';
    private static final String KPI_CATEGORY_COMMISSION_PAYABLE = 'COMMISSION_PAYABLE';
    private static final String KPI_LABEL_REVENUE_UNDER_COLLECTION = 'Receivables Outstanding';
    private static final String KPI_LABEL_COMMISSION_EARNED = 'Commission Accrued';
    private static final String KPI_LABEL_COMMISSION_PAYABLE = 'Commission Payable';
    private static final String INVOICE_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String INVOICE_STATUS_PAID = 'Paid';
    private static final String INVOICE_STATUS_VOID = 'Void';

    public static BillingControl_Invoicing.PaymentReceiptResultWrapper postReceipt(BillingControl_Invoicing.PostReceiptInputWrapper input) {
        if (input == null || input.opportunityId == null) {
            throw new AuraHandledException('A valid opportunity is required.');
        }
        if (input.amountReceived == null || input.amountReceived <= 0) {
            throw new AuraHandledException('Payment amount must be greater than 0.');
        }
        if (input.paymentDate == null) {
            throw new AuraHandledException('Payment date is required.');
        }
        if (String.isBlank(input.paymentMethod)) {
            throw new AuraHandledException('Payment method is required.');
        }
        if (String.isBlank(input.referenceNumber)) {
            throw new AuraHandledException('Reference number is required.');
        }

        Opportunity opportunityRecord = [
            SELECT Id, Billing_Status__c, AccountId
            FROM Opportunity
            WHERE Id = :input.opportunityId
            LIMIT 1
            FOR UPDATE
        ];

        Invoice__c invoiceRecord = resolveInvoiceForReceipt(opportunityRecord.Id, input.invoiceId);
        return applyReceipt(opportunityRecord, invoiceRecord, input);
    }

    @AuraEnabled
    public static BillingControl_Invoicing.PaymentReceiptResultWrapper postInvoiceReceipt(
        Id opportunityId,
        Id invoiceId,
        Decimal amountReceived,
        Date paymentDate,
        String paymentMethod,
        String referenceNumber
    ) {
        BillingControl_Invoicing.PostReceiptInputWrapper input = new BillingControl_Invoicing.PostReceiptInputWrapper();
        input.opportunityId = opportunityId;
        input.amountReceived = amountReceived;
        input.paymentDate = paymentDate;
        input.paymentMethod = paymentMethod;
        input.referenceNumber = referenceNumber;

        if (input.opportunityId == null) {
            throw new AuraHandledException('A valid opportunity is required.');
        }
        if (input.amountReceived == null || input.amountReceived <= 0) {
            throw new AuraHandledException('Payment amount must be greater than 0.');
        }
        if (input.paymentDate == null) {
            throw new AuraHandledException('Payment date is required.');
        }
        if (String.isBlank(input.paymentMethod)) {
            throw new AuraHandledException('Payment method is required.');
        }
        if (String.isBlank(input.referenceNumber)) {
            throw new AuraHandledException('Reference number is required.');
        }

        Opportunity opportunityRecord = [
            SELECT Id, Billing_Status__c, AccountId
            FROM Opportunity
            WHERE Id = :input.opportunityId
            LIMIT 1
            FOR UPDATE
        ];
        Invoice__c invoiceRecord = resolveInvoiceForReceipt(opportunityRecord.Id, invoiceId);
        return applyReceipt(opportunityRecord, invoiceRecord, input);
    }

    private static BillingControl_Invoicing.PaymentReceiptResultWrapper applyReceipt(
        Opportunity opportunityRecord,
        Invoice__c invoiceRecord,
        BillingControl_Invoicing.PostReceiptInputWrapper input
    ) {
        Decimal invoiceAmount = invoiceRecord.Total_Amount__c != null ? invoiceRecord.Total_Amount__c : 0;
        Decimal previouslyPaid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
        Decimal balanceDue = invoiceAmount - previouslyPaid;

        if (invoiceAmount <= 0) {
            throw new AuraHandledException(
                'The receivable invoice total must be greater than 0 before recording a receipt.'
            );
        }
        if (input.amountReceived > balanceDue) {
            throw new AuraHandledException('Payment amount cannot exceed the balance due.');
        }

        Invoice_Payment__c paymentRecord = new Invoice_Payment__c(
            Opportunity__c = input.opportunityId,
            Invoice__c = invoiceRecord.Id,
            Amount_Received__c = input.amountReceived,
            Payment_Date__c = input.paymentDate,
            Payment_Method__c = input.paymentMethod,
            Reference_Number__c = input.referenceNumber
        );
        insert paymentRecord;

        BillingControl_InvoiceMath.recalculate(new Set<Id>{ invoiceRecord.Id });
        writePaymentLedgerEntry(opportunityRecord.Id, invoiceRecord, paymentRecord, input.amountReceived);

        Invoice__c refreshedInvoice = [
            SELECT Id, Total_Amount__c, Amount_Paid__c, Balance_Due__c, Status__c
            FROM Invoice__c
            WHERE Id = :invoiceRecord.Id
            LIMIT 1
        ];

        BillingControl_OpportunityFinancials.Snapshot snapshot =
            BillingControl_OpportunityFinancials.load(new Set<Id>{ opportunityRecord.Id }).get(opportunityRecord.Id);
        String previousStatus = opportunityRecord.Billing_Status__c;
        String nextStatus = previousStatus;
        if (snapshot != null && snapshot.paidInFull) {
            nextStatus = PAID;
        } else if (snapshot != null && snapshot.paidTotal > 0) {
            nextStatus = PARTIALLY_PAID;
        }

        if (nextStatus != previousStatus) {
            update new Opportunity(
                Id = opportunityRecord.Id,
                Billing_Status__c = nextStatus
            );
        }

        if (nextStatus == PAID && previousStatus != PAID) {
            BillingControl_CommissionLifecycle.markPayable(opportunityRecord.Id);
        }

        BillingControl_Invoicing.PaymentReceiptResultWrapper result = new BillingControl_Invoicing.PaymentReceiptResultWrapper();
        result.totalPaid = refreshedInvoice.Amount_Paid__c != null ? refreshedInvoice.Amount_Paid__c : 0;
        result.balanceDue = refreshedInvoice.Balance_Due__c != null ? refreshedInvoice.Balance_Due__c : 0;
        result.billingStatus = nextStatus;
        return result;
    }

    public static BillingControl_Invoicing.CommissionMetricsWrapper getCommissionMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        BillingControl_Invoicing.CommissionMetricsWrapper metrics = new BillingControl_Invoicing.CommissionMetricsWrapper();
        metrics.unbilledRevenue = 0;
        metrics.unbilledRevenueCount = 0;
        for (AggregateResult revenueAggregateRow : Database.query(
            'SELECT Opportunity__c opportunityId, SUM(Total_Amount__c) totalInvoiced, SUM(Amount_Paid__c) totalReceived'
            + ' FROM Invoice__c'
            + buildReceivableInvoicesWhereClause(invoicesFilterContext)
            + ' GROUP BY Opportunity__c'
        )) {
            Decimal invoicedAmount = revenueAggregateRow.get('totalInvoiced') != null
                ? (Decimal) revenueAggregateRow.get('totalInvoiced')
                : 0;
            Decimal receivedAmount = revenueAggregateRow.get('totalReceived') != null
                ? (Decimal) revenueAggregateRow.get('totalReceived')
                : 0;
            Decimal outstandingAmount = invoicedAmount - receivedAmount;
            if (outstandingAmount <= 0) {
                continue;
            }

            metrics.revenueUnderCollectionCount++;
            metrics.revenueUnderCollection += outstandingAmount;
        }

        List<Commission__c> earnedCommissionRecords = Database.query(
            'SELECT Id, Opportunity__c, Commission_Rate__c'
            + ' FROM Commission__c'
            + buildCommissionWhereClause(commissionsFilterContext, true, false)
        );
        Set<Id> earnedOpportunityIds = new Set<Id>();
        for (Commission__c earnedCommissionRecord : earnedCommissionRecords) {
            if (earnedCommissionRecord.Opportunity__c != null) {
                earnedOpportunityIds.add(earnedCommissionRecord.Opportunity__c);
            }
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> earnedFinancials =
            BillingControl_OpportunityFinancials.load(earnedOpportunityIds);
        for (Commission__c earnedCommissionRecord : earnedCommissionRecords) {
            BillingControl_OpportunityFinancials.Snapshot snapshot =
                earnedFinancials.get(earnedCommissionRecord.Opportunity__c);
            metrics.commissionEarnedCount++;
            metrics.commissionEarned += BillingControl_CommissionLifecycle.computedCommissionAmount(
                snapshot != null ? snapshot.invoicedTotal : 0,
                earnedCommissionRecord.Commission_Rate__c
            );
        }

        List<Commission__c> payableCommissionRecords = queryOrderLinkedReceivableCommissionRecords(commissionsFilterContext);
        Set<Id> payableOpportunityIds = new Set<Id>();
        for (Commission__c payableCommissionRecord : payableCommissionRecords) {
            if (payableCommissionRecord.Opportunity__c != null) {
                payableOpportunityIds.add(payableCommissionRecord.Opportunity__c);
            }
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> payableFinancials =
            BillingControl_OpportunityFinancials.load(payableOpportunityIds);
        for (Commission__c payableCommissionRecord : payableCommissionRecords) {
            BillingControl_OpportunityFinancials.Snapshot snapshot =
                payableFinancials.get(payableCommissionRecord.Opportunity__c);
            Decimal commissionAmount = BillingControl_CommissionLifecycle.computedCommissionAmount(
                snapshot != null ? snapshot.invoicedTotal : 0,
                payableCommissionRecord.Commission_Rate__c
            );
            Decimal remainingPayable = 0;
            if (isCommissionPaid(payableCommissionRecord) || isCommissionCancelled(payableCommissionRecord)) {
                continue;
            }
            if (payableCommissionRecord.Status__c != 'Payable') {
                continue;
            }

            metrics.commissionPayableCount++;
            remainingPayable = commissionAmount - resolvedCommissionPaidAmount(payableCommissionRecord);
            if (remainingPayable < 0) {
                remainingPayable = 0;
            }
            metrics.commissionPayable += remainingPayable;
        }

        return metrics;
    }


    public static List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> getCommissionData(
        String subtabType,
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections = new List<BillingControl_Invoicing.CommissionKpiCategoryWrapper>{
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper(
                KPI_CATEGORY_REVENUE_UNDER_COLLECTION,
                KPI_LABEL_REVENUE_UNDER_COLLECTION
            ),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper(
                KPI_CATEGORY_COMMISSION_EARNED,
                KPI_LABEL_COMMISSION_EARNED
            ),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper(
                KPI_CATEGORY_COMMISSION_PAYABLE,
                KPI_LABEL_COMMISSION_PAYABLE
            )
        };

        Map<String, BillingControl_Invoicing.CommissionKpiCategoryWrapper> sectionByKey = new Map<String, BillingControl_Invoicing.CommissionKpiCategoryWrapper>();
        Map<String, Map<String, BillingControl_Invoicing.SalespersonWrapper>> salespersonIndexByCategoryKey =
            new Map<String, Map<String, BillingControl_Invoicing.SalespersonWrapper>>();
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            sectionByKey.put(section.categoryKey, section);
            salespersonIndexByCategoryKey.put(section.categoryKey, new Map<String, BillingControl_Invoicing.SalespersonWrapper>());
        }

        String ignoredSubtabType = subtabType;
        List<ReceivableOrderSummary> receivableSummaries = queryReceivableOrderSummaries(invoicesFilterContext);
        List<Commission__c> commissionRecords = queryOrderLinkedReceivableCommissionRecords(commissionsFilterContext);

        BillingControl_Invoicing.CommissionKpiCategoryWrapper revenueSection = sectionByKey.get(KPI_CATEGORY_REVENUE_UNDER_COLLECTION);
        BillingControl_Invoicing.CommissionKpiCategoryWrapper earnedSection = sectionByKey.get(KPI_CATEGORY_COMMISSION_EARNED);
        BillingControl_Invoicing.CommissionKpiCategoryWrapper payableSection = sectionByKey.get(KPI_CATEGORY_COMMISSION_PAYABLE);

        for (ReceivableOrderSummary summary : receivableSummaries) {
            addOpportunityToCommissionSection(
                revenueSection,
                salespersonIndexByCategoryKey.get(revenueSection.categoryKey),
                summary.ownerId,
                summary.ownerName,
                buildOpportunityFromReceivableSummary(summary)
            );
        }

        Map<Id, ReceivableOrderSummary> receivableSummaryByOpportunityId = new Map<Id, ReceivableOrderSummary>();
        for (ReceivableOrderSummary summary : receivableSummaries) {
            if (summary != null && summary.opportunityId != null) {
                receivableSummaryByOpportunityId.put(summary.opportunityId, summary);
            }
        }

        Set<Id> commissionOpportunityIds = new Set<Id>();
        for (Commission__c commissionRecord : commissionRecords) {
            if (commissionRecord != null && commissionRecord.Opportunity__c != null) {
                commissionOpportunityIds.add(commissionRecord.Opportunity__c);
            }
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> commissionFinancials =
            BillingControl_OpportunityFinancials.load(commissionOpportunityIds);

        for (Commission__c commissionRecord : commissionRecords) {
            Id commissionOpportunityId = commissionRecord != null ? commissionRecord.Opportunity__c : null;
            ReceivableOrderSummary invoiceSummary = commissionOpportunityId != null
                ? receivableSummaryByOpportunityId.get(commissionOpportunityId)
                : null;
            Decimal outstandingAmount = invoiceSummary != null ? BillingControl_Invoicing.coalesceDecimal(invoiceSummary.balanceDue) : 0;
            BillingControl_Invoicing.OpportunityWrapper commissionOpportunity =
                buildOpportunityFromOrderLinkedCommission(
                    commissionRecord,
                    invoiceSummary,
                    commissionFinancials.get(commissionOpportunityId)
                );

            if (outstandingAmount > 0) {
                addOpportunityToCommissionSection(
                    earnedSection,
                    salespersonIndexByCategoryKey.get(earnedSection.categoryKey),
                    commissionRecord.Sales_Person__c,
                    commissionRecord.Sales_Person__r != null ? commissionRecord.Sales_Person__r.Name : null,
                    commissionOpportunity
                );
            }

            if (commissionRecord.Status__c == 'Payable') {
                addOpportunityToCommissionSection(
                    payableSection,
                    salespersonIndexByCategoryKey.get(payableSection.categoryKey),
                    commissionRecord.Sales_Person__c,
                    commissionRecord.Sales_Person__r != null ? commissionRecord.Sales_Person__r.Name : null,
                    commissionOpportunity
                );
            }
        }

        stampOpportunityLedgerIds(sections);
        return sections;
    }

    public static List<ReceivableOrderSummary> queryReceivableOrderSummaries(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Invoice__c> outstandingReceivableInvoices = Database.query(
            'SELECT Id,'
            + ' Invoice_Number__c,'
            + ' Opportunity__c,'
            + ' Opportunity__r.Name,'
            + ' Opportunity__r.CloseDate,'
            + ' Opportunity__r.OwnerId,'
            + ' Opportunity__r.Owner.Name,'
            + ' Opportunity__r.Billing_Status__c,'
            + ' Account__r.Name,'
            + ' Total_Amount__c,'
            + ' Amount_Paid__c,'
            + ' Balance_Due__c,'
            + ' Invoice_Date__c,'
            + ' Status__c'
            + ' FROM Invoice__c'
            + buildReceivableInvoicesWhereClause(filterContext)
            + ' ORDER BY Opportunity__r.Name ASC NULLS LAST, Invoice_Number__c ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT
        );

        if (outstandingReceivableInvoices.size() >= QUERY_ROW_LIMIT) {
            while (outstandingReceivableInvoices.size() > MAX_ROWS_PER_SECTION) {
                outstandingReceivableInvoices.remove(outstandingReceivableInvoices.size() - 1);
            }
            BillingControl_Invoicing.addRuntimeWarning(filterContext, KPI_LABEL_REVENUE_UNDER_COLLECTION + ': ' + ROW_LIMIT_WARNING_MESSAGE);
        }

        return summarizeReceivableInvoices(outstandingReceivableInvoices);
    }

    public static List<Commission__c> queryOrderLinkedReceivableCommissionRecords(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Commission__c> commissionRecords = Database.query(
            'SELECT Id,'
            + ' Opportunity__c,'
            + ' Opportunity__r.Name,'
            + ' Opportunity__r.CloseDate,'
            + ' Opportunity__r.OwnerId,'
            + ' Opportunity__r.Owner.Name,'
            + ' Opportunity__r.Account.Name,'
            + ' Opportunity__r.Amount,'
            + ' Opportunity__r.Amount_Paid__c,'
            + ' Opportunity__r.Billing_Status__c,'
            + ' Sales_Person__c,'
            + ' Sales_Person__r.Name,'
            + ' Commission_Rate__c,'
            + ' Commission_Amount__c,'
            + ' Status__c,'
            + ' Paid_Amount__c,'
            + ' Commission_Paid__c'
            + ' FROM Commission__c'
            + buildCommissionPrefilterWhereClause(filterContext)
            + ' ORDER BY Sales_Person__r.Name ASC NULLS LAST, Opportunity__r.Name ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT
        );

        if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
            commissionRecords = filterReceivablesCommissionRecords(commissionRecords, filterContext);
        }

        if (commissionRecords.size() >= QUERY_ROW_LIMIT) {
            while (commissionRecords.size() > MAX_ROWS_PER_SECTION) {
                commissionRecords.remove(commissionRecords.size() - 1);
            }
            BillingControl_Invoicing.addRuntimeWarning(filterContext, KPI_LABEL_COMMISSION_EARNED + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            BillingControl_Invoicing.addRuntimeWarning(filterContext, KPI_LABEL_COMMISSION_PAYABLE + ': ' + ROW_LIMIT_WARNING_MESSAGE);
        }

        return commissionRecords;
    }

    public static List<Commission__c> filterReceivablesCommissionRecords(
        List<Commission__c> commissionRecords,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<Commission__c> filtered = new List<Commission__c>();
        for (Commission__c commissionRecord : commissionRecords) {
            if (matchesReceivablesCommissionFilters(commissionRecord, filterContext)) {
                filtered.add(commissionRecord);
            }
        }
        return filtered;
    }

    public static Boolean matchesReceivablesCommissionFilters(
        Commission__c commissionRecord,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return true;
        }

        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = BillingControl_Invoicing.normalizeFilterValue(filterRecord.objectApiName) + '.' + BillingControl_Invoicing.normalizeFilterValue(filterRecord.fieldApiName);
            Object fieldValue;

            if (fieldKey == 'ORDER.EFFECTIVEDATE' || fieldKey == 'OPPORTUNITY.CLOSEDATE') {
                Date closeDate = commissionRecord != null && commissionRecord.Opportunity__r != null
                    ? commissionRecord.Opportunity__r.CloseDate
                    : null;
                if (!BillingControl_Invoicing.evaluateDateFilter(closeDate, filterRecord)) {
                    return false;
                }
                continue;
            } else if (fieldKey == 'COMMISSION__C.COMMISSION_PAID__C') {
                fieldValue = commissionRecord != null ? commissionRecord.Commission_Paid__c : null;
            } else if (fieldKey == 'OPPORTUNITY.OWNERID') {
                fieldValue = commissionRecord != null && commissionRecord.Opportunity__r != null
                    ? commissionRecord.Opportunity__r.OwnerId
                    : null;
            } else {
                continue;
            }

            if (!BillingControl_Invoicing.evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    public static List<ReceivableOrderSummary> summarizeReceivableInvoices(List<Invoice__c> invoiceRecords) {
        Map<Id, ReceivableOrderSummary> summaryByOpportunityId = new Map<Id, ReceivableOrderSummary>();
        List<ReceivableOrderSummary> summaries = new List<ReceivableOrderSummary>();
        if (invoiceRecords == null) {
            return summaries;
        }

        for (Invoice__c invoiceRecord : invoiceRecords) {
            if (invoiceRecord == null || invoiceRecord.Opportunity__c == null) {
                continue;
            }

            Decimal invoicedAmount = BillingControl_Invoicing.coalesceDecimal(invoiceRecord.Total_Amount__c);
            Decimal receivedAmount = BillingControl_Invoicing.coalesceDecimal(invoiceRecord.Amount_Paid__c);
            Decimal outstandingAmount = invoiceRecord.Balance_Due__c != null
                ? BillingControl_Invoicing.coalesceDecimal(invoiceRecord.Balance_Due__c)
                : invoicedAmount - receivedAmount;
            if (outstandingAmount <= 0) {
                continue;
            }

            ReceivableOrderSummary summary = summaryByOpportunityId.get(invoiceRecord.Opportunity__c);
            if (summary == null) {
                summary = new ReceivableOrderSummary();
                summary.opportunityId = invoiceRecord.Opportunity__c;
                summary.opportunityName = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.Name : null;
                summary.accountName = invoiceRecord.Account__r != null ? invoiceRecord.Account__r.Name : null;
                summary.closeDate = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.CloseDate : null;
                summary.ownerId = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.OwnerId : null;
                summary.ownerName = invoiceRecord.Opportunity__r != null && invoiceRecord.Opportunity__r.Owner != null
                    ? invoiceRecord.Opportunity__r.Owner.Name
                    : null;
                summary.billingStatus = invoiceRecord.Opportunity__r != null
                    ? invoiceRecord.Opportunity__r.Billing_Status__c
                    : invoiceRecord.Status__c;
                summary.amount = 0;
                summary.amountPaid = 0;
                summary.balanceDue = 0;
                summaryByOpportunityId.put(summary.opportunityId, summary);
                summaries.add(summary);
            }

            summary.amount += invoicedAmount;
            summary.amountPaid += receivedAmount;
            summary.balanceDue += outstandingAmount;
        }

        return summaries;
    }

    public static BillingControl_Invoicing.OpportunityWrapper buildOpportunityFromReceivableSummary(ReceivableOrderSummary summary) {
        BillingControl_Invoicing.OpportunityWrapper opportunity = new BillingControl_Invoicing.OpportunityWrapper();
        opportunity.opportunityId = summary != null ? summary.opportunityId : null;
        opportunity.name = summary != null ? summary.opportunityName : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = summary != null ? summary.accountName : null;
        opportunity.amount = summary != null ? summary.amount : 0;
        opportunity.amountPaid = summary != null ? summary.amountPaid : 0;
        opportunity.balanceDue = summary != null ? summary.balanceDue : 0;
        opportunity.billingStatus = summary != null ? summary.billingStatus : null;
        opportunity.closeDate = summary != null ? summary.closeDate : null;
        opportunity.ownerId = summary != null ? summary.ownerId : null;
        opportunity.ownerName = summary != null ? summary.ownerName : null;
        opportunity.commissionAmount = 0;
        opportunity.commissionPaid = 0;
        opportunity.commissionId = null;
        return opportunity;
    }

    public static BillingControl_Invoicing.OpportunityWrapper buildOpportunityFromOrderLinkedCommission(
        Commission__c commissionRecord,
        ReceivableOrderSummary invoiceSummary
    ) {
        return buildOpportunityFromOrderLinkedCommission(commissionRecord, invoiceSummary, null);
    }

    public static BillingControl_Invoicing.OpportunityWrapper buildOpportunityFromOrderLinkedCommission(
        Commission__c commissionRecord,
        ReceivableOrderSummary invoiceSummary,
        BillingControl_OpportunityFinancials.Snapshot snapshot
    ) {
        BillingControl_Invoicing.OpportunityWrapper opportunity = new BillingControl_Invoicing.OpportunityWrapper();
        Opportunity linkedOpportunity = commissionRecord != null ? commissionRecord.Opportunity__r : null;
        opportunity.opportunityId = commissionRecord != null ? commissionRecord.Opportunity__c : null;
        opportunity.name = linkedOpportunity != null ? linkedOpportunity.Name : null;
        opportunity.opportunityName = opportunity.name;
        opportunity.accountName = linkedOpportunity != null && linkedOpportunity.Account != null
            ? linkedOpportunity.Account.Name
            : null;
        if (invoiceSummary != null) {
            opportunity.amount = BillingControl_Invoicing.coalesceDecimal(invoiceSummary.amount);
            opportunity.amountPaid = BillingControl_Invoicing.coalesceDecimal(invoiceSummary.amountPaid);
            opportunity.balanceDue = BillingControl_Invoicing.coalesceDecimal(invoiceSummary.balanceDue);
        } else {
            opportunity.amount = linkedOpportunity != null ? BillingControl_Invoicing.coalesceDecimal(linkedOpportunity.Amount) : 0;
            Decimal amountPaid = linkedOpportunity != null
                ? (Decimal) linkedOpportunity.get('Amount_Paid__c')
                : null;
            opportunity.amountPaid = amountPaid != null ? amountPaid : 0;
            opportunity.balanceDue = opportunity.amount - opportunity.amountPaid;
        }
        opportunity.billingStatus = linkedOpportunity != null ? linkedOpportunity.Billing_Status__c : null;
        opportunity.closeDate = linkedOpportunity != null ? linkedOpportunity.CloseDate : null;
        opportunity.ownerId = commissionRecord != null ? commissionRecord.Sales_Person__c : null;
        opportunity.ownerName = commissionRecord != null && commissionRecord.Sales_Person__r != null
            ? commissionRecord.Sales_Person__r.Name
            : null;
        opportunity.commissionAmount = BillingControl_CommissionLifecycle.computedCommissionAmount(
            snapshot != null ? snapshot.invoicedTotal : 0,
            commissionRecord != null ? commissionRecord.Commission_Rate__c : 0
        );
        opportunity.commissionPaid = resolvedCommissionPaidAmount(commissionRecord);
        opportunity.commissionId = commissionRecord != null ? commissionRecord.Id : null;
        return opportunity;
    }

    public static void addOpportunityToCommissionSection(
        BillingControl_Invoicing.CommissionKpiCategoryWrapper section,
        Map<String, BillingControl_Invoicing.SalespersonWrapper> salespersonIndex,
        Id salespersonId,
        String salespersonName,
        BillingControl_Invoicing.OpportunityWrapper opportunity
    ) {
        if (section == null || salespersonIndex == null || opportunity == null || opportunity.opportunityId == null) {
            return;
        }

        String salespersonKey = salespersonId != null ? String.valueOf(salespersonId) : 'UNASSIGNED';
        BillingControl_Invoicing.SalespersonWrapper salesperson = salespersonIndex.get(salespersonKey);
        if (salesperson == null) {
            salesperson = new BillingControl_Invoicing.SalespersonWrapper();
            salesperson.salespersonId = salespersonId;
            salesperson.salespersonName = String.isNotBlank(salespersonName) ? salespersonName : 'Unassigned';
            salesperson.totalAmount = 0;
            salesperson.totalCommission = 0;
            salesperson.totalPaid = 0;
            salesperson.opportunities = new List<BillingControl_Invoicing.OpportunityWrapper>();
            salespersonIndex.put(salespersonKey, salesperson);
            section.salespersonGroups.add(salesperson);
        }

        Decimal amount = opportunity.amount != null ? opportunity.amount : 0;
        Decimal commissionAmount = opportunity.commissionAmount != null ? opportunity.commissionAmount : 0;
        Decimal commissionPaid = opportunity.commissionPaid != null ? opportunity.commissionPaid : 0;

        salesperson.totalAmount += amount;
        salesperson.totalCommission += commissionAmount;
        salesperson.totalPaid += commissionPaid;
        salesperson.opportunities.add(opportunity);

        section.opportunityCount++;
        section.totalAmount += amount;
        section.totalCommission += commissionAmount;
        section.totalPaid += commissionPaid;
    }

    public static void stampOpportunityLedgerIds(List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections) {
        if (sections == null || sections.isEmpty()) {
            return;
        }
        Set<Id> opportunityIds = new Set<Id>();
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            if (section == null || section.salespersonGroups == null) {
                continue;
            }
            for (BillingControl_Invoicing.SalespersonWrapper salesperson : section.salespersonGroups) {
                if (salesperson == null || salesperson.opportunities == null) {
                    continue;
                }
                for (BillingControl_Invoicing.OpportunityWrapper opportunity : salesperson.opportunities) {
                    if (opportunity != null && opportunity.opportunityId != null) {
                        opportunityIds.add(opportunity.opportunityId);
                    }
                }
            }
        }
        Set<Id> eligibleOpportunityIds = new Set<Id>();
        if (!opportunityIds.isEmpty()) {
            for (Opportunity opportunityRecord : [
                SELECT Id, Billing_Status__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]) {
                if (String.isNotBlank(opportunityRecord.Billing_Status__c)) {
                    eligibleOpportunityIds.add(opportunityRecord.Id);
                }
            }
        }
        Map<Id, Id> ledgerByOpportunityId =
            BillingControl_WorkOrderLedger.getLedgerIdsByOpportunityId(eligibleOpportunityIds);
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper section : sections) {
            if (section == null || section.salespersonGroups == null) {
                continue;
            }
            for (BillingControl_Invoicing.SalespersonWrapper salesperson : section.salespersonGroups) {
                if (salesperson == null || salesperson.opportunities == null) {
                    continue;
                }
                for (BillingControl_Invoicing.OpportunityWrapper opportunity : salesperson.opportunities) {
                    if (opportunity == null) {
                        continue;
                    }
                    opportunity.ledgerId = ledgerByOpportunityId.get(opportunity.opportunityId);
                }
            }
        }
    }

    private static Boolean isCommissionPaid(Commission__c commissionRecord) {
        return commissionRecord != null && commissionRecord.Status__c == 'Paid';
    }

    private static Boolean isCommissionCancelled(Commission__c commissionRecord) {
        return commissionRecord != null && commissionRecord.Status__c == 'Cancelled';
    }

    private static Decimal resolvedCommissionPaidAmount(Commission__c commissionRecord) {
        if (commissionRecord == null || commissionRecord.Status__c != 'Paid') {
            return 0;
        }
        if (commissionRecord.Paid_Amount__c != null) {
            return commissionRecord.Paid_Amount__c;
        }
        return 0;
    }

    public static void updateCommissionPaid(List<Id> commissionIds) {
        BillingControl_CommissionLifecycle.payCommissions(commissionIds, Date.today(), null);
    }

    public static void payCommissions(
        List<Id> commissionIds,
        Date paidDate,
        Map<Id, Decimal> paidAmountOverrides
    ) {
        BillingControl_CommissionLifecycle.payCommissions(commissionIds, paidDate, paidAmountOverrides);
    }

    public static void markCommissionsPayable(Id opportunityId) {
        BillingControl_CommissionLifecycle.markPayable(opportunityId);
    }

    public static BillingControl_Invoicing.CommissionResultWrapper createCommissionRecords(List<BillingControl_Invoicing.CommissionInputWrapper> inputs) {

        BillingControl_Invoicing.CommissionResultWrapper result = new BillingControl_Invoicing.CommissionResultWrapper();
        result.successCount = 0;
        result.errorMessages = new List<String>();

        if (inputs == null || inputs.isEmpty()) {
            return result;
        }

        Map<Id, BillingControl_Invoicing.CommissionInputWrapper> inputByOpportunityId = new Map<Id, BillingControl_Invoicing.CommissionInputWrapper>();
        Set<Id> opportunityIds = new Set<Id>();
        for (BillingControl_Invoicing.CommissionInputWrapper input : inputs) {
            if (input != null && input.opportunityId != null) {
                inputByOpportunityId.put(input.opportunityId, input);
                opportunityIds.add(input.opportunityId);
            }
        }


        if (inputByOpportunityId.isEmpty()) {
            return result;
        }

        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, Name, OwnerId, Owner.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);


        List<Commission__c> commissionRecords = new List<Commission__c>();
        List<Id> commissionOpportunityIds = new List<Id>();

        for (BillingControl_Invoicing.CommissionInputWrapper input : inputs) {
            if (input == null || input.opportunityId == null) {
                continue;
            }

            Opportunity opportunityRecord = opportunityById.get(input.opportunityId);
            Id salesPersonId = input.ownerId != null
                ? input.ownerId
                : (opportunityRecord != null ? opportunityRecord.OwnerId : null);

            Commission__c commissionRecord = new Commission__c();
            commissionRecord.Opportunity__c = input.opportunityId;
            commissionRecord.Commission_Rate__c = input.commissionRate;
            commissionRecord.Sales_Person__c = salesPersonId;
            commissionRecord.Status__c = 'Accrued';
            commissionRecord.Amount_Basis__c = 'Invoiced Total';
            commissionRecord.Unique_Key__c = String.valueOf(input.opportunityId) + String.valueOf(salesPersonId);
            commissionRecords.add(commissionRecord);
            commissionOpportunityIds.add(input.opportunityId);
        }


        if (commissionRecords.isEmpty()) {
            return result;
        }

        Database.SaveResult[] saveResults = Database.insert(commissionRecords, false);

        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Id opportunityId = commissionOpportunityIds[index];
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            String opportunityName = opportunityRecord != null ? opportunityRecord.Name : String.valueOf(opportunityId);
            String ownerName = opportunityRecord != null && opportunityRecord.Owner != null
                ? opportunityRecord.Owner.Name
                : '';

            if (saveResult.isSuccess()) {
                result.successCount = (result.successCount == null ? 0 : result.successCount) + 1;
                continue;
            }

            for (Database.Error dbError : saveResult.getErrors()) {
                String message = dbError.getMessage();
                if (String.isNotBlank(message) &&
                    (message.contains('DUPLICATE_VALUE') || message.contains('duplicate value'))) {
                    result.errorMessages.add(
                        'Commission already exists for Opportunity: ' + opportunityName +
                        ' and Owner: ' + ownerName
                    );
                } else {
                    result.errorMessages.add(
                        'Opportunity: ' + opportunityName +
                        ', Owner: ' + ownerName +
                        ' - ' + message
                    );
                }
            }
        }


        if (result.successCount == 0 && result.errorMessages.isEmpty()) {
            result.errorMessages.add('No commission records were created.');
        }

        return result;
    }

    public static Invoice__c getInvoiceForReceipt(Id invoiceId, Id opportunityId) {
        if (invoiceId == null) {
            throw new AuraHandledException('Select an invoice before recording a receipt.');
        }

        List<Invoice__c> invoices = [
            SELECT Id,
                Invoice_Number__c,
                Opportunity__c,
                Amount_Paid__c,
                Balance_Due__c,
                Total_Amount__c,
                Status__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
            FOR UPDATE
        ];
        if (invoices.isEmpty()) {
            throw new AuraHandledException('The selected invoice could not be found.');
        }
        Invoice__c invoiceRecord = invoices[0];
        if (opportunityId != null && invoiceRecord.Opportunity__c != opportunityId) {
            throw new AuraHandledException('The selected invoice does not belong to this opportunity.');
        }
        if (invoiceRecord.Status__c == INVOICE_STATUS_VOID) {
            throw new AuraHandledException('Receipts cannot be recorded against a void invoice.');
        }
        Decimal invoiceAmount = invoiceRecord.Total_Amount__c != null ? invoiceRecord.Total_Amount__c : 0;
        Decimal previouslyPaid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
        if (invoiceAmount <= 0) {
            throw new AuraHandledException('Set the invoice amount before recording a receipt.');
        }
        if (invoiceAmount - previouslyPaid <= 0 || invoiceRecord.Status__c == INVOICE_STATUS_PAID) {
            throw new AuraHandledException('This invoice has no remaining balance.');
        }
        return invoiceRecord;
    }

    public static Invoice__c resolveInvoiceForReceipt(Id opportunityId, Id invoiceId) {
        if (invoiceId != null) {
            return getInvoiceForReceipt(invoiceId, opportunityId);
        }

        List<Invoice__c> openInvoices = [
            SELECT Id,
                Invoice_Number__c,
                Opportunity__c,
                Amount_Paid__c,
                Balance_Due__c,
                Total_Amount__c,
                Status__c
            FROM Invoice__c
            WHERE Opportunity__c = :opportunityId
            AND Status__c != :INVOICE_STATUS_PAID
            AND Status__c != :INVOICE_STATUS_VOID
            AND Total_Amount__c != NULL
            AND Total_Amount__c > 0
            FOR UPDATE
        ];
        List<Invoice__c> receivableInvoices = new List<Invoice__c>();
        for (Invoice__c invoiceRecord : openInvoices) {
            Decimal invoiceAmount = invoiceRecord.Total_Amount__c != null ? invoiceRecord.Total_Amount__c : 0;
            Decimal previouslyPaid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
            if (invoiceAmount - previouslyPaid > 0) {
                receivableInvoices.add(invoiceRecord);
            }
        }
        if (receivableInvoices.isEmpty()) {
            throw new AuraHandledException(
                'No open Invoice__c is available for this opportunity. Complete Billing or INV-Sync before recording a receipt.'
            );
        }
        if (receivableInvoices.size() > 1) {
            throw new AuraHandledException('Select an invoice before recording a receipt.');
        }
        return receivableInvoices[0];
    }

    public static Invoice__c getOpenReceivableInvoice(Id opportunityId) {
        try {
            return resolveInvoiceForReceipt(opportunityId, null);
        } catch (AuraHandledException caught) {
            return null;
        }
    }

    private static void writePaymentLedgerEntry(
        Id opportunityId,
        Invoice__c invoiceRecord,
        Invoice_Payment__c paymentRecord,
        Decimal paymentAmount
    ) {
        List<Opportunity_WorkOrder__c> junctions = [
            SELECT Work_Order__c
            FROM Opportunity_WorkOrder__c
            WHERE Opportunity__c = :opportunityId
            AND Work_Order__c != NULL
            LIMIT 1
        ];
        if (junctions.isEmpty()) {
            return;
        }
        Id workOrderId = junctions[0].Work_Order__c;
        List<Work_Order_Ledger__c> ledgers = [
            SELECT Id
            FROM Work_Order_Ledger__c
            WHERE Work_Order__c = :workOrderId
            LIMIT 1
        ];
        Work_Order_Ledger__c ledgerRecord;
        if (ledgers.isEmpty()) {
            WorkOrder workOrderRecord = [
                SELECT Id, AccountId
                FROM WorkOrder
                WHERE Id = :workOrderId
                LIMIT 1
            ];
            ledgerRecord = new Work_Order_Ledger__c(
                Work_Order__c = workOrderId,
                Work_Order_Key__c = String.valueOf(workOrderId),
                Account__c = workOrderRecord.AccountId
            );
            insert ledgerRecord;
        } else {
            ledgerRecord = ledgers[0];
        }

        String eventKey = 'PAYMENT_RECORDED|' + String.valueOf(paymentRecord.Id) + '|' + String.valueOf(workOrderId);
        if (eventKey.length() > 80) {
            eventKey = eventKey.substring(0, 80);
        }
        insert new Work_Order_Ledger_Entry__c(
            Work_Order_Ledger__c = ledgerRecord.Id,
            Event_Type__c = 'PAYMENT_RECORDED',
            Event_Key__c = eventKey,
            Event_Datetime__c = System.now(),
            Invoice__c = invoiceRecord.Id,
            Opportunity__c = opportunityId,
            Amount__c = paymentAmount,
            Description__c = 'Payment recorded on invoice ' + invoiceRecord.Invoice_Number__c,
            System_Generated__c = true,
            Changed_By__c = UserInfo.getUserId(),
            Source_Object__c = 'Invoice',
            Source_Record_Id__c = String.valueOf(paymentRecord.Id)
        );
    }

    public static String buildReceivableInvoicesWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<String> clauses = new List<String>{
            'Opportunity__c != NULL',
            'Status__c != \'' + String.escapeSingleQuotes(INVOICE_STATUS_PAID) + '\'',
            'Balance_Due__c > 0'
        };
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getReceivableInvoiceFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    public static String buildCommissionWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        Boolean onlyEarned,
        Boolean onlyPayable
    ) {
        List<String> clauses = new List<String>{ 'Opportunity__c != NULL' };
        if (onlyEarned) {
            clauses.add(
                'Opportunity__r.Billing_Status__c IN (\''
                + String.escapeSingleQuotes(OUTSTANDING_RECEIVABLE)
                + '\', \''
                + String.escapeSingleQuotes(OUTSTANDING_RECEIVABLES)
                + '\')'
            );
        }
        if (onlyPayable) {
            clauses.add(
                'Opportunity__r.Billing_Status__c = \''
                + String.escapeSingleQuotes(PAID)
                + '\''
            );
        }
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getCommissionFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    public static String buildCommissionPrefilterWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<String> clauses = new List<String>{ 'Opportunity__c != NULL' };
        if (filterContext != null && filterContext.filters != null) {
            for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
                String fieldKey = BillingControl_Invoicing.normalizeFilterValue(filterRecord.objectApiName) + '.' + BillingControl_Invoicing.normalizeFilterValue(filterRecord.fieldApiName);
                if (fieldKey != 'ORDER.EFFECTIVEDATE' && fieldKey != 'OPPORTUNITY.CLOSEDATE') {
                    continue;
                }
                BillingControl_DataProvider.BillingFilterContextDTO singleFilterContext =
                    new BillingControl_DataProvider.BillingFilterContextDTO();
                singleFilterContext.filters.add(filterRecord);
                List<String> queryClauses = BillingControl_DataProvider.buildQueryFilterClauses(
                    singleFilterContext,
                    new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
                        'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                            'Opportunity__r.CloseDate',
                            BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
                        ),
                        'OPPORTUNITY.CLOSEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                            'Opportunity__r.CloseDate',
                            BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
                        )
                    }
                );
                clauses.addAll(queryClauses);
            }
        }
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    public static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getReceivableInvoiceFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.RECEIVED_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Amount_Paid__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.OUTSTANDING_AMOUNT__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Balance_Due__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Invoice_Date__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'INVOICE__C.INVOICE_DATE__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Invoice_Date__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'OPPORTUNITY.OWNERID' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity__r.OwnerId',
                BillingControl_DataProvider.FILTER_DATA_TYPE_ID
            )
        };
    }

    public static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getCommissionFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity__r.CloseDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'OPPORTUNITY.CLOSEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity__r.CloseDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'COMMISSION__C.COMMISSION_PAID__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Commission_Paid__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DECIMAL
            ),
            'OPPORTUNITY.OWNERID' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity__r.OwnerId',
                BillingControl_DataProvider.FILTER_DATA_TYPE_ID
            )
        };
    }

    private class ReceivableOrderSummary {
        public Id opportunityId;
        public String opportunityName;
        public String accountName;
        public Date closeDate;
        public Id ownerId;
        public String ownerName;
        public String billingStatus;
        public Decimal amount;
        public Decimal amountPaid;
        public Decimal balanceDue;
    }
}
