/**
 * Commission status machine. Rate is manual. Amount at Payable uses invoiced total.
 * One row per Opportunity / salesperson; no installment children and no split UI.
 */
public inherited sharing class BillingControl_CommissionLifecycle {
    public static final String STATUS_ACCRUED = 'Accrued';
    public static final String STATUS_PAYABLE = 'Payable';
    public static final String STATUS_PAID = 'Paid';
    public static final String STATUS_CANCELLED = 'Cancelled';
    public static final String SECTION_ACCRUED = 'ACCRUED';
    public static final String SECTION_PAYABLE = 'PAYABLE';
    public static final String SECTION_PAID = 'PAID';
    private static final String STATUS_VOID = 'Void';
    private static final String BASIS_INVOICED_TOTAL = 'Invoiced Total';
    private static final String BASIS_MANUAL = 'Manual';

    public class CommissionRow {
        @AuraEnabled public Id commissionId;
        @AuraEnabled public Id salespersonId;
        @AuraEnabled public String salespersonName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal jobAmount;
        @AuraEnabled public Decimal invoicedTotal;
        @AuraEnabled public Decimal customerPaidTotal;
        @AuraEnabled public Boolean customerPaidInFull;
        @AuraEnabled public Decimal commissionRate;
        @AuraEnabled public Decimal commissionAmount;
        @AuraEnabled public String status;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Date payableDate;
        @AuraEnabled public Date paidDate;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public String amountBasis;
        @AuraEnabled public Boolean canPay;
    }

    public class SectionWrapper {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<CommissionRow> rows;
    }

    public class MetricsWrapper {
        @AuraEnabled public Decimal accrued;
        @AuraEnabled public Integer accruedCount;
        @AuraEnabled public Decimal payable;
        @AuraEnabled public Integer payableCount;
        @AuraEnabled public Decimal paidThisPeriod;
        @AuraEnabled public Integer paidThisPeriodCount;

        public MetricsWrapper() {
            accrued = 0;
            accruedCount = 0;
            payable = 0;
            payableCount = 0;
            paidThisPeriod = 0;
            paidThisPeriodCount = 0;
        }
    }

    public class TabRuntime {
        @AuraEnabled public MetricsWrapper metrics;
        @AuraEnabled public List<SectionWrapper> sections;
        @AuraEnabled public List<String> warnings;
    }

    public static void ensureAccrued(Opportunity opportunityRecord) {
        if (opportunityRecord == null || opportunityRecord.Id == null || opportunityRecord.OwnerId == null) {
            return;
        }
        Commission__c commissionRecord = new Commission__c(
            Opportunity__c = opportunityRecord.Id,
            Sales_Person__c = opportunityRecord.OwnerId,
            Commission_Rate__c = 0,
            Status__c = STATUS_ACCRUED,
            Amount_Basis__c = BASIS_INVOICED_TOTAL,
            Unique_Key__c = uniqueKey(opportunityRecord.Id, opportunityRecord.OwnerId)
        );
        Database.insert(commissionRecord, false);
    }

    public static void markPayable(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }
        BillingControl_OpportunityFinancials.Snapshot snapshot =
            BillingControl_OpportunityFinancials.load(new Set<Id>{ opportunityId }).get(opportunityId);
        if (snapshot == null || snapshot.paidInFull != true) {
            return;
        }

        List<Commission__c> commissionsToUpdate = new List<Commission__c>();
        for (Commission__c commissionRecord : [
            SELECT Id, Status__c, Payable_Date__c, Commission_Rate__c,
                Amount_Basis__c, Opportunity__c
            FROM Commission__c
            WHERE Opportunity__c = :opportunityId
            AND (Status__c = :STATUS_ACCRUED OR Status__c = NULL)
        ]) {
            commissionRecord.Status__c = STATUS_PAYABLE;
            commissionRecord.Payable_Date__c = Date.today();
            commissionRecord.Amount_Basis__c = BASIS_INVOICED_TOTAL;
            commissionsToUpdate.add(commissionRecord);
        }
        if (!commissionsToUpdate.isEmpty()) {
            update commissionsToUpdate;
        }
    }

    public static void payCommissions(
        List<Id> commissionIds,
        Date paidDate,
        Map<Id, Decimal> paidAmountOverrides
    ) {
        if (commissionIds == null || commissionIds.isEmpty()) {
            return;
        }
        Date effectivePaidDate = paidDate != null ? paidDate : Date.today();
        List<Commission__c> commissionsToUpdate = new List<Commission__c>();
        for (Commission__c commissionRecord : [
            SELECT Id, Status__c, Commission_Rate__c, Paid_Amount__c, Paid_Date__c, Opportunity__c
            FROM Commission__c
            WHERE Id IN :commissionIds
        ]) {
            if (commissionRecord.Status__c != STATUS_PAYABLE) {
                throw new AuraHandledException(
                    'Commission can only be paid when status is Payable. Customer receipts do not pay commissions.'
                );
            }
            BillingControl_OpportunityFinancials.Snapshot snapshot =
                BillingControl_OpportunityFinancials.load(new Set<Id>{ commissionRecord.Opportunity__c })
                    .get(commissionRecord.Opportunity__c);
            Decimal computedAmount = computedCommissionAmount(
                snapshot != null ? snapshot.invoicedTotal : 0,
                commissionRecord.Commission_Rate__c
            );
            Decimal paidAmount = paidAmountOverrides != null && paidAmountOverrides.containsKey(commissionRecord.Id)
                ? paidAmountOverrides.get(commissionRecord.Id)
                : computedAmount;
            if (paidAmount == null || paidAmount < 0) {
                throw new AuraHandledException('Commission paid amount must be greater than or equal to 0.');
            }
            commissionRecord.Status__c = STATUS_PAID;
            commissionRecord.Paid_Date__c = effectivePaidDate;
            commissionRecord.Paid_Amount__c = paidAmount;
            commissionsToUpdate.add(commissionRecord);
        }
        if (!commissionsToUpdate.isEmpty()) {
            update commissionsToUpdate;
        }
    }

    @AuraEnabled
    public static void paySelectedCommissions(List<Id> commissionIds, Date paidDate) {
        payCommissions(commissionIds, paidDate, null);
    }

    @AuraEnabled
    public static void setManualRate(Id commissionId, Decimal commissionRate) {
        if (commissionId == null) {
            throw new AuraHandledException('Select a commission.');
        }
        if (commissionRate == null || commissionRate < 0) {
            throw new AuraHandledException('Enter a commission rate of 0 or greater.');
        }
        Commission__c commissionRecord = [
            SELECT Id, Status__c, Opportunity__c, Commission_Rate__c, Amount_Basis__c
            FROM Commission__c
            WHERE Id = :commissionId
            LIMIT 1
            FOR UPDATE
        ];
        if (commissionRecord.Status__c == STATUS_PAID || commissionRecord.Status__c == STATUS_CANCELLED) {
            throw new AuraHandledException('Paid and cancelled commissions cannot change rate.');
        }
        commissionRecord.Commission_Rate__c = commissionRate;
        if (commissionRecord.Status__c == STATUS_PAYABLE) {
            commissionRecord.Amount_Basis__c = BASIS_INVOICED_TOTAL;
        }
        update commissionRecord;
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
        Date rangeStart = parseDate(startDate);
        Date rangeEnd = parseDate(endDate);
        Id ownerId = String.isBlank(opportunityOwnerId) ? null : (Id) opportunityOwnerId;

        TabRuntime tabRuntime = new TabRuntime();
        tabRuntime.warnings = new List<String>();
        tabRuntime.metrics = new MetricsWrapper();

        Map<String, SectionWrapper> sectionByKey = new Map<String, SectionWrapper>{
            SECTION_ACCRUED => emptySection(SECTION_ACCRUED, 'Accrued'),
            SECTION_PAYABLE => emptySection(SECTION_PAYABLE, 'Payable'),
            SECTION_PAID => emptySection(SECTION_PAID, 'Paid')
        };

        String soql =
            'SELECT Id, Status__c, Commission_Rate__c, Paid_Amount__c,'
            + ' Payable_Date__c, Paid_Date__c, Amount_Basis__c, Sales_Person__c, Sales_Person__r.Name,'
            + ' Opportunity__c, Opportunity__r.Name, Opportunity__r.Quote_Number__c, Opportunity__r.Amount,'
            + ' Opportunity__r.CloseDate, Opportunity__r.Account.Name, Opportunity__r.OwnerId'
            + ' FROM Commission__c'
            + ' WHERE Opportunity__c != NULL';
        if (ownerId != null) {
            soql += ' AND Opportunity__r.OwnerId = :ownerId';
        }
        soql += ' ORDER BY Sales_Person__r.Name NULLS LAST, Opportunity__r.Name NULLS LAST LIMIT 500';

        List<Commission__c> commissionRecords = Database.query(soql);
        Set<Id> opportunityIds = new Set<Id>();
        for (Commission__c commissionRecord : commissionRecords) {
            opportunityIds.add(commissionRecord.Opportunity__c);
        }
        Map<Id, BillingControl_OpportunityFinancials.Snapshot> financialsByOpportunityId =
            BillingControl_OpportunityFinancials.load(opportunityIds);

        for (Commission__c commissionRecord : commissionRecords) {
            CommissionRow row = toRow(commissionRecord, financialsByOpportunityId.get(commissionRecord.Opportunity__c));
            String statusValue = String.isBlank(commissionRecord.Status__c) ? STATUS_ACCRUED : commissionRecord.Status__c;
            if (statusValue == STATUS_PAID && isInRange(commissionRecord.Paid_Date__c, rangeStart, rangeEnd)) {
                addRow(sectionByKey.get(SECTION_PAID), row);
                tabRuntime.metrics.paidThisPeriodCount++;
                tabRuntime.metrics.paidThisPeriod += coalesce(row.paidAmount);
            } else if (
                row.customerPaidInFull == true
                && statusValue != STATUS_PAID
                && statusValue != STATUS_CANCELLED
            ) {
                Date accruedDate = commissionRecord.Payable_Date__c != null
                    ? commissionRecord.Payable_Date__c
                    : (commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.CloseDate : null);
                if (isInRange(accruedDate, rangeStart, rangeEnd)) {
                    addRow(sectionByKey.get(SECTION_ACCRUED), row);
                    tabRuntime.metrics.accruedCount++;
                    tabRuntime.metrics.accrued += coalesce(row.commissionAmount);
                }
                if (statusValue == STATUS_PAYABLE && isInRange(commissionRecord.Payable_Date__c, rangeStart, rangeEnd)) {
                    addRow(sectionByKey.get(SECTION_PAYABLE), row);
                    tabRuntime.metrics.payableCount++;
                    tabRuntime.metrics.payable += coalesce(row.commissionAmount);
                }
            }
        }

        tabRuntime.sections = new List<SectionWrapper>{
            sectionByKey.get(SECTION_ACCRUED),
            sectionByKey.get(SECTION_PAYABLE),
            sectionByKey.get(SECTION_PAID)
        };
        if (commissionRecords.isEmpty()) {
            tabRuntime.warnings.add('No commissions found.');
        }
        return tabRuntime;
    }

    private static CommissionRow toRow(
        Commission__c commissionRecord,
        BillingControl_OpportunityFinancials.Snapshot snapshot
    ) {
        CommissionRow row = new CommissionRow();
        row.commissionId = commissionRecord.Id;
        row.salespersonId = commissionRecord.Sales_Person__c;
        row.salespersonName = commissionRecord.Sales_Person__r != null ? commissionRecord.Sales_Person__r.Name : null;
        row.opportunityId = commissionRecord.Opportunity__c;
        row.opportunityName = commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.Name : null;
        row.quoteNumber = commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.Quote_Number__c : null;
        row.accountName = commissionRecord.Opportunity__r != null && commissionRecord.Opportunity__r.Account != null
            ? commissionRecord.Opportunity__r.Account.Name
            : null;
        row.jobAmount = commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.Amount : null;
        row.invoicedTotal = snapshot != null ? snapshot.invoicedTotal : 0;
        row.customerPaidTotal = snapshot != null ? snapshot.paidTotal : 0;
        row.customerPaidInFull = snapshot != null && snapshot.paidInFull == true;
        row.commissionRate = commissionRecord.Commission_Rate__c;
        row.commissionAmount = computedCommissionAmount(row.invoicedTotal, commissionRecord.Commission_Rate__c);
        row.status = commissionRecord.Status__c;
        row.closeDate = commissionRecord.Opportunity__r != null ? commissionRecord.Opportunity__r.CloseDate : null;
        row.payableDate = commissionRecord.Payable_Date__c;
        row.paidDate = commissionRecord.Paid_Date__c;
        row.paidAmount = commissionRecord.Paid_Amount__c;
        row.amountBasis = commissionRecord.Amount_Basis__c;
        row.canPay = row.customerPaidInFull == true && commissionRecord.Status__c == STATUS_PAYABLE;
        return row;
    }

    private static SectionWrapper emptySection(String categoryKey, String categoryLabel) {
        SectionWrapper section = new SectionWrapper();
        section.categoryKey = categoryKey;
        section.categoryLabel = categoryLabel;
        section.recordCount = 0;
        section.totalAmount = 0;
        section.rows = new List<CommissionRow>();
        return section;
    }

    private static void addRow(SectionWrapper section, CommissionRow row) {
        section.rows.add(row);
        section.recordCount++;
        section.totalAmount += coalesce(row.commissionAmount);
    }

    public static Decimal computedCommissionAmount(Decimal invoicedTotal, Decimal rate) {
        Decimal amount = coalesce(invoicedTotal);
        Decimal commissionRate = coalesce(rate);
        return (amount * commissionRate) / 100;
    }

    private static Boolean isInRange(Date value, Date rangeStart, Date rangeEnd) {
        if (rangeStart == null && rangeEnd == null) {
            return true;
        }
        if (value == null) {
            return false;
        }
        if (rangeStart != null && value < rangeStart) {
            return false;
        }
        if (rangeEnd != null && value > rangeEnd) {
            return false;
        }
        return true;
    }

    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return Date.valueOf(value);
    }

    private static Decimal coalesce(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String uniqueKey(Id opportunityId, Id salesPersonId) {
        return String.valueOf(opportunityId) + String.valueOf(salesPersonId);
    }
}
