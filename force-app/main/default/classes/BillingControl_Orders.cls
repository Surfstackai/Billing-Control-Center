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

    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';

    private static final String BUCKET_UNSCHEDULED = 'UNSCHEDULED';
    private static final String BUCKET_SCHEDULED = 'SCHEDULED';
    private static final String BUCKET_SCHEDULED_TODAY = 'SCHEDULED_TODAY';
    private static final String BUCKET_COMPLETED_THIS_WEEK = 'COMPLETED_THIS_WEEK';
    private static final String BUCKET_COMPLETED_THIS_MONTH = 'COMPLETED_THIS_MONTH';
    private static final String BUCKET_NO_OPPORTUNITY = 'NO_OPPORTUNITY';

    private static final String BUCKET_LABEL_UNSCHEDULED = 'Unscheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED = 'Scheduled Work';
    private static final String BUCKET_LABEL_SCHEDULED_TODAY = 'Scheduled for Today';
    private static final String BUCKET_LABEL_COMPLETED_THIS_WEEK = 'Completed This Week';
    private static final String BUCKET_LABEL_COMPLETED_THIS_MONTH = 'Completed This Month';
    private static final String BUCKET_LABEL_NO_OPPORTUNITY = 'Work Orders with No Opportunities';
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';
    private static final List<String> BUCKET_QUERY_ORDER = new List<String>{
        BUCKET_UNSCHEDULED,
        BUCKET_SCHEDULED,
        BUCKET_SCHEDULED_TODAY,
        BUCKET_COMPLETED_THIS_WEEK,
        BUCKET_COMPLETED_THIS_MONTH,
        BUCKET_NO_OPPORTUNITY
    };

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
        BillingMetricsSnapshot completedThisWeek = metricsByBucket.get(BUCKET_COMPLETED_THIS_WEEK);
        BillingMetricsSnapshot completedThisMonth = metricsByBucket.get(BUCKET_COMPLETED_THIS_MONTH);
        BillingMetricsSnapshot noOpportunity = metricsByBucket.get(BUCKET_NO_OPPORTUNITY);

        result.unscheduledCount = unscheduled != null ? unscheduled.recordCount : 0;
        result.unscheduledRevenue = unscheduled != null ? unscheduled.totalAmount : 0;

        result.scheduledCount = scheduled != null ? scheduled.recordCount : 0;
        result.scheduledRevenue = scheduled != null ? scheduled.totalAmount : 0;

        result.scheduledTodayCount = scheduledToday != null ? scheduledToday.recordCount : 0;
        result.scheduledTodayRevenue = scheduledToday != null ? scheduledToday.totalAmount : 0;

        result.completedThisWeekCount = completedThisWeek != null ? completedThisWeek.recordCount : 0;
        result.completedThisWeekRevenue = completedThisWeek != null ? completedThisWeek.totalAmount : 0;

        result.completedThisMonthCount = completedThisMonth != null ? completedThisMonth.recordCount : 0;
        result.completedThisMonthRevenue = completedThisMonth != null ? completedThisMonth.totalAmount : 0;

        result.noOpportunityCount = noOpportunity != null ? noOpportunity.recordCount : 0;
        result.noOpportunityRevenue = noOpportunity != null ? noOpportunity.totalAmount : 0;

        result.completedTodayCount = 0;
        result.completedTodayRevenue = 0;
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

        for (String bucketKey : BUCKET_QUERY_ORDER) {
            List<Order> diaryOrders = queryBucketOrders(bucketKey, null, filterContext);
            Boolean isTruncated = diaryOrders.size() >= QUERY_ROW_LIMIT;
            Integer maxIndex = Math.min(diaryOrders.size(), MAX_ROWS_PER_SECTION);
            List<WorkOrderRowWrapper> appointmentRows = new List<WorkOrderRowWrapper>();
            for (Integer index = 0; index < maxIndex; index++) {
                Order orderRecord = diaryOrders[index];
                if (!isActiveDiaryRecord(orderRecord)) {
                    continue;
                }
                appointmentRows.add(buildOrderDiaryRow(orderRecord));
            }

            if (isTruncated) {
                addRuntimeWarning(filterContext, BUCKET_LABELS.get(bucketKey) + ': ' + ROW_LIMIT_WARNING_MESSAGE);
            }

            if (filterContext != null && filterContext.filters != null && !filterContext.filters.isEmpty()) {
                appointmentRows = filterRows(appointmentRows, filterContext);
            }

            List<WorkOrderRowWrapper> groupedRows = groupOrderDiaryRowsByWorkOrder(appointmentRows);
            if (bucketKey == BUCKET_NO_OPPORTUNITY) {
                for (WorkOrderRowWrapper groupedRow : groupedRows) {
                    groupedRow.opportunityAmount = null;
                    if (groupedRow.relatedServiceAppointments != null) {
                        for (WorkOrderRowWrapper appointmentRow : groupedRow.relatedServiceAppointments) {
                            appointmentRow.opportunityAmount = null;
                        }
                    }
                }
            }
            rowsByBucketKey.get(bucketKey).addAll(groupedRows);
        }

        for (BucketSectionWrapper sectionRecord : sections) {
            sectionRecord.serviceAppointmentCount = 0;
            if (sectionRecord.rows != null) {
                for (WorkOrderRowWrapper row : sectionRecord.rows) {
                    sectionRecord.serviceAppointmentCount += row != null && row.serviceAppointmentCount != null
                        ? row.serviceAppointmentCount
                        : 0;
                }
                sectionRecord.rows.sort(new WorkOrderRowNumberComparator());
            }
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
                BUCKET_COMPLETED_THIS_WEEK,
                BUCKET_LABEL_COMPLETED_THIS_WEEK,
                new List<WorkOrderRowWrapper>()
            ),
            new BucketSectionWrapper(
                BUCKET_COMPLETED_THIS_MONTH,
                BUCKET_LABEL_COMPLETED_THIS_MONTH,
                new List<WorkOrderRowWrapper>()
            ),
            new BucketSectionWrapper(
                BUCKET_NO_OPPORTUNITY,
                BUCKET_LABEL_NO_OPPORTUNITY,
                new List<WorkOrderRowWrapper>()
            )
        };
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
        row.opportunityAmount = orderRecord != null && orderRecord.OpportunityId != null && orderRecord.Opportunity != null
            ? orderRecord.Opportunity.Amount
            : null;
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
        row.earliestStartTime = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.EarliestStartTime
            : null;
        row.schedStartTime = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.SchedStartTime
            : null;
        row.actualEndTime = orderRecord != null && orderRecord.Service_Appointment__r != null
            ? orderRecord.Service_Appointment__r.ActualEndTime
            : null;
        row.serviceAppointmentDisplay = buildServiceAppointmentDisplay(orderRecord);
        row.readyForBilling = orderRecord != null ? (Boolean) orderRecord.get('Ready_For_Billing__c') : null;
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
        Date referenceDate = orderRecord.Service_Appointment__r.EarliestStartTime != null
            ? orderRecord.Service_Appointment__r.EarliestStartTime.date()
            : (
                orderRecord.Service_Appointment__r.SchedStartTime != null
                    ? orderRecord.Service_Appointment__r.SchedStartTime.date()
                    : (
                        orderRecord.Service_Appointment__r.ActualEndTime != null
                            ? orderRecord.Service_Appointment__r.ActualEndTime.date()
                            : null
                    )
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

    private static List<WorkOrderRowWrapper> groupOrderDiaryRowsByWorkOrder(List<WorkOrderRowWrapper> appointmentRows) {
        List<WorkOrderRowWrapper> groupedRows = new List<WorkOrderRowWrapper>();
        if (appointmentRows == null || appointmentRows.isEmpty()) {
            return groupedRows;
        }

        Map<String, WorkOrderRowWrapper> rowByGroupingKey = new Map<String, WorkOrderRowWrapper>();
        for (WorkOrderRowWrapper appointmentRow : appointmentRows) {
            if (appointmentRow == null) {
                continue;
            }

            String groupingKey = buildGroupingKey(appointmentRow);
            WorkOrderRowWrapper groupedRow = rowByGroupingKey.get(groupingKey);
            if (groupedRow == null) {
                groupedRow = cloneOrderDiaryRow(appointmentRow);
                groupedRow.rowKey = appointmentRow.workOrderId != null
                    ? 'WO-' + String.valueOf(appointmentRow.workOrderId)
                    : appointmentRow.rowKey;
                groupedRow.relatedServiceAppointments = new List<WorkOrderRowWrapper>();
                groupedRow.serviceAppointmentCount = 0;
                rowByGroupingKey.put(groupingKey, groupedRow);
                groupedRows.add(groupedRow);
            }

            groupedRow.relatedServiceAppointments.add(cloneOrderDiaryRow(appointmentRow));
            groupedRow.serviceAppointmentCount++;
        }

        for (WorkOrderRowWrapper groupedRow : groupedRows) {
            groupedRow.opportunityAmount = resolveGroupedOpportunityAmount(groupedRow.relatedServiceAppointments);
        }

        return groupedRows;
    }

    private static Decimal resolveGroupedOpportunityAmount(List<WorkOrderRowWrapper> appointmentRows) {
        if (appointmentRows == null || appointmentRows.isEmpty()) {
            return null;
        }

        Id resolvedOpportunityId;
        for (WorkOrderRowWrapper appointmentRow : appointmentRows) {
            if (appointmentRow == null || appointmentRow.opportunityId == null) {
                return null;
            }
            if (resolvedOpportunityId == null) {
                resolvedOpportunityId = appointmentRow.opportunityId;
            } else if (resolvedOpportunityId != appointmentRow.opportunityId) {
                return null;
            }
        }

        return resolvedOpportunityId != null ? appointmentRows[0].opportunityAmount : null;
    }

    private static String buildGroupingKey(WorkOrderRowWrapper row) {
        if (row == null) {
            return null;
        }
        if (row.workOrderId != null) {
            return 'WORK_ORDER:' + String.valueOf(row.workOrderId);
        }
        return 'ORDER:' + String.valueOf(row.orderId);
    }

    private static WorkOrderRowWrapper cloneOrderDiaryRow(WorkOrderRowWrapper source) {
        if (source == null) {
            return null;
        }

        WorkOrderRowWrapper clone = new WorkOrderRowWrapper();
        clone.rowKey = source.rowKey;
        clone.orderId = source.orderId;
        clone.orderNumber = source.orderNumber;
        clone.workOrderId = source.workOrderId;
        clone.workOrderNumber = source.workOrderNumber;
        clone.subject = source.subject;
        clone.status = source.status;
        clone.accountId = source.accountId;
        clone.accountName = source.accountName;
        clone.opportunityId = source.opportunityId;
        clone.opportunityName = source.opportunityName;
        clone.opportunityAmount = source.opportunityAmount;
        clone.opportunityStageName = source.opportunityStageName;
        clone.opportunityCloseDate = source.opportunityCloseDate;
        clone.ownerId = source.ownerId;
        clone.ownerName = source.ownerName;
        clone.createdDate = source.createdDate;
        clone.serviceAppointmentId = source.serviceAppointmentId;
        clone.serviceAppointmentNumber = source.serviceAppointmentNumber;
        clone.serviceAppointmentStatus = source.serviceAppointmentStatus;
        clone.earliestStartTime = source.earliestStartTime;
        clone.schedStartTime = source.schedStartTime;
        clone.actualEndTime = source.actualEndTime;
        clone.serviceAppointmentDisplay = source.serviceAppointmentDisplay;
        clone.readyForBilling = source.readyForBilling;
        clone.invoicedAmount = source.invoicedAmount;
        clone.receivedAmount = source.receivedAmount;
        clone.outstandingAmount = source.outstandingAmount;
        clone.effectiveDate = source.effectiveDate;
        clone.serviceAppointmentCount = source.serviceAppointmentCount;
        return clone;
    }

    private static Map<String, BillingMetricsSnapshot> queryBucketMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext
    ) {
        Map<String, BillingMetricsSnapshot> metricsByBucket = new Map<String, BillingMetricsSnapshot>{
            BUCKET_UNSCHEDULED => new BillingMetricsSnapshot(),
            BUCKET_SCHEDULED => new BillingMetricsSnapshot(),
            BUCKET_SCHEDULED_TODAY => new BillingMetricsSnapshot(),
            BUCKET_COMPLETED_THIS_WEEK => new BillingMetricsSnapshot(),
            BUCKET_COMPLETED_THIS_MONTH => new BillingMetricsSnapshot(),
            BUCKET_NO_OPPORTUNITY => new BillingMetricsSnapshot()
        };

        for (String bucketKey : BUCKET_QUERY_ORDER) {
            if (!metricsByBucket.containsKey(bucketKey)) {
                continue;
            }

            Boolean useServiceAppointmentOpportunity = usesServiceAppointmentOpportunity(bucketKey);
            String opportunityIdField = useServiceAppointmentOpportunity
                ? 'Service_Appointment__r.Opportunity__c'
                : 'OpportunityId';
            String opportunityAmountField = useServiceAppointmentOpportunity
                ? 'Service_Appointment__r.Opportunity__r.Amount'
                : 'Opportunity.Amount';

            AggregateResult[] results = Database.query(
                'SELECT '
                + opportunityIdField
                + ' opportunityId, COUNT(Id) recordCount, MAX('
                + opportunityAmountField
                + ') opportunityAmount'
                + ' FROM Order'
                + buildOrdersWhereClause(filterContext, null, bucketKey)
                + ' GROUP BY '
                + opportunityIdField
            );
            BillingMetricsSnapshot snapshot = metricsByBucket.get(bucketKey);
            for (AggregateResult aggregateRow : results) {
                snapshot.recordCount += (Integer) aggregateRow.get('recordCount');
                Decimal opportunityAmount = (Decimal) aggregateRow.get('opportunityAmount');
                snapshot.totalAmount += opportunityAmount != null ? opportunityAmount : 0;
            }
        }
        return metricsByBucket;
    }

    private static List<Order> queryBucketOrders(
        String bucketKey,
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
            + ' Opportunity.Amount,'
            + ' Opportunity_Name__c,'
            + ' Opportunity_Stage__c,'
            + ' Opportunity.CloseDate,'
            + ' Work_Order__c,'
            + ' Work_Order_Number__c,'
            + ' Work_Order_Subject__c,'
            + ' Service_Appointment__c,'
            + ' Service_Appointment__r.AppointmentNumber,'
            + ' Service_Appointment__r.Status,'
            + ' Service_Appointment__r.EarliestStartTime,'
            + ' Service_Appointment__r.SchedStartTime,'
            + ' Service_Appointment__r.ActualEndTime,'
            + ' Technician__c,'
            + ' Technician__r.Name,'
            + ' Billing_Diary_Status__c,'
            + ' Ready_For_Billing__c,'
            + ' Invoiced_Amount__c,'
            + ' Received_Amount__c,'
            + ' Outstanding_Amount__c,'
            + ' EffectiveDate,'
            + ' CreatedDate'
            + ' FROM Order'
            + buildOrdersWhereClause(filterContext, diaryStatus, bucketKey)
            + ' ORDER BY OrderNumber ASC NULLS LAST, EffectiveDate ASC NULLS LAST, CreatedDate ASC NULLS LAST'
            + ' LIMIT '
            + QUERY_ROW_LIMIT;
        return Database.query(queryText);
    }

    private static String buildOrdersWhereClause(
        BillingControl_DataProvider.BillingFilterContextDTO filterContext,
        String enforcedDiaryStatus,
        String bucketKey
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
        clauses.addAll(buildBucketSpecificClauses(bucketKey));
        clauses.addAll(
            BillingControl_DataProvider.buildQueryFilterClauses(filterContext, getOrdersFilterFieldMappings())
        );
        return ' WHERE ' + String.join(clauses, ' AND ');
    }

    private static List<String> buildBucketSpecificClauses(String bucketKey) {
        List<String> clauses = new List<String>{ 'Service_Appointment__c != NULL' };

        Boolean isCompletedBucket =
            bucketKey == BUCKET_COMPLETED_THIS_WEEK || bucketKey == BUCKET_COMPLETED_THIS_MONTH;
        if (isCompletedBucket) {
            clauses.add(
                'Service_Appointment__r.Status = \''
                    + String.escapeSingleQuotes(SERVICE_APPOINTMENT_STATUS_COMPLETED)
                    + '\''
            );
        } else {
            clauses.add(
                'Service_Appointment__r.Status != \''
                    + String.escapeSingleQuotes(SERVICE_APPOINTMENT_STATUS_COMPLETED)
                    + '\''
            );
        }

        String todayWindowClause = buildSchedStartWindowClause(resolveTodayBound());
        String outsideTodayWindowClause = buildOutsideSchedStartWindowClause(resolveTodayBound());
        if (bucketKey == BUCKET_UNSCHEDULED) {
            clauses.add('Service_Appointment__r.SchedStartTime = NULL');
        } else if (bucketKey == BUCKET_SCHEDULED) {
            clauses.add('Service_Appointment__r.SchedStartTime != NULL');
            clauses.add(outsideTodayWindowClause);
        } else if (bucketKey == BUCKET_SCHEDULED_TODAY) {
            clauses.add('Service_Appointment__r.SchedStartTime != NULL');
            clauses.add(todayWindowClause);
        } else if (bucketKey == BUCKET_COMPLETED_THIS_WEEK) {
            clauses.add(buildActualEndWindowClause(resolveThisWeekBound()));
        } else if (bucketKey == BUCKET_COMPLETED_THIS_MONTH) {
            clauses.add(buildActualEndWindowClause(resolveThisMonthBound()));
        } else if (bucketKey == BUCKET_NO_OPPORTUNITY) {
            clauses.add('OpportunityId = NULL');
        }
        return clauses;
    }

    private static String buildSchedStartWindowClause(DatetimeBound bound) {
        return '(Service_Appointment__r.SchedStartTime >= '
            + bound.startLiteral
            + ' AND Service_Appointment__r.SchedStartTime < '
            + bound.endLiteral
            + ')';
    }

    private static String buildOutsideSchedStartWindowClause(DatetimeBound bound) {
        return '(Service_Appointment__r.SchedStartTime < '
            + bound.startLiteral
            + ' OR Service_Appointment__r.SchedStartTime >= '
            + bound.endLiteral
            + ')';
    }

    private static String buildActualEndWindowClause(DatetimeBound bound) {
        return '(Service_Appointment__r.ActualEndTime >= '
            + bound.startLiteral
            + ' AND Service_Appointment__r.ActualEndTime < '
            + bound.endLiteral
            + ')';
    }

    private static DatetimeBound resolveTodayBound() {
        return resolveDateBound(Date.today(), Date.today().addDays(1));
    }

    private static DatetimeBound resolveThisWeekBound() {
        Date weekStart = Date.today().toStartOfWeek();
        return resolveDateBound(weekStart, weekStart.addDays(7));
    }

    private static DatetimeBound resolveThisMonthBound() {
        Date monthStart = Date.today().toStartOfMonth();
        return resolveDateBound(monthStart, monthStart.addMonths(1));
    }

    private static DatetimeBound resolveDateBound(Date startDate, Date endDate) {
        // Date and Datetime.newInstance use the running user's timezone.
        Datetime startDateTime = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        Datetime endDateTime = Datetime.newInstance(endDate, Time.newInstance(0, 0, 0, 0));
        DatetimeBound bound = new DatetimeBound();
        bound.startLiteral = startDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        bound.endLiteral = endDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        return bound;
    }

    private class DatetimeBound {
        public String startLiteral;
        public String endLiteral;
    }

    private static Boolean usesServiceAppointmentOpportunity(String bucketKey) {
        return bucketKey == BUCKET_SCHEDULED_TODAY;
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
        @AuraEnabled public Decimal completedThisWeekRevenue;
        @AuraEnabled public Integer completedThisWeekCount;
        @AuraEnabled public Decimal completedThisMonthRevenue;
        @AuraEnabled public Integer completedThisMonthCount;
        @AuraEnabled public Decimal noOpportunityRevenue;
        @AuraEnabled public Integer noOpportunityCount;
        @AuraEnabled public Decimal noServiceAppointmentRevenue;
        @AuraEnabled public Integer noServiceAppointmentCount;
        @AuraEnabled public Decimal multipleOpportunitiesRevenue;
        @AuraEnabled public Integer multipleOpportunitiesCount;
        @AuraEnabled public Decimal completedTodayRevenue;
        @AuraEnabled public Integer completedTodayCount;
        @AuraEnabled public Decimal inProgressRevenue;
        @AuraEnabled public Integer inProgressCount;
    }

    public class BucketSectionWrapper {
        @AuraEnabled public String bucketKey;
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public List<WorkOrderRowWrapper> rows;

        public BucketSectionWrapper(String bucketKeyValue, String sectionLabelValue, List<WorkOrderRowWrapper> rowValues) {
            bucketKey = bucketKeyValue;
            sectionLabel = sectionLabelValue;
            serviceAppointmentCount = 0;
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
        @AuraEnabled public Datetime earliestStartTime;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime actualEndTime;
        @AuraEnabled public String serviceAppointmentDisplay;
        @AuraEnabled public Boolean readyForBilling;
        @AuraEnabled public Decimal invoicedAmount;
        @AuraEnabled public Decimal receivedAmount;
        @AuraEnabled public Decimal outstandingAmount;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Integer serviceAppointmentCount;
        @AuraEnabled public List<WorkOrderRowWrapper> relatedServiceAppointments;
        @AuraEnabled public Id ledgerId;
        @AuraEnabled public String workOrderStatus;
        @AuraEnabled public String reconciliationStatus;
        @AuraEnabled public Boolean attentionRequired;
        @AuraEnabled public String attentionReason;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public String depositStatus;
        @AuraEnabled public String partsStatus;
        @AuraEnabled public String invoiceNumbers;
        @AuraEnabled public Boolean billedBadge;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Date lastServiceDate;
        @AuraEnabled public Date nextServiceDate;
        @AuraEnabled public String accountOwnerName;
        @AuraEnabled public List<WorkOrderRowWrapper> relatedOpportunities;
    }

    public class TimelineEntryWrapper {
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public String eventType;
        @AuraEnabled public String eventLabel;
        @AuraEnabled public String oldValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public String changedByName;
        @AuraEnabled public String sourceObject;
        @AuraEnabled public String description;
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
        BUCKET_COMPLETED_THIS_WEEK => BUCKET_LABEL_COMPLETED_THIS_WEEK,
        BUCKET_COMPLETED_THIS_MONTH => BUCKET_LABEL_COMPLETED_THIS_MONTH,
        BUCKET_NO_OPPORTUNITY => BUCKET_LABEL_NO_OPPORTUNITY
    };
}