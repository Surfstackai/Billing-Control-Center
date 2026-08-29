/**
 * Invoice-grain Receivables worklist. Open AR is not gated on invoice date.
 */
public inherited sharing class BillingControl_ReceivablesWorklist {
    private static final String STATUS_VOID = 'Void';
    private static final String STATUS_PAID = 'Paid';
    private static final String TYPE_DEPOSIT = 'Deposit';
    private static final Integer QUERY_ROW_LIMIT = 500;

    public static final String SECTION_OUTSTANDING_AR = 'OUTSTANDING_AR';
    public static final String SECTION_OVERDUE = 'OVERDUE';
    public static final String SECTION_PARTIALLY_PAID = 'PARTIALLY_PAID';
    public static final String SECTION_NEEDS_AMOUNT = 'NEEDS_AMOUNT';
    public static final String SECTION_DEPOSITS_OUTSTANDING = 'DEPOSITS_OUTSTANDING';

    public class PaymentRow {
        @AuraEnabled public Id paymentId;
        @AuraEnabled public Date paymentDate;
        @AuraEnabled public Decimal amountReceived;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String referenceNumber;
    }

    public class InvoiceRow {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String invoiceType;
        @AuraEnabled public Date invoiceDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Integer daysOutstanding;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal balanceDue;
        @AuraEnabled public String status;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String billingStatus;
        @AuraEnabled public Decimal opportunityInvoiced;
        @AuraEnabled public Decimal opportunityPaid;
        @AuraEnabled public Decimal opportunityOutstanding;
        @AuraEnabled public Boolean canPostReceipt;
        @AuraEnabled public Boolean needsAmount;
        @AuraEnabled public Boolean overdue;
        @AuraEnabled public List<PaymentRow> payments;
    }

    public class SectionWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer invoiceCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Boolean isInvoiceSection;
        @AuraEnabled public List<InvoiceRow> rows;
    }

    public class MetricsWrapper {
        @AuraEnabled public Decimal outstandingAr;
        @AuraEnabled public Integer outstandingArCount;
        @AuraEnabled public Decimal overdue;
        @AuraEnabled public Integer overdueCount;
        @AuraEnabled public Decimal partiallyPaid;
        @AuraEnabled public Integer partiallyPaidCount;
        @AuraEnabled public Integer needsAmountCount;
        @AuraEnabled public Decimal depositsOutstanding;
        @AuraEnabled public Integer depositsOutstandingCount;

        public MetricsWrapper() {
            outstandingAr = 0;
            outstandingArCount = 0;
            overdue = 0;
            overdueCount = 0;
            partiallyPaid = 0;
            partiallyPaidCount = 0;
            needsAmountCount = 0;
            depositsOutstanding = 0;
            depositsOutstandingCount = 0;
        }
    }

    public class TabRuntime {
        @AuraEnabled public MetricsWrapper metrics;
        @AuraEnabled public List<SectionWrapper> invoiceSections;
        @AuraEnabled public List<String> warnings;
    }

    @AuraEnabled
    public static TabRuntime getTabRuntime(
        Long refreshToken,
        String filterKey,
        String startDate,
        String endDate,
        String opportunityOwnerId
    ) {
        Long ignoredRefreshToken = refreshToken;
        String ignoredFilterKey = filterKey;
        Id ownerId = String.isBlank(opportunityOwnerId) ? null : (Id) opportunityOwnerId;

        TabRuntime tabRuntime = new TabRuntime();
        tabRuntime.warnings = new List<String>();
        List<InvoiceRow> invoiceRows = loadInvoiceRows(ownerId);
        tabRuntime.invoiceSections = buildInvoiceSections(invoiceRows);
        tabRuntime.metrics = buildInvoiceMetrics(invoiceRows);
        if (invoiceRows.isEmpty()) {
            tabRuntime.warnings.add('No open invoices found.');
        }
        return tabRuntime;
    }

    @AuraEnabled
    public static void setInvoiceAmount(Id invoiceId, Decimal totalAmount) {
        if (invoiceId == null) {
            throw new AuraHandledException('Select an invoice.');
        }
        if (totalAmount == null || totalAmount <= 0) {
            throw new AuraHandledException('Invoice amount must be greater than 0.');
        }
        Invoice__c invoiceRecord = [
            SELECT Id, Status__c, Total_Amount__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
            FOR UPDATE
        ];
        if (invoiceRecord.Status__c == STATUS_VOID) {
            throw new AuraHandledException('Cannot set an amount on a void invoice.');
        }
        if (invoiceRecord.Total_Amount__c != null && invoiceRecord.Total_Amount__c > 0) {
            throw new AuraHandledException('This invoice already has an amount.');
        }
        update new Invoice__c(
            Id = invoiceRecord.Id,
            Subtotal__c = totalAmount,
            Tax_Amount__c = 0,
            Total_Amount__c = totalAmount,
            Amount_Source__c = 'Entered'
        );
        BillingControl_InvoiceMath.recalculate(new Set<Id>{ invoiceRecord.Id });
    }

    private static List<InvoiceRow> loadInvoiceRows(Id ownerId) {
        String soql =
            'SELECT Id, Invoice_Number__c, Invoice_Type__c, Invoice_Date__c, Due_Date__c,'
            + ' Total_Amount__c, Amount_Paid__c, Balance_Due__c, Status__c,'
            + ' Opportunity__c, Opportunity__r.Name, Opportunity__r.Quote_Number__c,'
            + ' Opportunity__r.Billing_Status__c,'
            + ' Opportunity__r.AccountId, Opportunity__r.Account.Name,'
            + ' Opportunity__r.OwnerId, Opportunity__r.Owner.Name'
            + ' FROM Invoice__c'
            + ' WHERE Opportunity__c != NULL'
            + ' AND Status__c != \'' + String.escapeSingleQuotes(STATUS_VOID) + '\'';
        if (ownerId != null) {
            soql += ' AND Opportunity__r.OwnerId = :ownerId';
        }
        soql += ' ORDER BY Opportunity__r.Account.Name NULLS LAST, Invoice_Date__c DESC NULLS LAST LIMIT '
            + String.valueOf(QUERY_ROW_LIMIT);

        List<Invoice__c> invoiceRecords = Database.query(soql);
        Set<Id> invoiceIds = new Map<Id, Invoice__c>(invoiceRecords).keySet();
        Set<Id> opportunityIds = new Set<Id>();
        for (Invoice__c invoiceRecord : invoiceRecords) {
            if (invoiceRecord.Opportunity__c != null) {
                opportunityIds.add(invoiceRecord.Opportunity__c);
            }
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> financialsByOpportunityId =
            BillingControl_OpportunityFinancials.load(opportunityIds);
        Map<Id, List<PaymentRow>> paymentsByInvoiceId = loadPayments(invoiceIds);

        List<InvoiceRow> rows = new List<InvoiceRow>();
        Date todayValue = Date.today();
        for (Invoice__c invoiceRecord : invoiceRecords) {
            InvoiceRow row = new InvoiceRow();
            row.invoiceId = invoiceRecord.Id;
            row.invoiceNumber = invoiceRecord.Invoice_Number__c;
            row.invoiceType = invoiceRecord.Invoice_Type__c;
            row.invoiceDate = invoiceRecord.Invoice_Date__c;
            row.dueDate = invoiceRecord.Due_Date__c;
            row.totalAmount = invoiceRecord.Total_Amount__c;
            row.amountPaid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
            row.balanceDue = invoiceRecord.Balance_Due__c;
            row.status = invoiceRecord.Status__c;
            row.opportunityId = invoiceRecord.Opportunity__c;
            row.opportunityName = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.Name : null;
            row.quoteNumber = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.Quote_Number__c : null;
            row.accountId = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.AccountId : null;
            row.accountName = invoiceRecord.Opportunity__r != null && invoiceRecord.Opportunity__r.Account != null
                ? invoiceRecord.Opportunity__r.Account.Name
                : null;
            row.ownerId = invoiceRecord.Opportunity__r != null ? invoiceRecord.Opportunity__r.OwnerId : null;
            row.ownerName = invoiceRecord.Opportunity__r != null && invoiceRecord.Opportunity__r.Owner != null
                ? invoiceRecord.Opportunity__r.Owner.Name
                : null;
            row.billingStatus = invoiceRecord.Opportunity__r != null
                ? invoiceRecord.Opportunity__r.Billing_Status__c
                : null;
            BillingControl_OpportunityFinancials.Snapshot snapshot =
                financialsByOpportunityId.get(invoiceRecord.Opportunity__c);
            if (snapshot != null) {
                row.opportunityInvoiced = snapshot.invoicedTotal;
                row.opportunityPaid = snapshot.paidTotal;
                row.opportunityOutstanding = snapshot.outstanding;
            }
            row.needsAmount = invoiceRecord.Total_Amount__c == null;
            Decimal remaining = remainingBalance(invoiceRecord);
            row.canPostReceipt = !row.needsAmount && remaining > 0 && invoiceRecord.Status__c != STATUS_PAID;
            row.overdue = !row.needsAmount && remaining > 0 && invoiceRecord.Due_Date__c != null
                && invoiceRecord.Due_Date__c < todayValue;
            if (invoiceRecord.Invoice_Date__c != null) {
                row.daysOutstanding = invoiceRecord.Invoice_Date__c.daysBetween(todayValue);
            }
            row.payments = paymentsByInvoiceId.containsKey(invoiceRecord.Id)
                ? paymentsByInvoiceId.get(invoiceRecord.Id)
                : new List<PaymentRow>();
            rows.add(row);
        }
        return rows;
    }

    private static Map<Id, List<PaymentRow>> loadPayments(Set<Id> invoiceIds) {
        Map<Id, List<PaymentRow>> paymentsByInvoiceId = new Map<Id, List<PaymentRow>>();
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return paymentsByInvoiceId;
        }
        for (Invoice_Payment__c paymentRecord : [
            SELECT Id, Invoice__c, Amount_Received__c, Payment_Date__c, Payment_Method__c, Reference_Number__c
            FROM Invoice_Payment__c
            WHERE Invoice__c IN :invoiceIds
            ORDER BY Payment_Date__c DESC, CreatedDate DESC
        ]) {
            if (!paymentsByInvoiceId.containsKey(paymentRecord.Invoice__c)) {
                paymentsByInvoiceId.put(paymentRecord.Invoice__c, new List<PaymentRow>());
            }
            PaymentRow paymentRow = new PaymentRow();
            paymentRow.paymentId = paymentRecord.Id;
            paymentRow.paymentDate = paymentRecord.Payment_Date__c;
            paymentRow.amountReceived = paymentRecord.Amount_Received__c;
            paymentRow.paymentMethod = paymentRecord.Payment_Method__c;
            paymentRow.referenceNumber = paymentRecord.Reference_Number__c;
            paymentsByInvoiceId.get(paymentRecord.Invoice__c).add(paymentRow);
        }
        return paymentsByInvoiceId;
    }

    private static List<SectionWrapper> buildInvoiceSections(List<InvoiceRow> invoiceRows) {
        Map<String, SectionWrapper> sectionByKey = new Map<String, SectionWrapper>{
            SECTION_OUTSTANDING_AR => emptySection(SECTION_OUTSTANDING_AR, 'Outstanding AR'),
            SECTION_OVERDUE => emptySection(SECTION_OVERDUE, 'Overdue'),
            SECTION_PARTIALLY_PAID => emptySection(SECTION_PARTIALLY_PAID, 'Partially Paid'),
            SECTION_NEEDS_AMOUNT => emptySection(SECTION_NEEDS_AMOUNT, 'Needs Amount'),
            SECTION_DEPOSITS_OUTSTANDING => emptySection(SECTION_DEPOSITS_OUTSTANDING, 'Deposits Outstanding')
        };

        for (InvoiceRow row : invoiceRows) {
            Decimal remaining = remainingBalance(row);
            if (!row.needsAmount && remaining > 0) {
                addRow(sectionByKey.get(SECTION_OUTSTANDING_AR), row, remaining);
            }
            if (row.overdue) {
                addRow(sectionByKey.get(SECTION_OVERDUE), row, remaining);
            }
            if (!row.needsAmount && remaining > 0 && row.amountPaid != null && row.amountPaid > 0) {
                addRow(sectionByKey.get(SECTION_PARTIALLY_PAID), row, remaining);
            }
            if (row.needsAmount) {
                addRow(sectionByKey.get(SECTION_NEEDS_AMOUNT), row, 0);
            }
            if (!row.needsAmount && remaining > 0 && row.invoiceType == TYPE_DEPOSIT) {
                addRow(sectionByKey.get(SECTION_DEPOSITS_OUTSTANDING), row, remaining);
            }
        }

        return new List<SectionWrapper>{
            sectionByKey.get(SECTION_OUTSTANDING_AR),
            sectionByKey.get(SECTION_OVERDUE),
            sectionByKey.get(SECTION_PARTIALLY_PAID),
            sectionByKey.get(SECTION_NEEDS_AMOUNT),
            sectionByKey.get(SECTION_DEPOSITS_OUTSTANDING)
        };
    }

    private static MetricsWrapper buildInvoiceMetrics(List<InvoiceRow> invoiceRows) {
        MetricsWrapper metrics = new MetricsWrapper();
        for (InvoiceRow row : invoiceRows) {
            Decimal remaining = remainingBalance(row);
            if (!row.needsAmount && remaining > 0) {
                metrics.outstandingArCount++;
                metrics.outstandingAr += remaining;
            }
            if (row.overdue) {
                metrics.overdueCount++;
                metrics.overdue += remaining;
            }
            if (!row.needsAmount && remaining > 0 && row.amountPaid != null && row.amountPaid > 0) {
                metrics.partiallyPaidCount++;
                metrics.partiallyPaid += remaining;
            }
            if (row.needsAmount) {
                metrics.needsAmountCount++;
            }
            if (!row.needsAmount && remaining > 0 && row.invoiceType == TYPE_DEPOSIT) {
                metrics.depositsOutstandingCount++;
                metrics.depositsOutstanding += remaining;
            }
        }
        return metrics;
    }

    private static SectionWrapper emptySection(String categoryKey, String categoryLabel) {
        SectionWrapper section = new SectionWrapper();
        section.categoryKey = categoryKey;
        section.categoryLabel = categoryLabel;
        section.invoiceCount = 0;
        section.totalAmount = 0;
        section.isInvoiceSection = true;
        section.rows = new List<InvoiceRow>();
        return section;
    }

    private static void addRow(SectionWrapper section, InvoiceRow row, Decimal amount) {
        section.rows.add(row);
        section.invoiceCount++;
        section.totalAmount += amount == null ? 0 : amount;
    }

    private static Decimal remainingBalance(Invoice__c invoiceRecord) {
        if (invoiceRecord.Total_Amount__c == null) {
            return 0;
        }
        Decimal paid = invoiceRecord.Amount_Paid__c != null ? invoiceRecord.Amount_Paid__c : 0;
        if (invoiceRecord.Balance_Due__c != null) {
            return invoiceRecord.Balance_Due__c;
        }
        return invoiceRecord.Total_Amount__c - paid;
    }

    private static Decimal remainingBalance(InvoiceRow row) {
        if (row.needsAmount || row.totalAmount == null) {
            return 0;
        }
        if (row.balanceDue != null) {
            return row.balanceDue;
        }
        Decimal paid = row.amountPaid != null ? row.amountPaid : 0;
        return row.totalAmount - paid;
    }
}
