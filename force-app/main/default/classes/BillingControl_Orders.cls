/**
 * Billing Control Center Orders tab read model.
 * Phase 2B source of truth is Order diary data only; no legacy fallback rows are surfaced here.
 */
public with sharing class BillingControl_Orders {
    private static final String ORDER_DIARY_STATUS_DRAFT = 'Draft';
    private static final String ORDER_DIARY_STATUS_FOR_REVIEW = 'For Review';
    private static final String ORDER_DIARY_STATUS_READY_TO_BILL = 'Ready to Bill';
    private static final String ORDER_DIARY_STATUS_ON_HOLD = 'On Hold';
    private static final String ORDER_DIARY_STATUS_PAID = 'Paid';
    private static final String ORDER_DIARY_STATUS_CANCELLED = 'Cancelled';

    private static final Set<String> ACTIVE_ORDER_DIARY_STATUSES = new Set<String>{
        ORDER_DIARY_STATUS_DRAFT,
        ORDER_DIARY_STATUS_FOR_REVIEW,
        ORDER_DIARY_STATUS_READY_TO_BILL,
        ORDER_DIARY_STATUS_ON_HOLD
    };

    private static final Set<String> EXCLUDED_ORDER_DIARY_STATUSES = new Set<String>{
        ORDER_DIARY_STATUS_PAID,
        ORDER_DIARY_STATUS_CANCELLED
    };

    private static final String BUCKET_UNSCHEDULED = 'UNSCHEDULED';
    private static final String BUCKET_SCHEDULED = 'SCHEDULED';
    private static final String BUCKET_SCHEDULED_TODAY = 'SCHEDULED_TODAY';
    private static final String BUCKET_COMPLETED_TODAY = 'COMPLETED_TODAY';

    private static final String BUCKET_LABEL_UNSCHEDULED = 'Unscheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED = 'Scheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED_TODAY = 'Scheduled for Today';
    private static final String BUCKET_LABEL_COMPLETED_TODAY = 'Completed Today';
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';

    public static KpiWrapper getKpis() {
        return getKpis(null);
    }

    @AuraEnabled(cacheable=true)
    public static KpiWrapper getKpis(Long refreshToken) {
        return getKpis(refreshToken, null);
    }

    public static KpiWrapper getKpis(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        KpiWrapper result = new KpiWrapper();
        Map<String, BillingMetricsSnapshot> metricsByBucket = queryBucketMetrics(filterContext);

        BillingMetricsSnapshot unscheduled = metricsByBucket.get(BUCKET_UNSCHEDULED);
        BillingMetricsSnapshot scheduled = metricsByBucket.get(BUCKET_SCHEDULED);
        BillingMetricsSnapshot scheduledToday = metricsByBucket.get(BUCKET_SCHEDULED_TODAY);
        BillingMetricsSnapshot completedToday = metricsByBucket.get(BUCKET_COMPLETED_TODAY);

        result.unscheduledCount = unscheduled != null ? unscheduled.recordCount : 0;
        result.unscheduledRevenue = unscheduled != null ? unscheduled.totalAmount : 0;

        result.scheduledCount = scheduled != null ? scheduled.recordCount : 0;
        result.scheduledRevenue = scheduled != null ? scheduled.totalAmount : 0;

        result.scheduledTodayCount = scheduledToday != null ? scheduledToday.recordCount : 0;
        result.scheduledTodayRevenue = scheduledToday != null ? scheduledToday.totalAmount : 0;

        result.completedTodayCount = completedToday != null ? completedToday.recordCount : 0;
        result.completedTodayRevenue = completedToday != null ? completedToday.totalAmount : 0;

        result.inProgressCount = 0;
        result.inProgressRevenue = 0;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static KpiWrapper getOrdersKpiData() {
        return getKpis();
    }

    public static List<BucketSectionWrapper> getBucketWorkOrders() {
        return getBucketWorkOrders(null);
    }

    @AuraEnabled(cacheable=true)
    public static List<BucketSectionWrapper> getBucketWorkOrders(Long refreshToken) {
        return getBucketWorkOrders(refreshToken, null);
    }

    public static List<BucketSectionWrapper> getBucketWorkOrders(
        Long refreshToken,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<BucketSectionWrapper> sections = buildDefaultBucketSections();
        Map<String, List<WorkOrderRowWrapper>> rowsByBucketKey = new Map<String, List<WorkOrderRowWrapper>>();
        for (BucketSectionWrapper sectionRecord : sections) {
            rowsByBucketKey.put(sectionRecord.bucketKey, sectionRecord.rows);
        }

        for (String bucketKey : new List<String>{ BUCKET_UNSCHEDULED, BUCKET_SCHEDULED, BUCKET_SCHEDULED_TODAY, BUCKET_COMPLETED_TODAY }) {
            String diaryStatus = getDiaryStatusForBucket(bucketKey);
            if (String.isBlank(diaryStatus)) {
                continue;
            }

            List<Order> diaryOrders = queryBucketOrders(diaryStatus, filterContext);
            Boolean isTruncated = diaryOrders.size() >= QUERY_ROW_LIMIT;
            Integer maxIndex = Math.min(diaryOrders.size(), MAX_ROWS_PER_SECTION);
            for (Integer index = 0; index < maxIndex; index++) {
                Order orderRecord = diaryOrders[index];
                if (!isActiveDiaryRecord(orderRecord)) {
                    continue;
                }
                rowsByBucketKey.get(bucketKey).add(buildOrderDiaryRow(orderRecord));
            }

            if (isTruncated) {
                addRuntimeWarning(filterContext, BUCKET_LABELS.get(bucketKey) + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            }
        }

        for (BucketSectionWrapper sectionRecord : sections) {
            if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
                sectionRecord.rows = filterRows(sectionRecord.rows, filterContext);
            }
            sectionRecord.rows.sort(new WorkOrderRowNumberComparator());
        }

        return sections;
    }

    @AuraEnabled(cacheable=true)
    public static List<OrderRowWrapper> getOrders() {
        return new List<OrderRowWrapper>();
    }

    private static Boolean isActiveDiaryRecord(Order orderRecord) {
        String diaryStatus = orderRecord != null ? (String) orderRecord.get('Billing_Diary_Status__c') : null;
        if (String.isBlank(diaryStatus)) {
            return false;
        }
        if (EXCLUDED_ORDER_DIARY_STATUSES.contains(diaryStatus)) {
            return false;
        }
        return ACTIVE_ORDER_DIARY_STATUSES.contains(diaryStatus);
    }

    private static String resolveBucketKey(Order orderRecord) {
        String diaryStatus = orderRecord != null ? (String) orderRecord.get('Billing_Diary_Status__c') : null;
        if (diaryStatus == ORDER_DIARY_STATUS_DRAFT) {
            return BUCKET_UNSCHEDULED;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_FOR_REVIEW) {
            return BUCKET_SCHEDULED;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_READY_TO_BILL) {
            return BUCKET_SCHEDULED_TODAY;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_ON_HOLD) {
            return BUCKET_COMPLETED_TODAY;
        }
        return null;
    }

    private static List<BucketSectionWrapper> buildDefaultBucketSections() {
        return new List<BucketSectionWrapper>{
            new BucketSectionWrapper(BUCKET_UNSCHEDULED, BUCKET_LABEL_UNSCHEDULED, new List<WorkOrderRowWrapper>()),
            new BucketSectionWrapper(BUCKET_SCHEDULED, BUCKET_LABEL_SCHEDULED, new List<WorkOrderRowWrapper>()),
            new BucketSectionWrapper(
                BUCKET_SCHEDULED_TODAY,
                BUCKET_LABEL_SCHEDULED_TODAY,
                new List<WorkOrderRowWrapper>()
            ),
            new BucketSectionWrapper(
                BUCKET_COMPLETED_TODAY,
                BUCKET_LABEL_COMPLETED_TODAY,
                new List<WorkOrderRowWrapper>()
            )
        };
    }

    private static BucketSectionWrapper findSectionByKey(List<BucketSectionWrapper> sections, String sectionKey) {
        if (sections == null || String.isBlank(sectionKey)) {
            return null;
        }
        for (BucketSectionWrapper sectionRecord : sections) {
            if (sectionRecord.bucketKey == sectionKey) {
                return sectionRecord;
            }
        }
        return null;
    }

    private static Decimal sumBillableAmount(List<WorkOrderRowWrapper> rows) {
        Decimal total = 0;
        if (rows == null) {
            return total;
        }
        for (WorkOrderRowWrapper row : rows) {
            total += row.opportunityAmount != null ? row.opportunityAmount : 0;
        }
        return total;
    }

    private static WorkOrderRowWrapper buildOrderDiaryRow(Order orderRecord) {
        WorkOrderRowWrapper row = new WorkOrderRowWrapper();
        row.rowKey = orderRecord != null && orderRecord.Id != null ? 'ORD-' + String.valueOf(orderRecord.Id) : null;
        row.orderId = orderRecord != null ? orderRecord.Id : null;
        row.orderNumber = orderRecord != null ? orderRecord.OrderNumber : null;
        row.workOrderId = orderRecord != null ? (Id) orderRecord.get('Work_Order__c') : null;
        row.workOrderNumber = orderRecord != null ? (String) orderRecord.get('Work_Order_Number__c') : null;
        row.subject = coalesceText(
            orderRecord != null ? (String) orderRecord.get('Work_Order_Subject__c') : null,
            orderRecord != null ? orderRecord.Name : null
        );
        row.status = orderRecord != null ? (String) orderRecord.get('Billing_Diary_Status__c') : null;
        row.accountId = orderRecord != null ? orderRecord.AccountId : null;
        row.accountName = orderRecord != null ? (String) orderRecord.get('Account_Name__c') : null;
        row.opportunityId = orderRecord != null ? orderRecord.OpportunityId : null;
        row.opportunityName = orderRecord != null ? (String) orderRecord.get('Opportunity_Name__c') : null;
        row.opportunityAmount = orderRecord != null ? (Decimal) orderRecord.get('Billable_Amount__c') : null;
        row.opportunityStageName = orderRecord != null ? (String) orderRecord.get('Opportunity_Stage__c') : null;
        row.opportunityCloseDate = orderRecord != null && orderRecord.Opportunity != null
            ? orderRecord.Opportunity.CloseDate
            : null;
        row.ownerId = orderRecord != null ? (Id) orderRecord.get('Technician__c') : null;
        row.ownerName = orderRecord != null && orderRecord.Technician__r != null
            ? orderRecord.Technician__r.Name
            : null;
        row.createdDate = orderRecord != null ? orderRecord.CreatedDate : null;
        row.serviceAppointmentId = orderRecord != null ? (Id) orderRecord.get('Service_Appointment__c') : null;
        row.serviceAppointmentNumber = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.AppointmentNumber
            : null;
        row.serviceAppointmentStatus = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.Status
            : null;
        row.schedStartTime = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.SchedStartTime
            : null;
        row.actualEndTime = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.ActualEndTime
            : null;
        row.serviceAppointmentDisplay = buildServiceAppointmentDisplay(orderRecord);
        row.readyForBilling = orderRecord != null ? (Boolean) orderRecord.get('Ready_For_Billing__c') : null;
        row.billableAmount = orderRecord != null ? (Decimal) orderRecord.get('Billable_Amount__c') : null;
        row.invoicedAmount = orderRecord != null ? (Decimal) orderRecord.get('Invoiced_Amount__c') : null;
        row.receivedAmount = orderRecord != null ? (Decimal) orderRecord.get('Received_Amount__c') : null;
        row.outstandingAmount = orderRecord != null ? (Decimal) orderRecord.get('Outstanding_Amount__c') : null;
        row.effectiveDate = orderRecord != null ? orderRecord.EffectiveDate : null;
        return row;
    }

    private static String buildServiceAppointmentDisplay(Order orderRecord) {
        if (orderRecord == null || orderRecord.Service_Appointment__r == null) {
            return null;
        }

        String appointmentName = String.isNotBlank(orderRecord.Service_Appointment__r.AppointmentNumber)
            ? orderRecord.Service_Appointment__r.AppointmentNumber
            : String.valueOf(orderRecord.get('Service_Appointment__c'));
        String appointmentStatus = String.isNotBlank(orderRecord.Service_Appointment__r.Status)
            ? orderRecord.Service_Appointment__r.Status
            : '';
        Date referenceDate = orderRecord.Service_Appointment__r.ActualEndTime != null
            ? orderRecord.Service_Appointment__r.ActualEndTime.date()
            : (
                orderRecord.Service_Appointment__r.SchedStartTime != null
                    ? orderRecord.Service_Appointment__r.SchedStartTime.date()
                    : null
            );
        String scheduledDate = referenceDate != null ? formatDateAsIso(referenceDate) : '';
        return String.join(new List<String>{ appointmentName, appointmentStatus, scheduledDate }, ': ');
    }

    private static String formatDateAsIso(Date value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.year())
            + '-'
            + String.valueOf(value.month()).leftPad(2, '0')
            + '-'
            + String.valueOf(value.day()).leftPad(2, '0');
    }

    private static String coalesceText(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }

    private static Map<String, BillingMetricsSnapshot> queryBucketMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Map<String, BillingMetricsSnapshot> metricsByBucket = new Map<String, BillingMetricsSnapshot>{
            BUCKET_UNSCHEDULED => new BillingMetricsSnapshot(),
            BUCKET_SCHEDULED => new BillingMetricsSnapshot(),
            BUCKET_SCHEDULED_TODAY => new BillingMetricsSnapshot(),
            BUCKET_COMPLETED_TODAY => new BillingMetricsSnapshot()
        };

        String queryText =
            'SELECT Billing_Diary_Status__c diaryStatus, COUNT(Id) recordCount, SUM(Billable_Amount__c) totalAmount'
            + ' FROM Order'
            + buildOrdersWhereClause(filterContext, null)
            + ' GROUP BY Billing_Diary_Status__c';
        for (AggregateResult aggregateRow : Database.query(queryText)) {
            String bucketKey = resolveBucketKeyFromStatus((String) aggregateRow.get('diaryStatus'));
            if (bucketKey == null || !metricsByBucket.containsKey(bucketKey)) {
                continue;
            }

            BillingMetricsSnapshot snapshot = metricsByBucket.get(bucketKey);
            snapshot.recordCount = (Integer) aggregateRow.get('recordCount');
            snapshot.totalAmount = aggregateRow.get('totalAmount') != null
                ? (Decimal) aggregateRow.get('totalAmount')
                : 0;
        }
        return metricsByBucket;
    }

    private static List<Order> queryBucketOrders(
        String diaryStatus,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        String queryText =
            'SELECT Id,'
            + ' Name,'
            + ' OrderNumber,'
            + ' AccountId,'
            + ' Account_Name__c,'
            + ' OpportunityId,'
            + ' Opportunity_Name__c,'
            + ' Opportunity_Stage__c,'
            + ' Opportunity.CloseDate,'
            + ' Work_Order__c,'
            + ' Work_Order_Number__c,'
            + ' Work_Order_Subject__c,'
            + ' Service_Appointment__c,'
            + ' Service_Appointment__r.AppointmentNumber,'
            + ' Service_Appointment__r.Status,'
            + ' Service_Appointment__r.SchedStartTime,'
            + ' Service_Appointment__r.ActualEndTime,'
            + ' Technician__c,'
            + ' Technician__r.Name,'
            + ' Billing_Diary_Status__c,'
            + ' Ready_For_Billing__c,'
            + ' Billable_Amount__c,'
            + ' Invoiced_Amount__c,'
            + ' Received_Amount__c,'
            + ' Outstanding_Amount__c,'
            + ' EffectiveDate,'
            + ' CreatedDate'
            + ' FROM Order'
            + buildOrdersWhereClause(filterContext, diaryStatus)
            + ' ORDER BY OrderNumber ASC NULLS LAST, EffectiveDate ASC NULLS LAST, CreatedDate ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT;
        return Database.query(queryText);
    }

    private static String buildOrdersWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        String enforcedDiaryStatus
    ) {
        List<String> clauses = new List<String>();
        if (String.isBlank(enforcedDiaryStatus)) {
            clauses.add('Billing_Diary_Status__c IN (' + joinQuotedValues(new List<String>{
                ORDER_DIARY_STATUS_DRAFT,
                ORDER_DIARY_STATUS_FOR_REVIEW,
                ORDER_DIARY_STATUS_READY_TO_BILL,
                ORDER_DIARY_STATUS_ON_HOLD
            }) + ')');
        } else {
            clauses.add('Billing_Diary_Status__c = \'' + String.escapeSingleQuotes(enforcedDiaryStatus) + '\'');
        }
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getOrdersFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static Map<String, BillingControl_DataProvider.FilterFieldDescriptor> getOrdersFilterFieldMappings() {
        return new Map<String, BillingControl_DataProvider.FilterFieldDescriptor>{
            'ORDER.BILLING_DIARY_STATUS__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Billing_Diary_Status__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_STRING
            ),
            'ORDER.READY_FOR_BILLING__C' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Ready_For_Billing__c',
                BillingControl_DataProvider.FILTER_DATA_TYPE_BOOLEAN
            ),
            'ORDER.EFFECTIVEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'EffectiveDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            ),
            'ORDER.CREATEDDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'CreatedDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATETIME
            ),
            'OPPORTUNITY.STAGENAME' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity.StageName',
                BillingControl_DataProvider.FILTER_DATA_TYPE_STRING
            ),
            'OPPORTUNITY.CLOSEDATE' => new BillingControl_DataProvider.FilterFieldDescriptor(
                'Opportunity.CloseDate',
                BillingControl_DataProvider.FILTER_DATA_TYPE_DATE
            )
        };
    }

    private static String getDiaryStatusForBucket(String bucketKey) {
        if (bucketKey == BUCKET_UNSCHEDULED) {
            return ORDER_DIARY_STATUS_DRAFT;
        }
        if (bucketKey == BUCKET_SCHEDULED) {
            return ORDER_DIARY_STATUS_FOR_REVIEW;
        }
        if (bucketKey == BUCKET_SCHEDULED_TODAY) {
            return ORDER_DIARY_STATUS_READY_TO_BILL;
        }
        if (bucketKey == BUCKET_COMPLETED_TODAY) {
            return ORDER_DIARY_STATUS_ON_HOLD;
        }
        return null;
    }

    private static String resolveBucketKeyFromStatus(String diaryStatus) {
        if (diaryStatus == ORDER_DIARY_STATUS_DRAFT) {
            return BUCKET_UNSCHEDULED;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_FOR_REVIEW) {
            return BUCKET_SCHEDULED;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_READY_TO_BILL) {
            return BUCKET_SCHEDULED_TODAY;
        }
        if (diaryStatus == ORDER_DIARY_STATUS_ON_HOLD) {
            return BUCKET_COMPLETED_TODAY;
        }
        return null;
    }

    private static void addRuntimeWarning(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        String warning
    ) {
        if (filterContext == null || String.isBlank(warning)) {
            return;
        }
        if (filterContext.runtimeWarnings == null) {
            filterContext.runtimeWarnings = new List<String>();
        }
        if (!filterContext.runtimeWarnings.contains(warning)) {
            filterContext.runtimeWarnings.add(warning);
        }
    }

    private static String joinQuotedValues(List<String> values) {
        List<String> quotedValues = new List<String>();
        for (String value : values) {
            quotedValues.add('\'' + String.escapeSingleQuotes(value) + '\'');
        }
        return String.join(quotedValues, ', ');
    }

    private static List<WorkOrderRowWrapper> filterRows(
        List<WorkOrderRowWrapper> rows,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        List<WorkOrderRowWrapper> filteredRows = new List<WorkOrderRowWrapper>();
        for (WorkOrderRowWrapper row : rows) {
            if (matchesOrdersFilters(row, filterContext)) {
                filteredRows.add(row);
            }
        }
        return filteredRows;
    }

    private static Boolean matchesOrdersFilters(
        WorkOrderRowWrapper row,
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty()) {
            return true;
        }

        for (BillingControl_DataProvider.BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeFilterValue(filterRecord.objectApiName)
                + '.'
                + normalizeFilterValue(filterRecord.fieldApiName);
            Object fieldValue;

            if (fieldKey == 'ORDER.BILLING_DIARY_STATUS__C') {
                fieldValue = row.status;
            } else if (fieldKey == 'ORDER.READY_FOR_BILLING__C') {
                fieldValue = row.readyForBilling;
            } else if (fieldKey == 'ORDER.EFFECTIVEDATE') {
                fieldValue = row.effectiveDate;
            } else if (fieldKey == 'ORDER.CREATEDDATE') {
                fieldValue = row.createdDate;
            } else if (fieldKey == 'OPPORTUNITY.STAGENAME') {
                fieldValue = row.opportunityStageName;
            } else if (fieldKey == 'OPPORTUNITY.CLOSEDATE') {
                fieldValue = row.opportunityCloseDate;
            } else {
                continue;
            }

            if (!evaluateFilter(fieldValue, filterRecord)) {
                return false;
            }
        }

        return true;
    }

    private static Boolean evaluateFilter(Object fieldValue, BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        String operatorValue = normalizeFilterValue(filterRecord.operator);
        if (operatorValue == 'IS NULL') {
            return fieldValue == null;
        }
        if (operatorValue == 'IS NOT NULL') {
            return fieldValue != null;
        }
        if (fieldValue == null) {
            return false;
        }

        if (fieldValue instanceof Datetime) {
            Datetime comparisonValue = resolveDatetimeFilterValue(filterRecord);
            if (comparisonValue == null) {
                return false;
            }
            return compareComparable(((Datetime) fieldValue).getTime(), comparisonValue.getTime(), operatorValue);
        }

        if (fieldValue instanceof Date) {
            Date comparisonValue = resolveDateFilterValue(filterRecord);
            if (comparisonValue == null) {
                return false;
            }
            Long fieldDays = Long.valueOf(String.valueOf(Date.newInstance(1900, 1, 1).daysBetween((Date) fieldValue)));
            Long comparisonDays = Long.valueOf(String.valueOf(Date.newInstance(1900, 1, 1).daysBetween(comparisonValue)));
            return compareComparable(fieldDays, comparisonDays, operatorValue);
        }

        return compareStringValue(String.valueOf(fieldValue), filterRecord, operatorValue);
    }

    private static Boolean compareStringValue(
        String fieldValue,
        BillingControl_DataProvider.BillingFilterDTO filterRecord,
        String operatorValue
    ) {
        String normalizedFieldValue = normalizeFilterValue(fieldValue);
        List<String> comparisonValues = splitFilterValues(filterRecord.value);
        if (operatorValue == 'EQUALS') {
            return normalizedFieldValue == normalizeFilterValue(filterRecord.value);
        }
        if (operatorValue == 'NOT EQUALS') {
            return normalizedFieldValue != normalizeFilterValue(filterRecord.value);
        }
        if (operatorValue == 'IN') {
            return comparisonValues.contains(normalizedFieldValue);
        }
        if (operatorValue == 'NOT IN') {
            return !comparisonValues.contains(normalizedFieldValue);
        }
        return false;
    }

    private static Boolean compareComparable(Long fieldValue, Long comparisonValue, String operatorValue) {
        if (operatorValue == 'EQUALS') {
            return fieldValue == comparisonValue;
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldValue != comparisonValue;
        }
        if (operatorValue == 'GREATER THAN') {
            return fieldValue > comparisonValue;
        }
        if (operatorValue == 'GREATER OR EQUAL') {
            return fieldValue >= comparisonValue;
        }
        if (operatorValue == 'LESS THAN') {
            return fieldValue < comparisonValue;
        }
        if (operatorValue == 'LESS OR EQUAL') {
            return fieldValue <= comparisonValue;
        }
        return false;
    }

    private static Datetime resolveDatetimeFilterValue(BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        if (normalizeFilterValue(filterRecord.valueType) == 'DATE LITERAL') {
            Date literalDate = resolveDateLiteralValue(filterRecord.value);
            return literalDate == null ? null : Datetime.newInstance(literalDate, Time.newInstance(0, 0, 0, 0));
        }
        try {
            return Datetime.valueOf(filterRecord.value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date resolveDateFilterValue(BillingControl_DataProvider.BillingFilterDTO filterRecord) {
        if (normalizeFilterValue(filterRecord.valueType) == 'DATE LITERAL') {
            return resolveDateLiteralValue(filterRecord.value);
        }
        try {
            return Date.valueOf(filterRecord.value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date resolveDateLiteralValue(String value) {
        String normalizedValue = normalizeFilterValue(value);
        Date todayDate = Date.today();
        if (normalizedValue == 'TODAY') {
            return todayDate;
        }
        if (normalizedValue == 'YESTERDAY') {
            return todayDate.addDays(-1);
        }
        if (normalizedValue == 'TOMORROW') {
            return todayDate.addDays(1);
        }
        if (normalizedValue == 'THIS WEEK') {
            return todayDate.toStartOfWeek();
        }
        if (normalizedValue == 'THIS MONTH') {
            return Date.newInstance(todayDate.year(), todayDate.month(), 1);
        }
        if (normalizedValue == 'THIS QUARTER') {
            Integer quarterStartMonth = (((todayDate.month() - 1) / 3) * 3) + 1;
            return Date.newInstance(todayDate.year(), quarterStartMonth, 1);
        }
        if (normalizedValue == 'THIS YEAR') {
            return Date.newInstance(todayDate.year(), 1, 1);
        }
        if (normalizedValue != null && normalizedValue.startsWith('LAST_N_DAYS:')) {
            return todayDate.addDays(-Integer.valueOf(normalizedValue.substring('LAST_N_DAYS:'.length())));
        }
        if (normalizedValue != null && normalizedValue.startsWith('NEXT_N_DAYS:')) {
            return todayDate.addDays(Integer.valueOf(normalizedValue.substring('NEXT_N_DAYS:'.length())));
        }
        if (normalizedValue != null && normalizedValue.startsWith('LAST_N_YEARS:')) {
            return todayDate.addYears(-Integer.valueOf(normalizedValue.substring('LAST_N_YEARS:'.length())));
        }
        return null;
    }

    private static List<String> splitFilterValues(String value) {
        List<String> values = new List<String>();
        if (String.isBlank(value)) {
            return values;
        }
        for (String token : value.split(';')) {
            values.add(normalizeFilterValue(token));
        }
        return values;
    }

    private static String normalizeFilterValue(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    private class WorkOrderRowNumberComparator implements Comparator<WorkOrderRowWrapper> {
        public Integer compare(WorkOrderRowWrapper left, WorkOrderRowWrapper right) {
            String leftNumber = String.isNotBlank(left.workOrderNumber)
                ? left.workOrderNumber
                : (String.isNotBlank(left.orderNumber) ? left.orderNumber : '');
            String rightNumber = String.isNotBlank(right.workOrderNumber)
                ? right.workOrderNumber
                : (String.isNotBlank(right.orderNumber) ? right.orderNumber : '');
            Integer numberCompare = leftNumber.compareTo(rightNumber);
            if (numberCompare != 0) {
                return numberCompare;
            }
            String leftSubject = String.isNotBlank(left.subject) ? left.subject : '';
            String rightSubject = String.isNotBlank(right.subject) ? right.subject : '';
            Integer subjectCompare = leftSubject.compareTo(rightSubject);
            if (subjectCompare != 0) {
                return subjectCompare;
            }
            String leftKey = String.isNotBlank(left.rowKey) ? left.rowKey : '';
            String rightKey = String.isNotBlank(right.rowKey) ? right.rowKey : '';
            return leftKey.compareTo(rightKey);
        }
    }

    public class KpiWrapper {
        @AuraEnabled public Decimal unscheduledRevenue;
        @AuraEnabled public Integer unscheduledCount;
        @AuraEnabled public Decimal scheduledRevenue;
        @AuraEnabled public Integer scheduledCount;
        @AuraEnabled public Decimal scheduledTodayRevenue;
        @AuraEnabled public Integer scheduledTodayCount;
        @AuraEnabled public Decimal completedTodayRevenue;
        @AuraEnabled public Integer completedTodayCount;
        @AuraEnabled public Decimal inProgressRevenue;
        @AuraEnabled public Integer inProgressCount;
    }

    public class BucketSectionWrapper {
        @AuraEnabled public String bucketKey;
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public List<WorkOrderRowWrapper> rows;

        public BucketSectionWrapper(String bucketKeyValue, String sectionLabelValue, List<WorkOrderRowWrapper> rowValues) {
            bucketKey = bucketKeyValue;
            sectionLabel = sectionLabelValue;
            rows = rowValues;
        }
    }

    public class WorkOrderRowWrapper {
        @AuraEnabled public String rowKey;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public String opportunityStageName;
        @AuraEnabled public Date opportunityCloseDate;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String serviceAppointmentNumber;
        @AuraEnabled public String serviceAppointmentStatus;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime actualEndTime;
        @AuraEnabled public String serviceAppointmentDisplay;
        @AuraEnabled public Boolean readyForBilling;
        @AuraEnabled public Decimal billableAmount;
        @AuraEnabled public Decimal invoicedAmount;
        @AuraEnabled public Decimal receivedAmount;
        @AuraEnabled public Decimal outstandingAmount;
        @AuraEnabled public Date effectiveDate;
    }

    public class OrderRowWrapper {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal opportunityAmount;
        @AuraEnabled public String opportunityStageName;
        @AuraEnabled public Date opportunityCloseDate;
        @AuraEnabled public String workOrderLabel;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Datetime activatedDate;
    }

    private class BillingMetricsSnapshot {
        public Integer recordCount = 0;
        public Decimal totalAmount = 0;
    }

    private static final Map<String, String> BUCKET_LABELS = new Map<String, String>{
        BUCKET_UNSCHEDULED => BUCKET_LABEL_UNSCHEDULED,
        BUCKET_SCHEDULED => BUCKET_LABEL_SCHEDULED,
        BUCKET_SCHEDULED_TODAY => BUCKET_LABEL_SCHEDULED_TODAY,
        BUCKET_COMPLETED_TODAY => BUCKET_LABEL_COMPLETED_TODAY
    };
}