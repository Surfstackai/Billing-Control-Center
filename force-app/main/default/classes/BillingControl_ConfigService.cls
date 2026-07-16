public with sharing class BillingControl_ConfigService {
    @AuraEnabled(cacheable=true)
    public static List<TabConfigDTO> getConfig() {
        return buildConfig(null);
    }

    @AuraEnabled(cacheable=true)
    public static List<TabConfigDTO> getTabs() {
        return buildConfig(null);
    }

    @AuraEnabled(cacheable=true)
    public static TabConfigDTO getTabConfig(String developerKey) {
        if (String.isBlank(developerKey)) {
            return null;
        }

        List<TabConfigDTO> tabs = buildConfig(new Set<String>{ developerKey.trim() });
        return tabs.isEmpty() ? null : tabs[0];
    }

    private static List<TabConfigDTO> buildConfig(Set<String> developerKeys) {
        List<Billing_Center_Tab_Config__c> tabRecords = loadTabs(developerKeys);
        if (tabRecords.isEmpty()) {
            return new List<TabConfigDTO>();
        }

        List<TabConfigDTO> tabs = new List<TabConfigDTO>();
        Map<Id, TabConfigDTO> tabsById = new Map<Id, TabConfigDTO>();
        Map<Id, Set<String>> datasetKeysByTabId = new Map<Id, Set<String>>();

        for (Billing_Center_Tab_Config__c record : tabRecords) {
            TabConfigDTO dto = toTabDto(record);
            tabs.add(dto);
            tabsById.put(record.Id, dto);
            datasetKeysByTabId.put(record.Id, new Set<String>());
        }

        Set<Id> tabIds = tabsById.keySet();
        List<Billing_Center_Section_Config__c> sectionRecords = loadSections(tabIds);
        Map<Id, SectionConfigDTO> sectionsById = new Map<Id, SectionConfigDTO>();
        for (Billing_Center_Section_Config__c record : sectionRecords) {
            SectionConfigDTO dto = toSectionDto(record);
            sectionsById.put(record.Id, dto);
            tabsById.get(record.Tab_Config__c).sections.add(dto);
            if (String.isNotBlank(dto.datasetDeveloperKey)) {
                datasetKeysByTabId.get(record.Tab_Config__c).add(dto.datasetDeveloperKey);
            }
        }

        List<Billing_Center_KPI_Config__c> kpiRecords = loadKpis(tabIds);
        List<ColumnConfigDTO> columnDtos = new List<ColumnConfigDTO>();
        List<FilterConfigDTO> filterDtos = new List<FilterConfigDTO>();
        List<KpiConfigDTO> kpiDtos = new List<KpiConfigDTO>();
        Set<Id> datasetIds = new Set<Id>();

        for (Billing_Center_KPI_Config__c record : kpiRecords) {
            KpiConfigDTO dto = toKpiDto(record);
            kpiDtos.add(dto);
            if (dto.datasetConfigId != null) {
                datasetIds.add(dto.datasetConfigId);
            }
            if (record.Section_Config__c != null && sectionsById.containsKey(record.Section_Config__c)) {
                sectionsById.get(record.Section_Config__c).kpis.add(dto);
            } else {
                tabsById.get(record.Tab_Config__c).kpis.add(dto);
            }
        }

        List<Billing_Center_Column_Config__c> columnRecords = loadColumns(tabIds);
        for (Billing_Center_Column_Config__c record : columnRecords) {
            ColumnConfigDTO dto = toColumnDto(record);
            columnDtos.add(dto);
            if (dto.datasetConfigId != null) {
                datasetIds.add(dto.datasetConfigId);
            }
            if (record.Section_Config__c != null && sectionsById.containsKey(record.Section_Config__c)) {
                sectionsById.get(record.Section_Config__c).columns.add(dto);
            } else {
                tabsById.get(record.Tab_Config__c).columns.add(dto);
            }
        }

        List<Billing_Center_Filter_Config__c> filterRecords = loadFilters(tabIds);
        for (Billing_Center_Filter_Config__c record : filterRecords) {
            FilterConfigDTO dto = toFilterDto(record);
            filterDtos.add(dto);
            if (dto.datasetConfigId != null) {
                datasetIds.add(dto.datasetConfigId);
            }
            if (record.Section_Config__c != null && sectionsById.containsKey(record.Section_Config__c)) {
                sectionsById.get(record.Section_Config__c).filters.add(dto);
            } else {
                tabsById.get(record.Tab_Config__c).filters.add(dto);
            }
        }

        List<Billing_Center_Action_Config__c> actionRecords = loadActions(tabIds);
        for (Billing_Center_Action_Config__c record : actionRecords) {
            ActionConfigDTO dto = toActionDto(record);
            if (record.Section_Config__c != null && sectionsById.containsKey(record.Section_Config__c)) {
                sectionsById.get(record.Section_Config__c).actions.add(dto);
            } else {
                tabsById.get(record.Tab_Config__c).actions.add(dto);
            }
        }

        Set<String> sectionDatasetKeys = new Set<String>();
        for (Billing_Center_Section_Config__c record : sectionRecords) {
            if (String.isNotBlank(record.Dataset_Key__c)) {
                sectionDatasetKeys.add(record.Dataset_Key__c);
            }
        }

        List<Billing_Center_Dataset_Config__c> datasetRecords = loadDatasets(datasetIds, sectionDatasetKeys);
        Map<Id, DatasetConfigDTO> datasetsById = new Map<Id, DatasetConfigDTO>();
        Map<String, DatasetConfigDTO> datasetsByDeveloperKey = new Map<String, DatasetConfigDTO>();

        for (Billing_Center_Dataset_Config__c record : datasetRecords) {
            DatasetConfigDTO dto = toDatasetDto(record);
            datasetsById.put(record.Id, dto);
            datasetsByDeveloperKey.put(record.Developer_Key__c, dto);
        }

        for (SectionConfigDTO dto : sectionsById.values()) {
            if (String.isNotBlank(dto.datasetDeveloperKey) && datasetsByDeveloperKey.containsKey(dto.datasetDeveloperKey)) {
                dto.dataset = datasetsByDeveloperKey.get(dto.datasetDeveloperKey);
            }
        }

        for (KpiConfigDTO dto : kpiDtos) {
            attachDataset(dto, datasetsById);
        }
        for (ColumnConfigDTO dto : columnDtos) {
            attachDataset(dto, datasetsById);
        }
        for (FilterConfigDTO dto : filterDtos) {
            attachDataset(dto, datasetsById);
        }

        for (Id tabId : tabsById.keySet()) {
            Set<String> usedKeys = datasetKeysByTabId.get(tabId);
            TabConfigDTO tabDto = tabsById.get(tabId);

            for (SectionConfigDTO sectionDto : tabDto.sections) {
                if (sectionDto.dataset != null) {
                    usedKeys.add(sectionDto.dataset.developerKey);
                }
                for (KpiConfigDTO kpiDto : sectionDto.kpis) {
                    if (kpiDto.dataset != null) {
                        usedKeys.add(kpiDto.dataset.developerKey);
                    }
                }
                for (ColumnConfigDTO columnDto : sectionDto.columns) {
                    if (columnDto.dataset != null) {
                        usedKeys.add(columnDto.dataset.developerKey);
                    }
                }
                for (FilterConfigDTO filterDto : sectionDto.filters) {
                    if (filterDto.dataset != null) {
                        usedKeys.add(filterDto.dataset.developerKey);
                    }
                }
            }

            for (KpiConfigDTO kpiDto : tabDto.kpis) {
                if (kpiDto.dataset != null) {
                    usedKeys.add(kpiDto.dataset.developerKey);
                }
            }
            for (ColumnConfigDTO columnDto : tabDto.columns) {
                if (columnDto.dataset != null) {
                    usedKeys.add(columnDto.dataset.developerKey);
                }
            }
            for (FilterConfigDTO filterDto : tabDto.filters) {
                if (filterDto.dataset != null) {
                    usedKeys.add(filterDto.dataset.developerKey);
                }
            }

            for (Billing_Center_Dataset_Config__c record : datasetRecords) {
                if (usedKeys.contains(record.Developer_Key__c)) {
                    tabDto.datasets.add(datasetsByDeveloperKey.get(record.Developer_Key__c));
                }
            }
        }

        return tabs;
    }

    private static void attachDataset(ConfigChildWithDataset dto, Map<Id, DatasetConfigDTO> datasetsById) {
        if (dto.datasetConfigId == null || !datasetsById.containsKey(dto.datasetConfigId)) {
            return;
        }

        dto.dataset = datasetsById.get(dto.datasetConfigId);
        dto.datasetDeveloperKey = dto.dataset.developerKey;
    }

    private static List<Billing_Center_Tab_Config__c> loadTabs(Set<String> developerKeys) {
        if (!Billing_Center_Tab_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Tab_Config__c>();
        }

        if (developerKeys == null || developerKeys.isEmpty()) {
            return [
                SELECT Id, Developer_Key__c, Label__c, Description__c, Is_Active__c, Display_Order__c,
                    Icon_Name__c, View_Type__c, Default_Date_Filter__c, Theme_Key__c, Apex_Handler_Key__c, Notes__c,
                    Navigation_Group__c, Navigation_Target_Type__c, Target_Object_API_Name__c,
                    Target_App_Developer_Name__c, Target_URL__c, Show_In_Navigation__c,
                    Required_Custom_Permission__c
                FROM Billing_Center_Tab_Config__c
                WHERE Is_Active__c = true
                ORDER BY Display_Order__c ASC, Label__c ASC
            ];
        }

        return [
            SELECT Id, Developer_Key__c, Label__c, Description__c, Is_Active__c, Display_Order__c,
                Icon_Name__c, View_Type__c, Default_Date_Filter__c, Theme_Key__c, Apex_Handler_Key__c, Notes__c,
                Navigation_Group__c, Navigation_Target_Type__c, Target_Object_API_Name__c,
                Target_App_Developer_Name__c, Target_URL__c, Show_In_Navigation__c,
                Required_Custom_Permission__c
            FROM Billing_Center_Tab_Config__c
            WHERE Is_Active__c = true
            AND Developer_Key__c IN :developerKeys
            ORDER BY Display_Order__c ASC, Label__c ASC
        ];
    }

    private static List<Billing_Center_Section_Config__c> loadSections(Set<Id> tabIds) {
        if (tabIds.isEmpty() || !Billing_Center_Section_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Section_Config__c>();
        }

        return [
            SELECT Id, Tab_Config__c, Developer_Key__c, Label__c, Description__c, Is_Active__c, Display_Order__c,
                Section_Type__c, Dataset_Key__c, Empty_State_Message__c, Notes__c
            FROM Billing_Center_Section_Config__c
            WHERE Tab_Config__c IN :tabIds
            AND Is_Active__c = true
            ORDER BY Display_Order__c ASC, Label__c ASC
        ];
    }

    private static List<Billing_Center_Dataset_Config__c> loadDatasets(Set<Id> datasetIds, Set<String> datasetKeys) {
        if (!Billing_Center_Dataset_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Dataset_Config__c>();
        }

        if ((datasetIds == null || datasetIds.isEmpty()) && (datasetKeys == null || datasetKeys.isEmpty())) {
            return new List<Billing_Center_Dataset_Config__c>();
        }

        if (datasetIds == null || datasetIds.isEmpty()) {
            return [
                SELECT Id, Developer_Key__c, Label__c, Description__c, Is_Active__c, Source_Object_API_Name__c,
                    Data_Source_Type__c, Apex_Handler_Key__c, Default_Sort_Field__c, Default_Sort_Direction__c,
                    Max_Row_Limit__c, Notes__c
                FROM Billing_Center_Dataset_Config__c
                WHERE Is_Active__c = true
                AND Developer_Key__c IN :datasetKeys
                ORDER BY Label__c ASC
            ];
        }

        if (datasetKeys == null || datasetKeys.isEmpty()) {
            return [
                SELECT Id, Developer_Key__c, Label__c, Description__c, Is_Active__c, Source_Object_API_Name__c,
                    Data_Source_Type__c, Apex_Handler_Key__c, Default_Sort_Field__c, Default_Sort_Direction__c,
                    Max_Row_Limit__c, Notes__c
                FROM Billing_Center_Dataset_Config__c
                WHERE Is_Active__c = true
                AND Id IN :datasetIds
                ORDER BY Label__c ASC
            ];
        }

        return [
            SELECT Id, Developer_Key__c, Label__c, Description__c, Is_Active__c, Source_Object_API_Name__c,
                Data_Source_Type__c, Apex_Handler_Key__c, Default_Sort_Field__c, Default_Sort_Direction__c,
                Max_Row_Limit__c, Notes__c
            FROM Billing_Center_Dataset_Config__c
            WHERE Is_Active__c = true
            AND (Id IN :datasetIds OR Developer_Key__c IN :datasetKeys)
            ORDER BY Label__c ASC
        ];
    }

    private static List<Billing_Center_KPI_Config__c> loadKpis(Set<Id> tabIds) {
        if (tabIds.isEmpty() || !Billing_Center_KPI_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_KPI_Config__c>();
        }

        return [
            SELECT Id, Tab_Config__c, Section_Config__c, Dataset_Config__c, Developer_Key__c, Label__c,
                Description__c, Is_Active__c, Display_Order__c, Metric_Type__c, Field_API_Name__c,
                Format_Type__c, Comparison_Enabled__c, Comparison_Period_Type__c, Icon_Name__c,
                Color_Key__c, Apex_Handler_Key__c, Notes__c
            FROM Billing_Center_KPI_Config__c
            WHERE Tab_Config__c IN :tabIds
            AND Is_Active__c = true
            ORDER BY Display_Order__c ASC, Label__c ASC
        ];
    }

    private static List<Billing_Center_Column_Config__c> loadColumns(Set<Id> tabIds) {
        if (tabIds.isEmpty() || !Billing_Center_Column_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Column_Config__c>();
        }

        return [
            SELECT Id, Tab_Config__c, Section_Config__c, Dataset_Config__c, Developer_Key__c, Label__c,
                Is_Active__c, Display_Order__c, Field_API_Name__c, Data_Type__c, Is_Link__c,
                Link_Target_Field__c, Is_Sortable__c, Is_Searchable__c, Width__c, Alignment__c, Notes__c
            FROM Billing_Center_Column_Config__c
            WHERE Tab_Config__c IN :tabIds
            AND Is_Active__c = true
            ORDER BY Display_Order__c ASC, Label__c ASC
        ];
    }

    private static List<Billing_Center_Filter_Config__c> loadFilters(Set<Id> tabIds) {
        if (tabIds.isEmpty() || !Billing_Center_Filter_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Filter_Config__c>();
        }

        return [
            SELECT Id, Tab_Config__c, Section_Config__c, Dataset_Config__c, Developer_Key__c, Label__c,
                Is_Active__c, Sequence__c, Object_API_Name__c, Field_API_Name__c, Operator__c, Value__c,
                Value_Type__c, Filter_Logic_Group__c, Notes__c
            FROM Billing_Center_Filter_Config__c
            WHERE Tab_Config__c IN :tabIds
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC, Label__c ASC
        ];
    }

    private static List<Billing_Center_Action_Config__c> loadActions(Set<Id> tabIds) {
        if (tabIds.isEmpty() || !Billing_Center_Action_Config__c.SObjectType.getDescribe().isAccessible()) {
            return new List<Billing_Center_Action_Config__c>();
        }

        return [
            SELECT Id, Tab_Config__c, Section_Config__c, Developer_Key__c, Label__c, Is_Active__c,
                Display_Order__c, Action_Type__c, Handler_Key__c, Requires_Selection__c, Min_Selected_Rows__c,
                Max_Selected_Rows__c, Confirmation_Required__c, Confirmation_Message__c, Button_Variant__c,
                Icon_Name__c, Notes__c
            FROM Billing_Center_Action_Config__c
            WHERE Tab_Config__c IN :tabIds
            AND Is_Active__c = true
            ORDER BY Display_Order__c ASC, Label__c ASC
        ];
    }

    private static TabConfigDTO toTabDto(Billing_Center_Tab_Config__c record) {
        TabConfigDTO dto = new TabConfigDTO();
        dto.id = record.Id;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.description = record.Description__c;
        dto.isActive = record.Is_Active__c;
        dto.displayOrder = record.Display_Order__c;
        dto.iconName = record.Icon_Name__c;
        dto.viewType = record.View_Type__c;
        dto.defaultDateFilter = record.Default_Date_Filter__c;
        dto.themeKey = record.Theme_Key__c;
        dto.apexHandlerKey = record.Apex_Handler_Key__c;
        dto.navigationGroup = record.Navigation_Group__c;
        dto.navigationTargetType = record.Navigation_Target_Type__c;
        dto.targetObjectApiName = record.Target_Object_API_Name__c;
        dto.targetAppDeveloperName = record.Target_App_Developer_Name__c;
        dto.targetUrl = record.Target_URL__c;
        dto.showInNavigation = record.Show_In_Navigation__c;
        dto.requiredCustomPermission = record.Required_Custom_Permission__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static SectionConfigDTO toSectionDto(Billing_Center_Section_Config__c record) {
        SectionConfigDTO dto = new SectionConfigDTO();
        dto.id = record.Id;
        dto.tabConfigId = record.Tab_Config__c;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.description = record.Description__c;
        dto.isActive = record.Is_Active__c;
        dto.displayOrder = record.Display_Order__c;
        dto.sectionType = record.Section_Type__c;
        dto.datasetDeveloperKey = record.Dataset_Key__c;
        dto.emptyStateMessage = record.Empty_State_Message__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static DatasetConfigDTO toDatasetDto(Billing_Center_Dataset_Config__c record) {
        DatasetConfigDTO dto = new DatasetConfigDTO();
        dto.id = record.Id;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.description = record.Description__c;
        dto.isActive = record.Is_Active__c;
        dto.sourceObjectApiName = record.Source_Object_API_Name__c;
        dto.dataSourceType = record.Data_Source_Type__c;
        dto.apexHandlerKey = record.Apex_Handler_Key__c;
        dto.defaultSortField = record.Default_Sort_Field__c;
        dto.defaultSortDirection = record.Default_Sort_Direction__c;
        dto.maxRowLimit = record.Max_Row_Limit__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static KpiConfigDTO toKpiDto(Billing_Center_KPI_Config__c record) {
        KpiConfigDTO dto = new KpiConfigDTO();
        dto.id = record.Id;
        dto.tabConfigId = record.Tab_Config__c;
        dto.sectionConfigId = record.Section_Config__c;
        dto.datasetConfigId = record.Dataset_Config__c;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.description = record.Description__c;
        dto.isActive = record.Is_Active__c;
        dto.displayOrder = record.Display_Order__c;
        dto.metricType = record.Metric_Type__c;
        dto.fieldApiName = record.Field_API_Name__c;
        dto.formatType = record.Format_Type__c;
        dto.comparisonEnabled = record.Comparison_Enabled__c;
        dto.comparisonPeriodType = record.Comparison_Period_Type__c;
        dto.iconName = record.Icon_Name__c;
        dto.colorKey = record.Color_Key__c;
        dto.apexHandlerKey = record.Apex_Handler_Key__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static ColumnConfigDTO toColumnDto(Billing_Center_Column_Config__c record) {
        ColumnConfigDTO dto = new ColumnConfigDTO();
        dto.id = record.Id;
        dto.tabConfigId = record.Tab_Config__c;
        dto.sectionConfigId = record.Section_Config__c;
        dto.datasetConfigId = record.Dataset_Config__c;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.isActive = record.Is_Active__c;
        dto.displayOrder = record.Display_Order__c;
        dto.fieldApiName = record.Field_API_Name__c;
        dto.dataType = record.Data_Type__c;
        dto.isLink = record.Is_Link__c;
        dto.linkTargetField = record.Link_Target_Field__c;
        dto.isSortable = record.Is_Sortable__c;
        dto.isSearchable = record.Is_Searchable__c;
        dto.width = record.Width__c;
        dto.alignment = record.Alignment__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static FilterConfigDTO toFilterDto(Billing_Center_Filter_Config__c record) {
        FilterConfigDTO dto = new FilterConfigDTO();
        dto.id = record.Id;
        dto.tabConfigId = record.Tab_Config__c;
        dto.sectionConfigId = record.Section_Config__c;
        dto.datasetConfigId = record.Dataset_Config__c;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.isActive = record.Is_Active__c;
        dto.sequence = record.Sequence__c;
        dto.objectApiName = record.Object_API_Name__c;
        dto.fieldApiName = record.Field_API_Name__c;
        dto.operatorValue = record.Operator__c;
        dto.value = record.Value__c;
        dto.valueType = record.Value_Type__c;
        dto.filterLogicGroup = record.Filter_Logic_Group__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    private static ActionConfigDTO toActionDto(Billing_Center_Action_Config__c record) {
        ActionConfigDTO dto = new ActionConfigDTO();
        dto.id = record.Id;
        dto.tabConfigId = record.Tab_Config__c;
        dto.sectionConfigId = record.Section_Config__c;
        dto.developerKey = record.Developer_Key__c;
        dto.label = record.Label__c;
        dto.isActive = record.Is_Active__c;
        dto.displayOrder = record.Display_Order__c;
        dto.actionType = record.Action_Type__c;
        dto.handlerKey = record.Handler_Key__c;
        dto.requiresSelection = record.Requires_Selection__c;
        dto.minSelectedRows = record.Min_Selected_Rows__c;
        dto.maxSelectedRows = record.Max_Selected_Rows__c;
        dto.confirmationRequired = record.Confirmation_Required__c;
        dto.confirmationMessage = record.Confirmation_Message__c;
        dto.buttonVariant = record.Button_Variant__c;
        dto.iconName = record.Icon_Name__c;
        dto.notes = record.Notes__c;
        return dto;
    }

    public virtual class ConfigChildWithDataset {
        @AuraEnabled public Id datasetConfigId;
        @AuraEnabled public String datasetDeveloperKey;
        @AuraEnabled public DatasetConfigDTO dataset;
    }

    public class TabConfigDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String iconName;
        @AuraEnabled public String viewType;
        @AuraEnabled public String defaultDateFilter;
        @AuraEnabled public String themeKey;
        @AuraEnabled public String apexHandlerKey;
        @AuraEnabled public String navigationGroup;
        @AuraEnabled public String navigationTargetType;
        @AuraEnabled public String targetObjectApiName;
        @AuraEnabled public String targetAppDeveloperName;
        @AuraEnabled public String targetUrl;
        @AuraEnabled public Boolean showInNavigation;
        @AuraEnabled public String requiredCustomPermission;
        @AuraEnabled public String notes;
        @AuraEnabled public List<SectionConfigDTO> sections = new List<SectionConfigDTO>();
        @AuraEnabled public List<KpiConfigDTO> kpis = new List<KpiConfigDTO>();
        @AuraEnabled public List<ColumnConfigDTO> columns = new List<ColumnConfigDTO>();
        @AuraEnabled public List<FilterConfigDTO> filters = new List<FilterConfigDTO>();
        @AuraEnabled public List<ActionConfigDTO> actions = new List<ActionConfigDTO>();
        @AuraEnabled public List<DatasetConfigDTO> datasets = new List<DatasetConfigDTO>();
    }

    public class SectionConfigDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id tabConfigId;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String sectionType;
        @AuraEnabled public String datasetDeveloperKey;
        @AuraEnabled public DatasetConfigDTO dataset;
        @AuraEnabled public String emptyStateMessage;
        @AuraEnabled public String notes;
        @AuraEnabled public List<KpiConfigDTO> kpis = new List<KpiConfigDTO>();
        @AuraEnabled public List<ColumnConfigDTO> columns = new List<ColumnConfigDTO>();
        @AuraEnabled public List<FilterConfigDTO> filters = new List<FilterConfigDTO>();
        @AuraEnabled public List<ActionConfigDTO> actions = new List<ActionConfigDTO>();
    }

    public class DatasetConfigDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String sourceObjectApiName;
        @AuraEnabled public String dataSourceType;
        @AuraEnabled public String apexHandlerKey;
        @AuraEnabled public String defaultSortField;
        @AuraEnabled public String defaultSortDirection;
        @AuraEnabled public Decimal maxRowLimit;
        @AuraEnabled public String notes;
    }

    public class KpiConfigDTO extends ConfigChildWithDataset {
        @AuraEnabled public Id id;
        @AuraEnabled public Id tabConfigId;
        @AuraEnabled public Id sectionConfigId;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String metricType;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String formatType;
        @AuraEnabled public Boolean comparisonEnabled;
        @AuraEnabled public String comparisonPeriodType;
        @AuraEnabled public String iconName;
        @AuraEnabled public String colorKey;
        @AuraEnabled public String apexHandlerKey;
        @AuraEnabled public String notes;
    }

    public class ColumnConfigDTO extends ConfigChildWithDataset {
        @AuraEnabled public Id id;
        @AuraEnabled public Id tabConfigId;
        @AuraEnabled public Id sectionConfigId;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isLink;
        @AuraEnabled public String linkTargetField;
        @AuraEnabled public Boolean isSortable;
        @AuraEnabled public Boolean isSearchable;
        @AuraEnabled public String width;
        @AuraEnabled public String alignment;
        @AuraEnabled public String notes;
    }

    public class FilterConfigDTO extends ConfigChildWithDataset {
        @AuraEnabled public Id id;
        @AuraEnabled public Id tabConfigId;
        @AuraEnabled public Id sectionConfigId;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String operatorValue;
        @AuraEnabled public String value;
        @AuraEnabled public String valueType;
        @AuraEnabled public String filterLogicGroup;
        @AuraEnabled public String notes;
    }

    public class ActionConfigDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id tabConfigId;
        @AuraEnabled public Id sectionConfigId;
        @AuraEnabled public String developerKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public String actionType;
        @AuraEnabled public String handlerKey;
        @AuraEnabled public Boolean requiresSelection;
        @AuraEnabled public Decimal minSelectedRows;
        @AuraEnabled public Decimal maxSelectedRows;
        @AuraEnabled public Boolean confirmationRequired;
        @AuraEnabled public String confirmationMessage;
        @AuraEnabled public String buttonVariant;
        @AuraEnabled public String iconName;
        @AuraEnabled public String notes;
    }
}