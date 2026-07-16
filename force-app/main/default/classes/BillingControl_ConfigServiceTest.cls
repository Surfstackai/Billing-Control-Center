@IsTest
private class BillingControl_ConfigServiceTest {
    @TestSetup
    static void createConfigData() {
        Billing_Center_Tab_Config__c alphaTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'ALPHA',
            Label__c = 'Alpha Tab',
            Is_Active__c = true,
            Display_Order__c = 20,
            View_Type__c = 'Table',
            Default_Date_Filter__c = 'This Month',
            Navigation_Group__c = 'Billing',
            Navigation_Target_Type__c = 'Internal BCC Tab',
            Show_In_Navigation__c = true
        );
        Billing_Center_Tab_Config__c betaTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'BETA',
            Label__c = 'Beta Tab',
            Is_Active__c = true,
            Display_Order__c = 10,
            View_Type__c = 'Dashboard',
            Default_Date_Filter__c = 'This Year',
            Navigation_Group__c = 'Standard',
            Navigation_Target_Type__c = 'Object Home',
            Target_Object_API_Name__c = 'Opportunity',
            Show_In_Navigation__c = true
        );
        Billing_Center_Tab_Config__c inactiveTab = new Billing_Center_Tab_Config__c(
            Developer_Key__c = 'INACTIVE',
            Label__c = 'Inactive Tab',
            Is_Active__c = false,
            Display_Order__c = 30,
            View_Type__c = 'Custom',
            Default_Date_Filter__c = 'Today',
            Navigation_Group__c = 'Admin',
            Navigation_Target_Type__c = 'App',
            Target_App_Developer_Name__c = 'Billing_Control_Center_Config',
            Show_In_Navigation__c = true,
            Required_Custom_Permission__c = 'Billing_Control_Center_Admin_Access'
        );
        insert new List<Billing_Center_Tab_Config__c>{ alphaTab, betaTab, inactiveTab };

        Billing_Center_Dataset_Config__c datasetAlpha = new Billing_Center_Dataset_Config__c(
            Developer_Key__c = 'DATASET_ALPHA',
            Label__c = 'Dataset Alpha',
            Is_Active__c = true,
            Data_Source_Type__c = 'Apex Handler',
            Apex_Handler_Key__c = 'Test.alpha'
        );
        Billing_Center_Dataset_Config__c datasetBeta = new Billing_Center_Dataset_Config__c(
            Developer_Key__c = 'DATASET_BETA',
            Label__c = 'Dataset Beta',
            Is_Active__c = true,
            Data_Source_Type__c = 'Static'
        );
        insert new List<Billing_Center_Dataset_Config__c>{ datasetAlpha, datasetBeta };

        Billing_Center_Section_Config__c alphaSectionB = new Billing_Center_Section_Config__c(
            Tab_Config__c = alphaTab.Id,
            Developer_Key__c = 'SECTION_B',
            Label__c = 'Section B',
            Is_Active__c = true,
            Display_Order__c = 20,
            Section_Type__c = 'Table',
            Dataset_Key__c = 'DATASET_ALPHA'
        );
        Billing_Center_Section_Config__c alphaSectionA = new Billing_Center_Section_Config__c(
            Tab_Config__c = alphaTab.Id,
            Developer_Key__c = 'SECTION_A',
            Label__c = 'Section A',
            Is_Active__c = true,
            Display_Order__c = 10,
            Section_Type__c = 'Accordion',
            Dataset_Key__c = 'DATASET_ALPHA'
        );
        Billing_Center_Section_Config__c betaSection = new Billing_Center_Section_Config__c(
            Tab_Config__c = betaTab.Id,
            Developer_Key__c = 'SECTION_C',
            Label__c = 'Section C',
            Is_Active__c = true,
            Display_Order__c = 10,
            Section_Type__c = 'Table',
            Dataset_Key__c = 'DATASET_BETA'
        );
        Billing_Center_Section_Config__c inactiveSection = new Billing_Center_Section_Config__c(
            Tab_Config__c = alphaTab.Id,
            Developer_Key__c = 'SECTION_INACTIVE',
            Label__c = 'Inactive Section',
            Is_Active__c = false,
            Display_Order__c = 30,
            Section_Type__c = 'Custom'
        );
        insert new List<Billing_Center_Section_Config__c>{ alphaSectionB, alphaSectionA, betaSection, inactiveSection };

        insert new List<Billing_Center_KPI_Config__c>{
            new Billing_Center_KPI_Config__c(
                Tab_Config__c = alphaTab.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'TAB_KPI',
                Label__c = 'Tab KPI',
                Is_Active__c = true,
                Display_Order__c = 20,
                Metric_Type__c = 'Apex Handler',
                Format_Type__c = 'Number',
                Apex_Handler_Key__c = 'Test.tabKpi'
            ),
            new Billing_Center_KPI_Config__c(
                Tab_Config__c = alphaTab.Id,
                Section_Config__c = alphaSectionA.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'SECTION_KPI',
                Label__c = 'Section KPI',
                Is_Active__c = true,
                Display_Order__c = 10,
                Metric_Type__c = 'Apex Handler',
                Format_Type__c = 'Currency',
                Apex_Handler_Key__c = 'Test.sectionKpi'
            ),
            new Billing_Center_KPI_Config__c(
                Tab_Config__c = alphaTab.Id,
                Developer_Key__c = 'INACTIVE_KPI',
                Label__c = 'Inactive KPI',
                Is_Active__c = false,
                Display_Order__c = 30,
                Metric_Type__c = 'Apex Handler',
                Format_Type__c = 'Number'
            )
        };

        insert new List<Billing_Center_Column_Config__c>{
            new Billing_Center_Column_Config__c(
                Tab_Config__c = alphaTab.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'TAB_COLUMN',
                Label__c = 'Tab Column',
                Is_Active__c = true,
                Display_Order__c = 20,
                Field_API_Name__c = 'fieldOne',
                Data_Type__c = 'Text'
            ),
            new Billing_Center_Column_Config__c(
                Tab_Config__c = alphaTab.Id,
                Section_Config__c = alphaSectionA.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'SECTION_COLUMN',
                Label__c = 'Section Column',
                Is_Active__c = true,
                Display_Order__c = 10,
                Field_API_Name__c = 'fieldTwo',
                Data_Type__c = 'Number'
            )
        };

        insert new List<Billing_Center_Filter_Config__c>{
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = alphaTab.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'TAB_FILTER',
                Label__c = 'Tab Filter',
                Is_Active__c = true,
                Sequence__c = 20,
                Object_API_Name__c = 'Account',
                Field_API_Name__c = 'Name',
                Operator__c = 'Equals',
                Value_Type__c = 'Static',
                Value__c = 'Alpha'
            ),
            new Billing_Center_Filter_Config__c(
                Tab_Config__c = alphaTab.Id,
                Section_Config__c = alphaSectionA.Id,
                Dataset_Config__c = datasetAlpha.Id,
                Developer_Key__c = 'SECTION_FILTER',
                Label__c = 'Section Filter',
                Is_Active__c = true,
                Sequence__c = 10,
                Object_API_Name__c = 'Account',
                Field_API_Name__c = 'Industry',
                Operator__c = 'Contains',
                Value_Type__c = 'Static',
                Value__c = 'Service'
            )
        };

        insert new List<Billing_Center_Action_Config__c>{
            new Billing_Center_Action_Config__c(
                Tab_Config__c = alphaTab.Id,
                Developer_Key__c = 'TAB_ACTION',
                Label__c = 'Tab Action',
                Is_Active__c = true,
                Display_Order__c = 20,
                Action_Type__c = 'Refresh',
                Button_Variant__c = 'Neutral'
            ),
            new Billing_Center_Action_Config__c(
                Tab_Config__c = alphaTab.Id,
                Section_Config__c = alphaSectionA.Id,
                Developer_Key__c = 'SECTION_ACTION',
                Label__c = 'Section Action',
                Is_Active__c = true,
                Display_Order__c = 10,
                Action_Type__c = 'Modal',
                Button_Variant__c = 'Brand'
            )
        };
    }

    @IsTest
    static void getConfig_returnsActiveTabsInDisplayOrder() {
        Test.startTest();
        List<BillingControl_ConfigService.TabConfigDTO> tabs = BillingControl_ConfigService.getConfig();
        Test.stopTest();

        System.assertEquals(2, tabs.size(), 'Only active tabs should be returned.');
        System.assertEquals('BETA', tabs[0].developerKey, 'Tabs should be sorted by display order.');
        System.assertEquals('ALPHA', tabs[1].developerKey, 'Tabs should be sorted by display order.');
        System.assertEquals('Standard', tabs[0].navigationGroup);
        System.assertEquals('Object Home', tabs[0].navigationTargetType);
        System.assertEquals('Opportunity', tabs[0].targetObjectApiName);
        System.assertEquals(true, tabs[0].showInNavigation);
    }

    @IsTest
    static void getConfig_groupsSectionsAndChildrenUnderCorrectParents() {
        Test.startTest();
        List<BillingControl_ConfigService.TabConfigDTO> tabs = BillingControl_ConfigService.getConfig();
        Test.stopTest();

        BillingControl_ConfigService.TabConfigDTO alphaTab;
        for (BillingControl_ConfigService.TabConfigDTO tab : tabs) {
            if (tab.developerKey == 'ALPHA') {
                alphaTab = tab;
                break;
            }
        }

        System.assertNotEquals(null, alphaTab, 'Alpha tab should be present.');
        System.assertEquals(2, alphaTab.sections.size(), 'Only active sections should be returned.');
        System.assertEquals('SECTION_A', alphaTab.sections[0].developerKey, 'Sections should be sorted by display order.');
        System.assertEquals('SECTION_B', alphaTab.sections[1].developerKey, 'Sections should be sorted by display order.');
        System.assertEquals('DATASET_ALPHA', alphaTab.sections[0].datasetDeveloperKey, 'Section dataset keys should be carried through.');
        System.assertNotEquals(null, alphaTab.sections[0].dataset, 'Section dataset should be resolved.');
        System.assertEquals('DATASET_ALPHA', alphaTab.sections[0].dataset.developerKey, 'Resolved dataset should match the section key.');

        System.assertEquals(1, alphaTab.kpis.size(), 'Tab-level KPIs should stay on the tab.');
        System.assertEquals('TAB_KPI', alphaTab.kpis[0].developerKey);
        System.assertEquals(1, alphaTab.columns.size(), 'Tab-level columns should stay on the tab.');
        System.assertEquals('TAB_COLUMN', alphaTab.columns[0].developerKey);
        System.assertEquals(1, alphaTab.filters.size(), 'Tab-level filters should stay on the tab.');
        System.assertEquals('TAB_FILTER', alphaTab.filters[0].developerKey);
        System.assertEquals(1, alphaTab.actions.size(), 'Tab-level actions should stay on the tab.');
        System.assertEquals('TAB_ACTION', alphaTab.actions[0].developerKey);

        BillingControl_ConfigService.SectionConfigDTO sectionA = alphaTab.sections[0];
        System.assertEquals(1, sectionA.kpis.size(), 'Section-level KPIs should stay on the section.');
        System.assertEquals('SECTION_KPI', sectionA.kpis[0].developerKey);
        System.assertEquals(1, sectionA.columns.size(), 'Section-level columns should stay on the section.');
        System.assertEquals('SECTION_COLUMN', sectionA.columns[0].developerKey);
        System.assertEquals(1, sectionA.filters.size(), 'Section-level filters should stay on the section.');
        System.assertEquals('SECTION_FILTER', sectionA.filters[0].developerKey);
        System.assertEquals(1, sectionA.actions.size(), 'Section-level actions should stay on the section.');
        System.assertEquals('SECTION_ACTION', sectionA.actions[0].developerKey);
        System.assertEquals(1, alphaTab.datasets.size(), 'Used datasets should be surfaced once per tab.');
        System.assertEquals('DATASET_ALPHA', alphaTab.datasets[0].developerKey);
    }

    @IsTest
    static void getTabConfig_returnsOnlyRequestedTab() {
        Test.startTest();
        BillingControl_ConfigService.TabConfigDTO tab = BillingControl_ConfigService.getTabConfig('ALPHA');
        Test.stopTest();

        System.assertNotEquals(null, tab, 'Requested tab should be returned.');
        System.assertEquals('ALPHA', tab.developerKey);
        System.assertEquals(2, tab.sections.size(), 'Requested tab should include its sections.');
        System.assertEquals(1, tab.kpis.size(), 'Requested tab should include only its own tab-level records.');
        System.assertEquals('Billing', tab.navigationGroup);
        System.assertEquals('Internal BCC Tab', tab.navigationTargetType);
        System.assertEquals(true, tab.showInNavigation);
    }
}