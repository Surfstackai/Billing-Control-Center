public with sharing class BillingControl_DataProvider {
    private static final String INVOICING_TAB_KEY = 'INVOICING';
    private static final String RECEIVABLES_TAB_KEY = 'RECEIVABLES';

    private static final String INVOICING_DATASET_KEY = 'INVOICING_SERVICE_APPOINTMENTS';
    private static final String RECEIVABLES_INVOICES_DATASET_KEY = 'RECEIVABLES_INVOICES';
    private static final String RECEIVABLES_COMMISSIONS_DATASET_KEY = 'RECEIVABLES_COMMISSIONS';

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

    public static BillingControl_WorkOrderLedger.OrdersRuntimeDataDTO getOrdersRuntimeData(
        Long refreshToken,
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        return BillingControl_WorkOrderLedger.getOrdersRuntimeData(refreshToken, dateFilter, opportunityOwnerId);
    }

    public static BillingControl_WorkOrderLedger.OrdersRuntimeDataDTO getOrdersRuntimeData(
        Long refreshToken,
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter
    ) {
        return BillingControl_WorkOrderLedger.getOrdersRuntimeData(refreshToken, dateFilter);
    }

    public static BillingControl_WorkOrderLedger.OrdersRuntimeDataDTO getOrdersRuntimeData(Long refreshToken) {
        return BillingControl_WorkOrderLedger.getOrdersRuntimeData(refreshToken);
    }

    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(
        Long refreshToken,
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        InvoicingRuntimeDataDTO result = new InvoicingRuntimeDataDTO();
        BillingControl_ConfigService.TabConfigDTO tabConfig = BillingControl_ConfigService.getTabConfig(INVOICING_TAB_KEY);
        BillingControl_ConfigService.DatasetConfigDTO datasetConfig = BillingControl_BillingFilters.findDataset(tabConfig, INVOICING_DATASET_KEY);
        result.filterContext = BillingControl_BillingFilters.buildFilterContext(tabConfig, datasetConfig, result.warnings);
        BillingControl_BillingFilters.applyDateFilterToContext(
            result.filterContext,
            BillingControl_BillingFilters.defaultThisYearDateFilter(dateFilter),
            'ServiceAppointment',
            'ActualEndTime',
            true,
            result.warnings
        );
        BillingControl_BillingFilters.applyOpportunityOwnerFilterToContext(result.filterContext, opportunityOwnerId);

        if (BillingControl_BillingFilters.isDatasetConfiguredForHandlers(datasetConfig, INVOICING_DATASET_KEY, INVOICING_SUPPORTED_HANDLER_KEYS, result.warnings)) {
            loadInvoicingRuntimeData(refreshToken, result);
            return result;
        }

        result.warnings.add('Invoicing dataset missing or invalid.');
        result.warnings.add('Legacy fallback disabled.');
        initializeEmptyInvoicingRuntimeData(result);
        return result;
    }

    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData(
        Long refreshToken,
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        ReceivablesRuntimeDataDTO result = new ReceivablesRuntimeDataDTO();
        BillingControl_ConfigService.TabConfigDTO tabConfig = BillingControl_ConfigService.getTabConfig(RECEIVABLES_TAB_KEY);
        BillingControl_ConfigService.DatasetConfigDTO invoicesDataset = BillingControl_BillingFilters.findDataset(tabConfig, RECEIVABLES_INVOICES_DATASET_KEY);
        BillingControl_ConfigService.DatasetConfigDTO commissionsDataset = BillingControl_BillingFilters.findDataset(
            tabConfig,
            RECEIVABLES_COMMISSIONS_DATASET_KEY
        );
        result.invoicesFilterContext = BillingControl_BillingFilters.buildFilterContext(tabConfig, invoicesDataset, result.warnings);
        result.commissionsFilterContext = BillingControl_BillingFilters.buildFilterContext(tabConfig, commissionsDataset, result.warnings);
        BillingControl_BillingFilters.applyDateFilterToContext(
            result.invoicesFilterContext,
            dateFilter,
            'Invoice__c',
            'Invoice_Date__c',
            false,
            result.warnings
        );
        BillingControl_BillingFilters.applyDateFilterToContext(
            result.commissionsFilterContext,
            dateFilter,
            'Opportunity',
            'CloseDate',
            false,
            result.warnings
        );
        BillingControl_BillingFilters.applyOpportunityOwnerFilterToContext(result.invoicesFilterContext, opportunityOwnerId);
        BillingControl_BillingFilters.applyOpportunityOwnerFilterToContext(result.commissionsFilterContext, opportunityOwnerId);

        Boolean invoicesValid = BillingControl_BillingFilters.isDatasetConfiguredForHandlers(
            invoicesDataset,
            RECEIVABLES_INVOICES_DATASET_KEY,
            RECEIVABLES_SUPPORTED_HANDLER_KEYS,
            result.warnings
        );
        Boolean commissionsValid = BillingControl_BillingFilters.isDatasetConfiguredForHandlers(
            commissionsDataset,
            RECEIVABLES_COMMISSIONS_DATASET_KEY,
            RECEIVABLES_SUPPORTED_HANDLER_KEYS,
            result.warnings
        );

        if (invoicesValid && commissionsValid) {
            loadReceivablesRuntimeData(result);
            return result;
        }

        result.warnings.add('Receivables dataset missing or invalid.');
        result.warnings.add('Legacy fallback disabled.');
        initializeEmptyReceivablesRuntimeData(result);
        return result;
    }

    @AuraEnabled
    public static BillingControl_WorkOrderLedger.OrdersRuntimeDataDTO getOrdersRuntimeData(
        Long refreshToken,
        String filterKey,
        String startDate,
        String endDate,
        String opportunityOwnerId
    ) {
        return BillingControl_WorkOrderLedger.getOrdersRuntimeData(
            refreshToken,
            filterKey,
            startDate,
            endDate,
            opportunityOwnerId
        );
    }

    @AuraEnabled
    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(
        Long refreshToken,
        String filterKey,
        String startDate,
        String endDate,
        String opportunityOwnerId
    ) {
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter = new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = filterKey;
        dateFilter.startDate = startDate;
        dateFilter.endDate = endDate;
        return getInvoicingRuntimeData(refreshToken, dateFilter, opportunityOwnerId);
    }

    @AuraEnabled
    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData(
        Long refreshToken,
        String filterKey,
        String startDate,
        String endDate,
        String opportunityOwnerId
    ) {
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter = new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = filterKey;
        dateFilter.startDate = startDate;
        dateFilter.endDate = endDate;
        return getReceivablesRuntimeData(refreshToken, dateFilter, opportunityOwnerId);
    }

    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(Long refreshToken, BillingControl_BillingFilters.BillingDateFilterDTO dateFilter) {
        return getInvoicingRuntimeData(refreshToken, dateFilter, null);
    }

    public static InvoicingRuntimeDataDTO getInvoicingRuntimeData(Long refreshToken) {
        return getInvoicingRuntimeData(refreshToken, null, null);
    }

    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData(Long refreshToken, BillingControl_BillingFilters.BillingDateFilterDTO dateFilter) {
        return getReceivablesRuntimeData(refreshToken, dateFilter, null);
    }

    public static ReceivablesRuntimeDataDTO getReceivablesRuntimeData() {
        return getReceivablesRuntimeData(null, null, null);
    }

    @AuraEnabled
    public static BillingControl_WorkOrderLedger.LedgerDetailWrapper getWorkOrderLedgerDetail(Id ledgerId) {
        return BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerId);
    }

    @AuraEnabled
    public static BillingControl_WorkOrderLedger.LedgerDetailWrapper getWorkOrderLedgerDetailForRange(
        Id ledgerId,
        String filterKey,
        String startDate,
        String endDate
    ) {
        if (String.isBlank(filterKey) && String.isBlank(startDate) && String.isBlank(endDate)) {
            return BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerId, null);
        }
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter = new BillingControl_BillingFilters.BillingDateFilterDTO();
        dateFilter.filterKey = filterKey;
        dateFilter.startDate = startDate;
        dateFilter.endDate = endDate;
        return getWorkOrderLedgerDetailForRange(ledgerId, dateFilter);
    }

    public static BillingControl_WorkOrderLedger.LedgerDetailWrapper getWorkOrderLedgerDetailForRange(
        Id ledgerId,
        BillingControl_BillingFilters.BillingDateFilterDTO dateFilter
    ) {
        BillingControl_BillingFilters.DateRangeDTO dateWindow = dateFilter == null
            ? null
            : BillingControl_BillingFilters.resolveDateRange(dateFilter, new List<String>());
        return BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail(ledgerId, dateWindow);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_WorkOrderLedger.ValidationCountsWrapper getWorkOrderLedgerValidationCounts() {
        return BillingControl_WorkOrderLedger.getValidationCounts();
    }

    private static void loadInvoicingRuntimeData(Long refreshToken, InvoicingRuntimeDataDTO result) {
        try {
            Long ignoredRefreshToken = refreshToken;
            BillingControl_BillingReadiness.Runtime runtime =
                BillingControl_BillingReadiness.load(result.filterContext);
            result.metrics = BillingControl_Invoicing.metricsFromRuntime(runtime);
            result.groups = BillingControl_Invoicing.groupsFromRuntime(runtime);
            appendRuntimeWarnings(result.warnings, result.filterContext);
            if (result.metrics == null || result.metrics.readyToBill == 0) {
                result.warnings.add('No billable Opportunities found.');
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
            result.warnings.add('Receivables dataset missing or invalid.');
            result.warnings.add('Legacy fallback disabled.');
            result.warnings.add('Receivables filter application failed. ' + ex.getMessage());
            initializeEmptyReceivablesRuntimeData(result);
        }
    }

    private static void appendRuntimeWarnings(List<String> warnings, BillingControl_BillingFilters.BillingFilterContextDTO filterContext) {
        if (warnings == null || filterContext == null || filterContext.runtimeWarnings == null) {
            return;
        }

        for (String warning : filterContext.runtimeWarnings) {
            if (String.isNotBlank(warning) && !warnings.contains(warning)) {
                warnings.add(warning);
            }
        }
    }

    private static void initializeEmptyInvoicingRuntimeData(InvoicingRuntimeDataDTO result) {
        result.metrics = new BillingControl_Invoicing.BillingControlMetricsWrapper();
        result.metrics.completedMoreThan2Days = 0;
        result.metrics.readyToBill = 0;
        result.metrics.unbilledRevenue = 0;
        result.metrics.outstandingAr = 0;
        result.metrics.completedTodayCount = 0;
        result.metrics.completedTodayAmount = 0;
        result.metrics.completedThisWeekCount = 0;
        result.metrics.completedThisWeekAmount = 0;
        result.metrics.completedLaterCount = 0;
        result.metrics.completedLaterAmount = 0;
        result.groups = new List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper>{
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('DEPOSITS_DUE', 'Deposit Due'),
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('BALANCES_READY', 'Ready to Bill'),
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('UNDER_INVOICED', 'Balance Remaining'),
            new BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper('NEEDS_REVIEW', 'Needs Review')
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
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('REVENUE_UNDER_COLLECTION', 'Receivables Outstanding'),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('COMMISSION_EARNED', 'Commission Accrued'),
            new BillingControl_Invoicing.CommissionKpiCategoryWrapper('COMMISSION_PAYABLE', 'Commission Payable')
        };
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
    public class InvoicingRuntimeDataDTO {
        @AuraEnabled public BillingControl_Invoicing.BillingControlMetricsWrapper metrics;
        @AuraEnabled public List<BillingControl_Invoicing.ServiceAppointmentKpiCategoryWrapper> groups;
        @AuraEnabled public BillingControl_BillingFilters.BillingFilterContextDTO filterContext;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    public class ReceivablesRuntimeDataDTO {
        @AuraEnabled public BillingControl_Invoicing.CommissionMetricsWrapper metrics;
        @AuraEnabled public List<BillingControl_Invoicing.CommissionKpiCategoryWrapper> sections;
        @AuraEnabled public BillingControl_BillingFilters.BillingFilterContextDTO invoicesFilterContext;
        @AuraEnabled public BillingControl_BillingFilters.BillingFilterContextDTO commissionsFilterContext;
        @AuraEnabled public List<String> warnings = new List<String>();
    }
}
