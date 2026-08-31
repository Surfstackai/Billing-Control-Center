/**
 * Shared Billing Control Center filter DTOs and date-window helpers.
 * Serialized field names stay identical to the former DataProvider inner types.
 */
public with sharing class BillingControl_BillingFilters {
    private static final String DATA_SOURCE_TYPE_APEX_HANDLER = 'APEX HANDLER';
    private static final Set<String> SUPPORTED_VALUE_TYPES = new Set<String>{ 'STATIC', 'DATE LITERAL' };
    private static final Set<String> SUPPORTED_OPERATORS = new Set<String>{
        'EQUALS',
        'NOT EQUALS',
        'IN',
        'NOT IN',
        'GREATER THAN',
        'GREATER OR EQUAL',
        'LESS THAN',
        'LESS OR EQUAL',
        'IS NULL',
        'IS NOT NULL'
    };
    private static final String ORDERS_TAB_KEY = 'ORDERS';
    private static final String INVOICING_TAB_KEY = 'INVOICING';
    private static final String RECEIVABLES_TAB_KEY = 'RECEIVABLES';

    private static final String ORDERS_DATASET_KEY = 'ORDERS_WORK_ORDERS';
    private static final String INVOICING_DATASET_KEY = 'INVOICING_SERVICE_APPOINTMENTS';
    private static final String RECEIVABLES_INVOICES_DATASET_KEY = 'RECEIVABLES_INVOICES';
    private static final String RECEIVABLES_COMMISSIONS_DATASET_KEY = 'RECEIVABLES_COMMISSIONS';
    public static final String FILTER_DATA_TYPE_STRING = 'STRING';
    public static final String FILTER_DATA_TYPE_BOOLEAN = 'BOOLEAN';
    public static final String FILTER_DATA_TYPE_DATE = 'DATE';
    public static final String FILTER_DATA_TYPE_DATETIME = 'DATETIME';
    public static final String FILTER_DATA_TYPE_DECIMAL = 'DECIMAL';
    public static final String FILTER_DATA_TYPE_ID = 'ID';

    public static BillingControl_ConfigService.DatasetConfigDTO findDataset(
        BillingControl_ConfigService.TabConfigDTO tabConfig,
        String datasetDeveloperKey
    ) {
        if (tabConfig == null || String.isBlank(datasetDeveloperKey) || tabConfig.datasets == null) {
            return null;
        }

        String normalizedKey = normalizeKey(datasetDeveloperKey);
        for (BillingControl_ConfigService.DatasetConfigDTO dataset : tabConfig.datasets) {
            if (normalizeKey(dataset != null ? dataset.developerKey : null) == normalizedKey) {
                return dataset;
            }
        }
        return null;
    }

    public static BillingFilterContextDTO buildFilterContext(
        BillingControl_ConfigService.TabConfigDTO tabConfig,
        BillingControl_ConfigService.DatasetConfigDTO datasetConfig,
        List<String> responseWarnings
    ) {
        BillingFilterContextDTO context = new BillingFilterContextDTO();
        context.tabKey = tabConfig != null ? tabConfig.developerKey : null;
        context.datasetKey = datasetConfig != null ? datasetConfig.developerKey : null;

        if (tabConfig == null || datasetConfig == null || tabConfig.id == null || datasetConfig.id == null) {
            return context;
        }

        if (!Billing_Center_Filter_Config__c.SObjectType.getDescribe().isAccessible()) {
            context.warnings.add('Billing Center filter config object is not accessible.');
            responseWarnings.addAll(context.warnings);
            return context;
        }

        for (Billing_Center_Filter_Config__c record : [
            SELECT Id, Developer_Key__c, Object_API_Name__c, Field_API_Name__c, Operator__c, Value__c,
                Value_Type__c, Sequence__c, Dataset_Config__c, Section_Config__c
            FROM Billing_Center_Filter_Config__c
            WHERE Tab_Config__c = :tabConfig.id
            AND Dataset_Config__c = :datasetConfig.id
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC, Developer_Key__c ASC
        ]) {
            if (record.Section_Config__c != null) {
                context.warnings.add(
                    'Section-scoped filter '
                    + String.valueOf(record.Developer_Key__c)
                    + ' is not applied in dataset runtime retrieval yet.'
                );
                continue;
            }

            BillingFilterDTO dto = normalizeFilter(record, context);
            if (dto != null) {
                context.filters.add(dto);
            }
        }

        responseWarnings.addAll(context.warnings);
        return context;
    }

    private static BillingFilterDTO normalizeFilter(
        Billing_Center_Filter_Config__c record,
        BillingFilterContextDTO context
    ) {
        String objectApiName = normalizeKey(record.Object_API_Name__c);
        String fieldApiName = normalizeKey(record.Field_API_Name__c);
        String operatorValue = normalizeKey(record.Operator__c);
        String valueType = normalizeKey(record.Value_Type__c);
        String fieldKey = objectApiName + '.' + fieldApiName;

        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' is missing object or field metadata and was skipped.'
            );
            return null;
        }
        if (!SUPPORTED_VALUE_TYPES.contains(valueType)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' uses unsupported value type ' + record.Value_Type__c + '.'
            );
            return null;
        }
        if (!SUPPORTED_OPERATORS.contains(operatorValue)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' uses unsupported operator ' + record.Operator__c + '.'
            );
            return null;
        }
        if (!isSupportedField(context.tabKey, context.datasetKey, fieldKey)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' targets unsupported field ' + record.Object_API_Name__c + '.' + record.Field_API_Name__c + '.'
            );
            return null;
        }
        if (!isSupportedOperatorForField(context.tabKey, context.datasetKey, fieldKey, operatorValue)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' uses unsupported operator ' + record.Operator__c + ' for field ' + record.Object_API_Name__c + '.' + record.Field_API_Name__c + '.'
            );
            return null;
        }
        if (requiresValue(operatorValue) && String.isBlank(record.Value__c)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' requires a value and was skipped.'
            );
            return null;
        }
        if ('DATE LITERAL' == valueType && !isSupportedDateLiteral(record.Value__c)) {
            context.warnings.add(
                'Filter ' + String.valueOf(record.Developer_Key__c) + ' uses unsupported date literal ' + record.Value__c + '.'
            );
            return null;
        }

        BillingFilterDTO dto = new BillingFilterDTO();
        dto.developerKey = record.Developer_Key__c;
        dto.objectApiName = record.Object_API_Name__c;
        dto.fieldApiName = record.Field_API_Name__c;
        dto.operator = record.Operator__c;
        dto.value = record.Value__c;
        dto.valueType = record.Value_Type__c;
        dto.sequence = record.Sequence__c;
        return dto;
    }

    public static void applyOpportunityOwnerFilterToContext(
        BillingFilterContextDTO context,
        String opportunityOwnerId
    ) {
        if (context == null || String.isBlank(opportunityOwnerId)) {
            return;
        }
        if (context.filters == null) {
            context.filters = new List<BillingFilterDTO>();
        }
        BillingFilterDTO dto = new BillingFilterDTO();
        dto.developerKey = 'OPPORTUNITY_OWNER';
        dto.objectApiName = 'Opportunity';
        dto.fieldApiName = 'OwnerId';
        dto.operator = 'Equals';
        dto.valueType = 'Static';
        dto.sequence = 9992;
        dto.value = opportunityOwnerId;
        context.filters.add(dto);
    }

    public static BillingDateFilterDTO defaultThisYearDateFilter(BillingDateFilterDTO dateFilter) {
        if (dateFilter != null
            && (!String.isBlank(dateFilter.filterKey)
                || (!String.isBlank(dateFilter.startDate) && !String.isBlank(dateFilter.endDate)))
        ) {
            return dateFilter;
        }
        BillingDateFilterDTO fallback = new BillingDateFilterDTO();
        fallback.filterKey = 'This Year';
        return fallback;
    }

    public static void applyDateFilterToContext(
        BillingFilterContextDTO context,
        BillingDateFilterDTO dateFilter,
        String objectApiName,
        String fieldApiName,
        Boolean isDateTimeField,
        List<String> responseWarnings
    ) {
        if (context == null || dateFilter == null) {
            return;
        }
        if (String.isBlank(dateFilter.filterKey)
            && (String.isBlank(dateFilter.startDate) || String.isBlank(dateFilter.endDate))
        ) {
            return;
        }

        DateRangeDTO range = resolveDateRange(dateFilter, responseWarnings);
        if (range == null) {
            return;
        }

        context.filters.add(buildDateBoundaryFilter(
            'DATE_FILTER_START',
            objectApiName,
            fieldApiName,
            'Greater Or Equal',
            range.startDate,
            isDateTimeField,
            9990
        ));
        context.filters.add(buildDateBoundaryFilter(
            'DATE_FILTER_END',
            objectApiName,
            fieldApiName,
            'Less Or Equal',
            range.endDate,
            isDateTimeField,
            9991
        ));
    }

    private static BillingFilterDTO buildDateBoundaryFilter(
        String developerKey,
        String objectApiName,
        String fieldApiName,
        String operatorValue,
        Date boundaryDate,
        Boolean isDateTimeField,
        Decimal sequence
    ) {
        BillingFilterDTO dto = new BillingFilterDTO();
        dto.developerKey = developerKey;
        dto.objectApiName = objectApiName;
        dto.fieldApiName = fieldApiName;
        dto.operator = operatorValue;
        dto.valueType = 'Static';
        dto.sequence = sequence;
        dto.value = isDateTimeField
            ? formatDate(boundaryDate) + (operatorValue == 'Less Or Equal' ? ' 23:59:59' : ' 00:00:00')
            : formatDate(boundaryDate);
        return dto;
    }

    public static DateRangeDTO resolveDateRangeForInvSync(BillingDateFilterDTO dateFilter) {
        return resolveDateRange(defaultThisYearDateFilter(dateFilter), new List<String>());
    }

    public static DateRangeDTO resolveDateRange(BillingDateFilterDTO dateFilter, List<String> responseWarnings) {
        Date explicitStart = parseDateValue(dateFilter != null ? dateFilter.startDate : null);
        Date explicitEnd = parseDateValue(dateFilter != null ? dateFilter.endDate : null);
        if (explicitStart != null && explicitEnd != null) {
            if (explicitStart > explicitEnd) {
                responseWarnings.add('Custom date filter start date must be on or before end date.');
                return null;
            }
            return new DateRangeDTO(explicitStart, explicitEnd);
        }

        String normalizedKey = normalizeKey(dateFilter != null ? dateFilter.filterKey : null);
        if (String.isBlank(normalizedKey)) {
            return null;
        }

        Date todayDate = Date.today();
        if (normalizedKey == 'TODAY') {
            return new DateRangeDTO(todayDate, todayDate);
        }
        if (normalizedKey == 'THIS WEEK') {
            Date startOfWeek = todayDate.toStartOfWeek();
            return new DateRangeDTO(startOfWeek, startOfWeek.addDays(6));
        }
        if (normalizedKey == 'THIS MONTH') {
            Date startOfMonth = Date.newInstance(todayDate.year(), todayDate.month(), 1);
            return new DateRangeDTO(startOfMonth, startOfMonth.addMonths(1).addDays(-1));
        }
        if (normalizedKey == 'THIS QUARTER') {
            Integer startMonth = (((todayDate.month() - 1) / 3) * 3) + 1;
            Date startOfQuarter = Date.newInstance(todayDate.year(), startMonth, 1);
            return new DateRangeDTO(startOfQuarter, startOfQuarter.addMonths(3).addDays(-1));
        }
        if (normalizedKey == 'THIS YEAR' || normalizedKey == 'CURRENT YEAR') {
            Date startOfYear = Date.newInstance(todayDate.year(), 1, 1);
            return new DateRangeDTO(startOfYear, Date.newInstance(todayDate.year(), 12, 31));
        }
        if (normalizedKey == 'LAST YEAR' || normalizedKey == 'PRIOR YEAR') {
            Integer priorYear = todayDate.year() - 1;
            return new DateRangeDTO(
                Date.newInstance(priorYear, 1, 1),
                Date.newInstance(priorYear, 12, 31)
            );
        }
        if (normalizedKey == 'CUSTOM') {
            responseWarnings.add('Custom date filter requires both start date and end date.');
            return null;
        }

        responseWarnings.add('Unsupported date filter key: ' + dateFilter.filterKey + '.');
        return null;
    }

    public static Boolean isDatasetConfiguredForHandlers(
        BillingControl_ConfigService.DatasetConfigDTO datasetConfig,
        String datasetDeveloperKey,
        Set<String> supportedHandlerKeys,
        List<String> warnings
    ) {
        if (datasetConfig == null) {
            warnings.add('Dataset ' + datasetDeveloperKey + ' is missing or inactive in Billing Control Center config.');
            return false;
        }

        if (normalizeKey(datasetConfig.dataSourceType) != DATA_SOURCE_TYPE_APEX_HANDLER) {
            warnings.add(
                'Dataset ' + datasetDeveloperKey + ' must use Data Source Type Apex Handler, but found '
                + datasetConfig.dataSourceType
                + '.'
            );
            return false;
        }

        String handlerKey = normalizeKey(datasetConfig.apexHandlerKey);
        if (String.isBlank(handlerKey) || !supportedHandlerKeys.contains(handlerKey)) {
            warnings.add(
                'Dataset '
                + datasetDeveloperKey
                + ' uses unsupported Apex handler key '
                + String.valueOf(datasetConfig.apexHandlerKey)
                + '.'
            );
            return false;
        }

        return true;
    }

    public static List<String> buildQueryFilterClauses(
        BillingFilterContextDTO filterContext,
        Map<String, FilterFieldDescriptor> fieldMappings
    ) {
        List<String> clauses = new List<String>();
        if (filterContext == null || filterContext.filters == null || filterContext.filters.isEmpty() || fieldMappings == null) {
            return clauses;
        }

        for (BillingFilterDTO filterRecord : filterContext.filters) {
            String fieldKey = normalizeKey(filterRecord.objectApiName) + '.' + normalizeKey(filterRecord.fieldApiName);
            FilterFieldDescriptor descriptor = fieldMappings.get(fieldKey);
            if (descriptor == null) {
                continue;
            }

            String clause = buildQueryFilterClause(filterRecord, descriptor);
            if (String.isNotBlank(clause)) {
                clauses.add(clause);
            }
        }

        return clauses;
    }

    private static String buildQueryFilterClause(BillingFilterDTO filterRecord, FilterFieldDescriptor descriptor) {
        if (filterRecord == null || descriptor == null || String.isBlank(descriptor.queryFieldPath)) {
            return null;
        }

        String operatorValue = normalizeKey(filterRecord.operator);
        if (String.isBlank(operatorValue)) {
            return null;
        }

        if (operatorValue == 'IS NULL') {
            return descriptor.queryFieldPath + ' = NULL';
        }
        if (operatorValue == 'IS NOT NULL') {
            return descriptor.queryFieldPath + ' != NULL';
        }

        if (FILTER_DATA_TYPE_STRING == descriptor.dataType || FILTER_DATA_TYPE_ID == descriptor.dataType) {
            return buildStringFilterClause(descriptor.queryFieldPath, operatorValue, filterRecord.value);
        }
        if (FILTER_DATA_TYPE_BOOLEAN == descriptor.dataType) {
            return buildBooleanFilterClause(descriptor.queryFieldPath, operatorValue, filterRecord.value);
        }
        if (FILTER_DATA_TYPE_DATE == descriptor.dataType) {
            return buildDateFilterClause(descriptor.queryFieldPath, operatorValue, filterRecord.value);
        }
        if (FILTER_DATA_TYPE_DATETIME == descriptor.dataType) {
            return buildDateTimeFilterClause(descriptor.queryFieldPath, operatorValue, filterRecord.value);
        }
        if (FILTER_DATA_TYPE_DECIMAL == descriptor.dataType) {
            return buildDecimalFilterClause(descriptor.queryFieldPath, operatorValue, filterRecord.value);
        }

        return null;
    }

    private static String buildStringFilterClause(String fieldPath, String operatorValue, String rawValue) {
        List<String> values = splitFilterValues(rawValue);
        if (values.isEmpty()) {
            return null;
        }
        if (operatorValue == 'EQUALS') {
            return fieldPath + ' = \'' + String.escapeSingleQuotes(values[0]) + '\'';
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldPath + ' != \'' + String.escapeSingleQuotes(values[0]) + '\'';
        }
        if (operatorValue == 'IN') {
            return fieldPath + ' IN (' + joinQuotedValues(values) + ')';
        }
        if (operatorValue == 'NOT IN') {
            return fieldPath + ' NOT IN (' + joinQuotedValues(values) + ')';
        }
        return null;
    }

    private static String buildBooleanFilterClause(String fieldPath, String operatorValue, String rawValue) {
        Boolean parsedValue = parseBooleanValue(rawValue);
        if (parsedValue == null) {
            return null;
        }
        if (operatorValue == 'EQUALS') {
            return fieldPath + ' = ' + String.valueOf(parsedValue).toLowerCase();
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldPath + ' != ' + String.valueOf(parsedValue).toLowerCase();
        }
        return null;
    }

    private static String buildDateFilterClause(String fieldPath, String operatorValue, String rawValue) {
        Date parsedValue = parseDateValue(rawValue);
        if (parsedValue == null) {
            return null;
        }
        String comparisonOperator = getComparisonOperator(operatorValue);
        if (comparisonOperator == null) {
            return null;
        }
        return fieldPath + ' ' + comparisonOperator + ' ' + formatDate(parsedValue);
    }

    private static String buildDateTimeFilterClause(String fieldPath, String operatorValue, String rawValue) {
        Datetime parsedValue = parseDatetimeValue(rawValue);
        if (parsedValue == null) {
            return null;
        }
        String comparisonOperator = getComparisonOperator(operatorValue);
        if (comparisonOperator == null) {
            return null;
        }
        return fieldPath + ' ' + comparisonOperator + ' ' + formatDateTimeLiteral(parsedValue);
    }

    private static String buildDecimalFilterClause(String fieldPath, String operatorValue, String rawValue) {
        List<String> rawValues = splitFilterValues(rawValue);
        List<String> formattedValues = new List<String>();
        for (String entry : rawValues) {
            Decimal parsedValue;
            try {
                parsedValue = Decimal.valueOf(entry);
            } catch (Exception ex) {
                return null;
            }
            formattedValues.add(String.valueOf(parsedValue));
        }

        if (formattedValues.isEmpty()) {
            return null;
        }
        if (operatorValue == 'EQUALS') {
            return fieldPath + ' = ' + formattedValues[0];
        }
        if (operatorValue == 'NOT EQUALS') {
            return fieldPath + ' != ' + formattedValues[0];
        }
        if (operatorValue == 'IN') {
            return fieldPath + ' IN (' + String.join(formattedValues, ', ') + ')';
        }
        if (operatorValue == 'NOT IN') {
            return fieldPath + ' NOT IN (' + String.join(formattedValues, ', ') + ')';
        }
        String comparisonOperator = getComparisonOperator(operatorValue);
        if (comparisonOperator != null) {
            return fieldPath + ' ' + comparisonOperator + ' ' + formattedValues[0];
        }
        return null;
    }

    private static String getComparisonOperator(String operatorValue) {
        if (operatorValue == 'EQUALS') {
            return '=';
        }
        if (operatorValue == 'NOT EQUALS') {
            return '!=';
        }
        if (operatorValue == 'GREATER THAN') {
            return '>';
        }
        if (operatorValue == 'GREATER OR EQUAL') {
            return '>=';
        }
        if (operatorValue == 'LESS THAN') {
            return '<';
        }
        if (operatorValue == 'LESS OR EQUAL') {
            return '<=';
        }
        return null;
    }

    private static List<String> splitFilterValues(String rawValue) {
        List<String> values = new List<String>();
        if (String.isBlank(rawValue)) {
            return values;
        }
        for (String entry : rawValue.split('[;,]')) {
            String trimmedEntry = entry != null ? entry.trim() : null;
            if (String.isNotBlank(trimmedEntry)) {
                values.add(trimmedEntry);
            }
        }
        return values;
    }

    private static String joinQuotedValues(List<String> values) {
        List<String> quotedValues = new List<String>();
        for (String value : values) {
            quotedValues.add('\'' + String.escapeSingleQuotes(value) + '\'');
        }
        return String.join(quotedValues, ', ');
    }

    private static Boolean parseBooleanValue(String rawValue) {
        String normalizedValue = normalizeKey(rawValue);
        if (normalizedValue == 'TRUE' || normalizedValue == 'YES' || normalizedValue == 'Y' || normalizedValue == '1') {
            return true;
        }
        if (normalizedValue == 'FALSE' || normalizedValue == 'NO' || normalizedValue == 'N' || normalizedValue == '0') {
            return false;
        }
        return null;
    }

    private static Datetime parseDatetimeValue(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        try {
            return Datetime.valueOfGmt(rawValue);
        } catch (Exception firstEx) {
            try {
                return Datetime.valueOf(rawValue);
            } catch (Exception secondEx) {
                return null;
            }
        }
    }

    private static String formatDateTimeLiteral(Datetime value) {
        return value == null ? null : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static Boolean isSupportedField(String tabKey, String datasetKey, String fieldKey) {
        String normalizedTabKey = normalizeKey(tabKey);
        String normalizedDatasetKey = normalizeKey(datasetKey);
        String normalizedFieldKey = normalizeKey(fieldKey);

        if (normalizedTabKey == ORDERS_TAB_KEY && normalizedDatasetKey == ORDERS_DATASET_KEY) {
            return new Set<String>{
                'WORK_ORDER_LEDGER__C.LAST_MATERIAL_ACTIVITY__C',
                'WORK_ORDER_LEDGER__C.LAST_SERVICE_DATE__C',
                'WORKORDER.CREATEDDATE',
                'OPPORTUNITY.STAGENAME',
                'OPPORTUNITY.CLOSEDATE'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == INVOICING_TAB_KEY && normalizedDatasetKey == INVOICING_DATASET_KEY) {
            return new Set<String>{
                'SERVICEAPPOINTMENT.ACTUALENDTIME'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == RECEIVABLES_TAB_KEY && normalizedDatasetKey == RECEIVABLES_INVOICES_DATASET_KEY) {
            return new Set<String>{
                'INVOICE__C.INVOICE_DATE__C',
                'OPPORTUNITY.OWNERID'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == RECEIVABLES_TAB_KEY && normalizedDatasetKey == RECEIVABLES_COMMISSIONS_DATASET_KEY) {
            return new Set<String>{
                'OPPORTUNITY.CLOSEDATE',
                'COMMISSION__C.COMMISSION_PAID__C',
                'OPPORTUNITY.OWNERID'
            }.contains(normalizedFieldKey);
        }

        return false;
    }

    private static Boolean isSupportedOperatorForField(
        String tabKey,
        String datasetKey,
        String fieldKey,
        String operatorValue
    ) {
        String normalizedFieldKey = normalizeKey(fieldKey);
        String normalizedOperator = normalizeKey(operatorValue);

        if (
            normalizedFieldKey == 'OPPORTUNITY.CLOSEDATE'
            || normalizedFieldKey == 'SERVICEAPPOINTMENT.ACTUALENDTIME'
            || normalizedFieldKey == 'WORK_ORDER_LEDGER__C.LAST_MATERIAL_ACTIVITY__C'
            || normalizedFieldKey == 'WORK_ORDER_LEDGER__C.LAST_SERVICE_DATE__C'
            || normalizedFieldKey == 'WORKORDER.CREATEDDATE'
            || normalizedFieldKey == 'INVOICE__C.INVOICE_DATE__C'
            || normalizedFieldKey == 'COMMISSION__C.COMMISSION_PAID__C'
        ) {
            return new Set<String>{
                'EQUALS',
                'NOT EQUALS',
                'GREATER THAN',
                'GREATER OR EQUAL',
                'LESS THAN',
                'LESS OR EQUAL',
                'IS NULL',
                'IS NOT NULL'
            }.contains(normalizedOperator);
        }

        return new Set<String>{
            'EQUALS',
            'NOT EQUALS',
            'IN',
            'NOT IN',
            'IS NULL',
            'IS NOT NULL'
        }.contains(normalizedOperator);
    }

    private static Boolean requiresValue(String operatorValue) {
        String normalizedOperator = normalizeKey(operatorValue);
        return normalizedOperator != 'IS NULL' && normalizedOperator != 'IS NOT NULL';
    }

    private static Boolean isSupportedDateLiteral(String value) {
        String normalizedValue = normalizeKey(value);
        if (String.isBlank(normalizedValue)) {
            return false;
        }

        if (new Set<String>{ 'TODAY', 'YESTERDAY', 'TOMORROW', 'THIS WEEK', 'THIS MONTH', 'THIS QUARTER', 'THIS YEAR', 'LAST YEAR', 'PRIOR YEAR' }.contains(normalizedValue)) {
            return true;
        }

        List<String> prefixes = new List<String>{ 'LAST_N_DAYS:', 'NEXT_N_DAYS:', 'LAST_N_YEARS:' };
        for (String prefix : prefixes) {
            if (normalizedValue.startsWith(prefix)) {
                String suffix = normalizedValue.substring(prefix.length());
                try {
                    Integer.valueOf(suffix);
                    return true;
                } catch (Exception ex) {
                    return false;
                }
            }
        }

        return false;
    }

    private static Date parseDateValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String formatDate(Date value) {
        return String.valueOf(value.year()) + '-'
            + String.valueOf(value.month()).leftPad(2, '0') + '-'
            + String.valueOf(value.day()).leftPad(2, '0');
    }

    private static String normalizeKey(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    public class BillingFilterDTO {
        @AuraEnabled public String developerKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String operator;
        @AuraEnabled public String value;
        @AuraEnabled public String valueType;
        @AuraEnabled public Decimal sequence;
    }

    public class BillingFilterContextDTO {
        @AuraEnabled public String tabKey;
        @AuraEnabled public String datasetKey;
        @AuraEnabled public List<BillingFilterDTO> filters = new List<BillingFilterDTO>();
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<String> runtimeWarnings = new List<String>();
    }

    public class FilterFieldDescriptor {
        public String queryFieldPath;
        public String dataType;

        public FilterFieldDescriptor(String queryFieldPathValue, String dataTypeValue) {
            queryFieldPath = queryFieldPathValue;
            dataType = dataTypeValue;
        }
    }

    public class BillingDateFilterDTO {
        @AuraEnabled public String filterKey { get; set; }
        @AuraEnabled public String startDate { get; set; }
        @AuraEnabled public String endDate { get; set; }
    }
    public class DateRangeDTO {
        public Date startDate;
        public Date endDate;

        public DateRangeDTO(Date startDateValue, Date endDateValue) {
            startDate = startDateValue;
            endDate = endDateValue;
        }
    }
}
