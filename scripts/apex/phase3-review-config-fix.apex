Billing_Center_Dataset_Config__c datasetConfig = [
    SELECT Id, Label__c, Apex_Handler_Key__c, Source_Object_API_Name__c
    FROM Billing_Center_Dataset_Config__c
    WHERE Developer_Key__c = 'ORDERS_WORK_ORDERS'
    LIMIT 1
];
datasetConfig.Label__c = 'Work Order Ledger';
datasetConfig.Apex_Handler_Key__c = 'BillingControl_WorkOrderLedger.getBucketWorkOrders';
datasetConfig.Source_Object_API_Name__c = 'Work_Order_Ledger__c';
update datasetConfig;

Billing_Center_Column_Config__c statusColumn = [
    SELECT Id, Label__c
    FROM Billing_Center_Column_Config__c
    WHERE Developer_Key__c = 'WORK_ORDER_STATUS'
    AND Tab_Config__r.Developer_Key__c = 'ORDERS'
    LIMIT 1
];
statusColumn.Label__c = 'Reconciliation Status';
update statusColumn;

System.debug(
    'Updated dataset ' + datasetConfig.Id
    + ' handler=' + datasetConfig.Apex_Handler_Key__c
    + ' source=' + datasetConfig.Source_Object_API_Name__c
    + ' column=' + statusColumn.Id
);
