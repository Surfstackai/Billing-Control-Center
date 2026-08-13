public with sharing class BillingControl_DataProvider {
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

    private static final Set<String> ORDERS_SUPPORTED_HANDLER_KEYS = new Set<String>{
        'BILLINGCONTROL_ORDERS.GETKPIS',
        'BILLINGCONTROL_ORDERS.GETBUCKETWORKORDERS',
        'BILLINGCONTROL_WORKORDERLEDGER.GETKPIS',
        'BILLINGCONTROL_WORKORDERLEDGER.GETBUCKETWORKORDERS'
    };
    private static final Set<String> INVOICING_SUPPORTED_HANDLER_KEYS = new Set<String>{
        'BILLINGCONTROL_INVOICING.GETSERVICEAPPOINTMENTBILLINGMETRICS',
        'BILLINGCONTROL_INVOICING.GETSERVICEAPPOINTMENTBILLINGMETRICSWITHREFRESH',
        'BILLINGCONTROL_INVOICING.GETBILLABLESERVICEAPPOINTMENTGROUPS',
        'BILLINGCONTROL_INVOICING.GETBILLABLESERVICEAPPOINTMENTGROUPSWITHREFRESH'
    };
    private static final Set<String> RECEIVABLES_SUPPORTED_HANDLER_KEYS = new Set<String>{
        'BILLINGCONTROL_INVOICING.GETCOMMISSIONDATA',
        'BILLINGCONTROL_INVOICING.GETCOMMISSIONMETRICS'
    };

    @AuraEnabled(cacheable=true)
    public static OrdersRuntimeDataDTO getOrdersRuntimeData(Long refreshToken, BillingDateFilterDTO dateFilter) {
        OrdersRuntimeDataDTO result = new OrdersRuntimeDataDTO();
        BillingControl_ConfigService.TabConfigDTO tabConfig = BillingControl_ConfigService.getTabConfig(ORDERS_TAB_KEY);
        BillingControl_ConfigService.DatasetConfigDTO datasetConfig = findDataset(tabConfig, ORDERS_DATASET_KEY);
        result.filterContext = buildFilterContext(tabConfig, datasetConfig, result.warnings);
        applyDateFilterToContext(
            result.filterContext,
            dateFilter,
            'Work_Order_Ledger__c',
            'Last_Service_Date__c',
            false,
            result.warnings
        );

        if (isDatasetConfiguredForHandlers(datasetConfig, ORDERS_DATASET_KEY, ORDERS_SUPPORTED_HANDLER_KEYS, result.warnings)) {
            loadOrdersRuntimeData(refreshToken, result);
            return result;
        }

        result.warnings.add('Work Order Ledger dataset missing or invalid.');
        result.warnings.add('Legacy fallback disabled.');
        initializeEmptyOrdersRuntimeData(result);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(Long refreshToken, BillingDateFilterDTO dateFilter) {
        InvoicingRuntimeDataDTO result = new InvoicingRuntimeDataDTO();
        BillingControl_ConfigService.TabConfigDTO tabConfig = BillingControl_ConfigService.getTabConfig(INVOICING_TAB_KEY);
        BillingControl_ConfigService.DatasetConfigDTO datasetConfig = findDataset(tabConfig, INVOICING_DATASET_KEY);
        result.filterContext = buildFilterContext(tabConfig, datasetConfig, result.warnings);

        if (isDatasetConfiguredForHandlers(datasetConfig, INVOICING_DATASET_KEY, INVOICING_SUPPORTED_HANDLER_KEYS, result.warnings)) {
            loadInvoicingRuntimeData(refreshToken, result);
            return result;
        }

        result.warnings.add('Invoicing dataset missing or invalid.');
        result.warnings.add('Legacy fallback disabled.');
        initializeEmptyInvoicingRuntimeData(result);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData(Long refreshToken, BillingDateFilterDTO dateFilter) {
        ReceivablesRuntimeDataDTO result = new ReceivablesRuntimeDataDTO();
        BillingControl_ConfigService.TabConfigDTO tabConfig = BillingControl_ConfigService.getTabConfig(RECEIVABLES_TAB_KEY);
        BillingControl_ConfigService.DatasetConfigDTO invoicesDataset = findDataset(tabConfig, RECEIVABLES_INVOICES_DATASET_KEY);
        BillingControl_ConfigService.DatasetConfigDTO commissionsDataset = findDataset(
            tabConfig,
            RECEIVABLES_COMMISSIONS_DATASET_KEY
        );
        result.invoicesFilterContext = buildFilterContext(tabConfig, invoicesDataset, result.warnings);
        result.commissionsFilterContext = buildFilterContext(tabConfig, commissionsDataset, result.warnings);
        applyDateFilterToContext(
            result.invoicesFilterContext,
            dateFilter,
            'Order',
            'EffectiveDate',
            false,
            result.warnings
        );
        applyDateFilterToContext(
            result.commissionsFilterContext,
            dateFilter,
            'Order',
            'EffectiveDate',
            false,
            result.warnings
        );

        Boolean invoicesValid = isDatasetConfiguredForHandlers(
            invoicesDataset,
            RECEIVABLES_INVOICES_DATASET_KEY,
            RECEIVABLES_SUPPORTED_HANDLER_KEYS,
            result.warnings
        );
        Boolean commissionsValid = isDatasetConfiguredForHandlers(
            commissionsDataset,
            RECEIVABLES_COMMISSIONS_DATASET_KEY,
            RECEIVABLES_SUPPORTED_HANDLER_KEYS,
            result.warnings
        );

        if (invoicesValid && commissionsValid) {
            loadReceivablesRuntimeData(result);
            return result;
        }

        result.warnings.add('Order diary dataset missing or invalid.');
        result.warnings.add('Legacy fallback disabled.');
        initializeEmptyReceivablesRuntimeData(result);
        return result;
    }

    public static OrdersRuntimeDataDTO getOrdersRuntimeData(Long refreshToken) {
        return getOrdersRuntimeData(refreshToken, null);
    }

    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(Long refreshToken) {
        return getInvoicingRuntimeData(refreshToken, null);
    }

    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData() {
        return getReceivablesRuntimeData(null, null);
    }

    @AuraEnabled
    public static BillingControl_WorkOrderLedger.LedgerDetailWrapper getWorkOrderLedgerDetail(Id ledgerId) {
        return BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerId);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_WorkOrderLedger.ValidationCountsWrapper getWorkOrderLedgerValidationCounts() {
        return BillingControl_WorkOrderLedger.getValidationCounts();
    }

    private static void loadOrdersRuntimeData(Long refreshToken, OrdersRuntimeDataDTO result) {
        try {
            BillingControl_WorkOrderLedger.RuntimeBundle runtime =
                BillingControl_WorkOrderLedger.getRuntime(refreshToken, result.filterContext);
            result.kpis = runtime.kpis;
            result.bucketSections = runtime.sections;
            appendRuntimeWarnings(result.warnings, result.filterContext);
            if (countOrderRows(result.bucketSections) == 0) {
                result.warnings.add('No Work Order Ledger records found.');
            }
        } catch (Exception ex) {
            result.warnings.add('Work Order Ledger dataset missing or invalid.');
            result.warnings.add('Legacy fallback disabled.');
            result.warnings.add('Work Order Ledger filter application failed. ' + ex.getMessage());
            initializeEmptyOrdersRuntimeData(result);
        }
    }

    private static void loadInvoicingRuntimeData(Long refreshToken, InvoicingRuntimeDataDTO result) {
        try {
            result.metrics = BillingControl_Invoicing.getServiceAppointmentBillingMetricsWithRefresh(
                refreshToken,
                result.filterContext
            );
            result.groups = BillingControl_Invoicing.getBillableServiceAppointmentGroupsWithRefresh(
                refreshToken,
                result.filterContext
            );
            appendRuntimeWarnings(result.warnings, result.filterContext);
            if (countInvoicingRows(result.groups) == 0) {
                result.warnings.add('No ready-to-bill Service Appointments found.');
            }
        } catch (Exception ex) {
            result.warnings.add('Invoicing dataset missing or invalid.');
            result.warnings.add('Legacy fallback disabled.');
            result.warnings.add('Invoicing filter application failed. ' + ex.getMessage());
            initializeEmptyInvoicingRuntimeData(result);
        }
    }

    private static void loadReceivablesRuntimeData(ReceivablesRuntimeDataDTO result) {
        try {
            result.metrics = BillingControl_Invoicing.getCommissionMetrics(
                result.invoicesFilterContext,
                result.commissionsFilterContext
            );
            result.sections = BillingControl_Invoicing.getCommissionData(
                'kpi',
                result.invoicesFilterContext,
                result.commissionsFilterContext
            );
            appendRuntimeWarnings(result.warnings, result.invoicesFilterContext);
            appendRuntimeWarnings(result.warnings, result.commissionsFilterContext);
            if (countReceivablesRows(result.sections) == 0) {
                result.warnings.add('No outstanding invoices or commissions found.');
            }
        } catch (Exception ex) {
            result.warnings.add('Order diary dataset missing or invalid.');
            result.warnings.add('Legacy fallback disabled.');
            result.warnings.add('Receivables filter application failed. ' + ex.getMessage());
            initializeEmptyReceivablesRuntimeData(result);
        }
    }

    private static BillingControl_ConfigService.DatasetConfigDTO findDataset(
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

    private static BillingFilterContextDTO buildFilterContext(
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

    private static void applyDateFilterToContext(
        BillingFilterContextDTO context,
        BillingDateFilterDTO dateFilter,
        String objectApiName,
        String fieldApiName,
        Boolean isDateTimeField,
        List<String> responseWarnings
    ) {
        if (context == null || dateFilter == null || String.isBlank(dateFilter.filterKey)) {
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

    private static DateRangeDTO resolveDateRange(BillingDateFilterDTO dateFilter, List<String> responseWarnings) {
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
        if (normalizedKey == 'THIS YEAR') {
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
            Date startDate = parseDateValue(dateFilter.startDate);
            Date endDate = parseDateValue(dateFilter.endDate);
            if (startDate == null || endDate == null) {
                responseWarnings.add('Custom date filter requires both start date and end date.');
                return null;
            }
            if (startDate > endDate) {
                responseWarnings.add('Custom date filter start date must be on or before end date.');
                return null;
            }
            return new DateRangeDTO(startDate, endDate);
        }

        responseWarnings.add('Unsupported date filter key: ' + dateFilter.filterKey + '.');
        return null;
    }

    private static Boolean isDatasetConfiguredForHandlers(
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

    private static void appendRuntimeWarnings(List<String> warnings, BillingFilterContextDTO filterContext) {
        if (warnings == null || filterContext == null || filterContext.runtimeWarnings == null) {
            return;
        }

        for (String warning : filterContext.runtimeWarnings) {
            if (String.isNotBlank(warning) && !warnings.contains(warning)) {
                warnings.add(warning);
            }
        }
    }

    private static Boolean isSupportedField(String tabKey, String datasetKey, String fieldKey) {
        String normalizedTabKey = normalizeKey(tabKey);
        String normalizedDatasetKey = normalizeKey(datasetKey);
        String normalizedFieldKey = normalizeKey(fieldKey);

        if (normalizedTabKey == ORDERS_TAB_KEY && normalizedDatasetKey == ORDERS_DATASET_KEY) {
            return new Set<String>{
                'ORDER.BILLING_DIARY_STATUS__C',
                'ORDER.READY_FOR_BILLING__C',
                'ORDER.EFFECTIVEDATE',
                'ORDER.CREATEDDATE',
                'OPPORTUNITY.STAGENAME',
                'OPPORTUNITY.CLOSEDATE',
                'WORK_ORDER_LEDGER__C.LAST_MATERIAL_ACTIVITY__C',
                'WORK_ORDER_LEDGER__C.LAST_SERVICE_DATE__C',
                'WORKORDER.CREATEDDATE'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == INVOICING_TAB_KEY && normalizedDatasetKey == INVOICING_DATASET_KEY) {
            return new Set<String>{
                'ORDER.BILLING_DIARY_STATUS__C',
                'ORDER.READY_FOR_BILLING__C',
                'ORDER.SERVICE_APPOINTMENT__C',
                'ORDER.INVOICED_AMOUNT__C',
                'SERVICEAPPOINTMENT.ACTUALENDTIME'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == RECEIVABLES_TAB_KEY && normalizedDatasetKey == RECEIVABLES_INVOICES_DATASET_KEY) {
            return new Set<String>{
                'ORDER.BILLING_DIARY_STATUS__C',
                'ORDER.RECEIVED_AMOUNT__C',
                'ORDER.OUTSTANDING_AMOUNT__C',
                'ORDER.EFFECTIVEDATE'
            }.contains(normalizedFieldKey);
        }

        if (normalizedTabKey == RECEIVABLES_TAB_KEY && normalizedDatasetKey == RECEIVABLES_COMMISSIONS_DATASET_KEY) {
            return new Set<String>{
                'ORDER.BILLING_DIARY_STATUS__C',
                'ORDER.RECEIVED_AMOUNT__C',
                'ORDER.OUTSTANDING_AMOUNT__C',
                'ORDER.EFFECTIVEDATE',
                'COMMISSION__C.COMMISSION_PAID__C'
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
            normalizedFieldKey == 'ORDER.EFFECTIVEDATE'
            || normalizedFieldKey == 'ORDER.CREATEDDATE'
            || normalizedFieldKey == 'OPPORTUNITY.CLOSEDATE'
            || normalizedFieldKey == 'SERVICEAPPOINTMENT.ACTUALENDTIME'
            || normalizedFieldKey == 'ORDER.RECEIVED_AMOUNT__C'
            || normalizedFieldKey == 'ORDER.OUTSTANDING_AMOUNT__C'
            || normalizedFieldKey == 'WORK_ORDER_LEDGER__C.LAST_MATERIAL_ACTIVITY__C'
            || normalizedFieldKey == 'WORK_ORDER_LEDGER__C.LAST_SERVICE_DATE__C'
            || normalizedFieldKey == 'WORKORDER.CREATEDDATE'
            || normalizedFieldKey == 'ORDER.INVOICED_AMOUNT__C'
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

    private static void initializeEmptyOrdersRuntimeData(OrdersRuntimeDataDTO result) {
        result.kpis = new BillingControl_Orders.KpiWrapper();
        result.kpis.unscheduledRevenue = 0;
        result.kpis.unscheduledCount = 0;
        result.kpis.scheduledRevenue = 0;
        result.kpis.scheduledCount = 0;
        result.kpis.scheduledTodayRevenue = 0;
        result.kpis.scheduledTodayCount = 0;
        result.kpis.completedThisWeekRevenue = 0;
        result.kpis.completedThisWeekCount = 0;
        result.kpis.completedThisMonthRevenue = 0;
        result.kpis.completedThisMonthCount = 0;
        result.kpis.noOpportunityRevenue = 0;
        result.kpis.noOpportunityCount = 0;
        result.kpis.noServiceAppointmentRevenue = 0;
        result.kpis.noServiceAppointmentCount = 0;
        result.kpis.multipleOpportunitiesRevenue = 0;
        result.kpis.multipleOpportunitiesCount = 0;
        result.kpis.completedTodayRevenue = 0;
        result.kpis.completedTodayCount = 0;
        result.kpis.inProgressRevenue = 0;
        result.kpis.inProgressCount = 0;
        result.bucketSections = new List<BillingControl_Orders.BucketSectionWrapper>{
            new BillingControl_Orders.BucketSectionWrapper('UNSCHEDULED', 'Unscheduled Work', new List<BillingControl_Orders.WorkOrderRowWrapper>()),
            new BillingControl_Orders.BucketSectionWrapper('SCHEDULED', 'Scheduled Work', new List<BillingControl_Orders.WorkOrderRowWrapper>()),
            new BillingControl_Orders.BucketSectionWrapper('SCHEDULED_TODAY', 'Scheduled for Today', new List<BillingControl_Orders.WorkOrderRowWrapper>()),
            new BillingControl_Orders.BucketSectionWrapper('COMPLETED_THIS_WEEK', 'Completed This Week', new List<BillingControl_Orders.WorkOrderRowWrapper>()),
            new BillingControl_Orders.BucketSectionWrapper('COMPLETED_THIS_MONTH', 'Completed This Month', new List<BillingControl_Orders.WorkOrderRowWrapper>()),
            new BillingControl_Orders.BucketSectionWrapper(
                'NO_OPPORTUNITY',
                'Work Orders with No Opportunities',
                new List<BillingControl_Orders.WorkOrderRowWrapper>()
            ),
            new BillingControl_Orders.BucketSectionWrapper(
                'NO_SERVICE_APPOINTMENT',
                'Work Orders with No Service Appointment',
                new List<BillingControl_Orders.WorkOrderRowWrapper>()
            ),
            new BillingControl_Orders.BucketSectionWrapper(
                'MULTIPLE_OPPORTUNITIES',
                'Work Orders with Multiple Opportunities',
                new List<BillingControl_Orders.WorkOrderRowWrapper>()
            )
        };
    }

    private static void initializeEmptyInvoicingRuntimeData(InvoicingRuntimeDataDTO result) {
        result.metrics = new BillingControl_Invoicing.BillingControlMetricsWrapper();
        result.metrics.completedMoreThan2Days = 0;
        result.metrics.readyToBill = 0;
        result.metrics.unbilledRevenue = 0;
        result.metrics.outstandingAr = 0;
        result.groups = new List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper>{
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('AGED_COMPLETED', 'Aged Completed Work (>2 Days)'),
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('READY_TO_BILL', 'Billable Service Appointments'),
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('UNBILLED_REVENUE', 'Uninvoiced Revenue')
        };
    }

    private static void initializeEmptyReceivablesRuntimeData(ReceivablesRuntimeDataDTO result) {
        result.metrics = new BillingControl_Invoicing.CommissionMetricsWrapper();
        result.metrics.unbilledRevenue = 0;
        result.metrics.unbilledRevenueCount = 0;
        result.metrics.revenueUnderCollection = 0;
        result.metrics.revenueUnderCollectionCount = 0;
        result.metrics.commissionEarned = 0;
        result.metrics.commissionEarnedCount = 0;
        result.metrics.commissionPayable = 0;
        result.metrics.commissionPayableCount = 0;
        result.sections = new List<BillingControl_Invoicing.CommissionKpiCategoryWrapper>{
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('REVENUE_UNDER_COLLECTION', 'Accounts Receivable (A/R)'),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('COMMISSION_EARNED', 'Commission Accrued'),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('COMMISSION_PAYABLE', 'Commission Payable')
        };
    }

    private static Integer countOrderRows(List<BillingControl_Orders.BucketSectionWrapper> sections) {
        Integer rowCount = 0;
        if (sections == null) {
            return rowCount;
        }
        for (BillingControl_Orders.BucketSectionWrapper sectionRecord : sections) {
            rowCount += sectionRecord != null && sectionRecord.rows != null ? sectionRecord.rows.size() : 0;
        }
        return rowCount;
    }

    private static Integer countInvoicingRows(List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups) {
        Integer rowCount = 0;
        if (groups == null) {
            return rowCount;
        }
        for (BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper groupRecord : groups) {
            rowCount += groupRecord != null ? groupRecord.serviceAppointmentCount : 0;
        }
        return rowCount;
    }

    private static Integer countReceivablesRows(List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections) {
        Integer rowCount = 0;
        if (sections == null) {
            return rowCount;
        }
        for (BillingControl_Invoicing.CommissionKpiCategoryWrapper sectionRecord : sections) {
            rowCount += sectionRecord != null ? sectionRecord.opportunityCount : 0;
        }
        return rowCount;
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
        @AuraEnabled public String filterKey;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
    }

    public class OrdersRuntimeDataDTO {
        @AuraEnabled public BillingControl_Orders.KpiWrapper kpis;
        @AuraEnabled public List<BillingControl_Orders.BucketSectionWrapper> bucketSections;
        @AuraEnabled public BillingFilterContextDTO filterContext;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    public class InvoicingRuntimeDataDTO {
        @AuraEnabled public BillingControl_Invoicing.BillingControlMetricsWrapper metrics;
        @AuraEnabled public List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups;
        @AuraEnabled public BillingFilterContextDTO filterContext;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    public class ReceivablesRuntimeDataDTO {
        @AuraEnabled public BillingControl_Invoicing.CommissionMetricsWrapper metrics;
        @AuraEnabled public List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections;
        @AuraEnabled public BillingFilterContextDTO invoicesFilterContext;
        @AuraEnabled public BillingFilterContextDTO commissionsFilterContext;
        @AuraEnabled public List<String> warnings = new List<String>();
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