/*
  @description : Retrieving contacts related to the account associated with the work order.
*/
public with sharing class SiteContactHelperClass {
    @AuraEnabled(cacheable=true)
    public static List<Site_Contact__c> getSiteContacts(Id workOrderId) {
        return [
            SELECT Id, Name, Account__c,Contact__c,Account__r.Name,Contact__r.Name,Email__c,Mobile__c,Other_Phone__c,Phone__c,Service_Appointment__c,Title__c,Work_Order__c
            FROM Site_Contact__c
            WHERE Work_Order__c = :workOrderId
        ];
    }
}