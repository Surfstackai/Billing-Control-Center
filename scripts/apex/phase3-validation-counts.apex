BillingControl_WorkOrderLedger.ValidationCountsWrapper counts =
    BillingControl_WorkOrderLedger.getValidationCounts();
System.debug(LoggingLevel.ERROR, 'VALIDATION_COUNTS=' + JSON.serialize(counts));
System.debug(LoggingLevel.ERROR, 'LEDGER_SYNC_SHOULD_RUN=' + WorkOrderLedgerAutomationControl.shouldRunSyncAutomation());
System.debug(LoggingLevel.ERROR, 'ORDER_DIARY_SYNC_SHOULD_RUN=' + OrderDiaryAutomationControl.shouldRunSyncAutomation());

Integer ledgerDisabled = [
    SELECT COUNT()
    FROM Billing_Center_Global_Setting__c
    WHERE Is_Active__c = true
    AND Disable_Work_Order_Ledger_Automation__c = true
];
Integer diaryDisabled = [
    SELECT COUNT()
    FROM Billing_Center_Global_Setting__c
    WHERE Is_Active__c = true
    AND Disable_Order_Diary_Sync_Automation__c = true
];
System.debug(LoggingLevel.ERROR, 'LEDGER_DISABLED_SETTING=' + ledgerDisabled);
System.debug(LoggingLevel.ERROR, 'ORDER_DIARY_DISABLED_SETTING=' + diaryDisabled);
