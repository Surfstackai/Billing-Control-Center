/**
 * @description       : Controller class for managing Assessment records.
 *                      Provides methods to retrieve assessment questions (template-based and active)
 *                      and save user responses to assessments.
 *                      Designed to be used in Lightning Components via @AuraEnabled methods.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @last modified on  : 03-11-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/

public with sharing class AssessmentController {
    @AuraEnabled(cacheable=true)
    public static List<Assessment__c> getAssessmentQuestions() {
        return [SELECT Id,Sequence__c, Question__c, Data_Type__c, Service_Appointment__c, Picklist_Values__c, IsTemplate__c, Answer__c, Image__c, Required__c,Question_header__c  FROM Assessment__c WHERE IsTemplate__c = true and IsActive__c = true ORDER BY Sequence__c ASC];
    }

    @AuraEnabled(cacheable=true)
    public static AssessmentInitWrapper initAssessment(Id serviceAppointmentId, Long refreshKey) {
        System.debug('serviceAppointmentId: ' + serviceAppointmentId);

        AssessmentInitWrapper result = new AssessmentInitWrapper();

        //Fetch Assessment Template Questions
        result.questions = [
            SELECT Id, Sequence__c, Question__c, Data_Type__c,
                Picklist_Values__c, Answer__c, Required__c,
                Question_header__c
            FROM Assessment__c
            WHERE IsTemplate__c = true
            AND IsActive__c = true
            ORDER BY Sequence__c ASC
        ];
        System.debug('Questions: ' + result.questions);

        //Resolve Assets from Service Appointment
        Set<Id> assetIds = new Set<Id>();

        ServiceAppointment sa = [
            SELECT ParentRecordId, ParentRecordType
            FROM ServiceAppointment
            WHERE Id = :serviceAppointmentId
            LIMIT 1
        ];
        System.debug('SA: ' + sa);

        String workOrderId;

        if (sa.parentRecordId != null &&
            sa.ParentRecordType == 'WorkOrder') {
                workOrderId = sa.ParentRecordId;
        } else if (sa.ParentRecordId != null &&
            sa.ParentRecordType == 'WorkOrderLineItem') {

            WorkOrderLineItem woli = [
                SELECT WorkOrderId
                FROM WorkOrderLineItem
                WHERE Id = :sa.ParentRecordId
                LIMIT 1
            ];
            
            workOrderId = woli.WorkOrderId;
        }
        System.debug('WorkORderId: ' + workOrderId);

        List<WorkOrderLineItem> lineItems = [
            SELECT AssetId
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
            AND AssetId != null
        ];

        if (String.isNotBlank(workOrderId)) {
            for (WorkOrderLineItem item : lineItems) {
                assetIds.add(item.AssetId);
            }


            Set<String> assessmentCompletedAssets = new Set<String>();
            if(!assetIds.isEmpty()) {
                List<Assessment__c> completedAssests = [
                    SELECT Asset__c, Asset__r.Name
                    FROM Assessment__c
                    WHERE Service_Appointment__c = :serviceAppointmentId
                    AND Asset__c IN :assetIds
                    AND IsTemplate__c = false];
                System.debug('Completed Assets: ' + completedAssests);

                if(!completedAssests.isEmpty()) {
                    for (Assessment__c a : completedAssests) {
                        assessmentCompletedAssets.add(a.Asset__r.Name);
                    }
                } 
                System.debug('Completed assessmentCompletedAssets: ' + assessmentCompletedAssets);  
            }
            result.assessmentCompletedAssets = new List<String>(assessmentCompletedAssets);

            List<Asset> assets = [
                SELECT Id, Name
                FROM Asset
                WHERE Id IN :assetIds
            ];
            // Build Asset Picklist Options (unique by Id)
            result.assetOptions = new List<PicklistOption>();
            if (!assetIds.isEmpty()) {
                for (Asset a : assets) {
                    result.assetOptions.add(
                        new PicklistOption(a.Name, a.Id)
                    );
                }
            }
        }
            
        System.debug('assetOptions: ' + result.assetOptions);
        return result;
    }


    @AuraEnabled
    public static void saveAssessmentAnswers(List<Assessment__c> assessments) {
        try {
            if (assessments != null || !assessments.isEmpty()) {
    				upsert assessments;
				}
       		} 
        catch (Exception e) {
           throw new AuraHandledException(e.getMessage());
        }
    }

    public class AssessmentInitWrapper {
        @AuraEnabled public List<Assessment__c> questions;
        @AuraEnabled public List<PicklistOption> assetOptions;
        @AuraEnabled public List<String> assessmentCompletedAssets;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}