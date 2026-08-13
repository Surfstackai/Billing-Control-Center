public without sharing class OrderDiaryAutomationControl {
    @TestVisible
    private static Boolean automationEnabledForTests = false;
    private static Boolean syncAutomationDisabled;

    public static Boolean shouldRun() {
        return !Test.isRunningTest() || automationEnabledForTests;
    }

    public static Boolean shouldRunSyncAutomation() {
        if (Test.isRunningTest()) {
            return automationEnabledForTests;
        }
        if (syncAutomationDisabled == null) {
            syncAutomationDisabled = isSyncAutomationDisabledBySetting();
        }
        return !syncAutomationDisabled;
    }

    @TestVisible
    public static void enableForTests() {
        automationEnabledForTests = true;
        syncAutomationDisabled = false;
    }

    @TestVisible
    public static void disableForTests() {
        automationEnabledForTests = false;
        syncAutomationDisabled = true;
    }

    private static Boolean isSyncAutomationDisabledBySetting() {
        return [
            SELECT COUNT()
            FROM Billing_Center_Global_Setting__c
            WHERE Is_Active__c = true
            AND Disable_Order_Diary_Sync_Automation__c = true
        ] > 0;
    }
}