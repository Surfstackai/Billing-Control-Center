public with sharing class OpportunitySelectorController {
    public class OpportunityOption {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String name;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
    }

    public class FlowRequest {
        @InvocableVariable(required=true label='Work Order Id')
        public Id workOrderId;
    }

    public class FlowResponse {
        @InvocableVariable(label='Work Order Id')
        public Id workOrderId;

        @InvocableVariable(label='Selected Opportunity Id')
        public Id selectedOpportunityId;

        @InvocableVariable(label='Allowed Opportunity Ids CSV')
        public String allowedOpportunityIdsCsv;

        @InvocableVariable(label='Opportunity Count')
        public Integer opportunityCount;

        @InvocableVariable(label='Has No Opportunities')
        public Boolean hasNoOpportunities;

        @InvocableVariable(label='Has Single Opportunity')
        public Boolean hasSingleOpportunity;

        @InvocableVariable(label='Has Multiple Opportunities')
        public Boolean hasMultipleOpportunities;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityOption> getOpenOpportunities(Id workOrderId) {
        if (workOrderId == null) {
            return new List<OpportunityOption>();
        }

        Map<Id, List<Opportunity>> opportunitiesByWorkOrderId =
            getOpenOpportunitiesByWorkOrderIds(new Set<Id>{ workOrderId });

        return toOptions(opportunitiesByWorkOrderId.get(workOrderId));
    }

    @InvocableMethod(
        label='Get Open Opportunities for Work Order'
        description='Returns open opportunities related to each work order and auto-selects when only one exists.'
    )
    public static List<FlowResponse> getOpenOpportunitiesForFlow(List<FlowRequest> requests) {
        List<FlowResponse> responses = new List<FlowResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> workOrderIds = new Set<Id>();
        for (FlowRequest requestItem : requests) {
            if (requestItem != null && requestItem.workOrderId != null) {
                workOrderIds.add(requestItem.workOrderId);
            }
        }

        Map<Id, List<Opportunity>> opportunitiesByWorkOrderId =
            getOpenOpportunitiesByWorkOrderIds(workOrderIds);

        for (FlowRequest requestItem : requests) {
            FlowResponse responseItem = new FlowResponse();
            responseItem.workOrderId = requestItem != null ? requestItem.workOrderId : null;

            List<Opportunity> opportunities = requestItem != null && requestItem.workOrderId != null
                ? opportunitiesByWorkOrderId.get(requestItem.workOrderId)
                : null;

            if (opportunities == null) {
                opportunities = new List<Opportunity>();
            }

            responseItem.opportunityCount = opportunities.size();
            responseItem.hasNoOpportunities = opportunities.isEmpty();
            responseItem.hasSingleOpportunity = opportunities.size() == 1;
            responseItem.hasMultipleOpportunities = opportunities.size() > 1;
            responseItem.selectedOpportunityId = responseItem.hasSingleOpportunity
                ? opportunities[0].Id
                : null;
            responseItem.allowedOpportunityIdsCsv = buildCsvFromOpportunities(opportunities);

            responses.add(responseItem);
        }

        return responses;
    }

    private static Map<Id, List<Opportunity>> getOpenOpportunitiesByWorkOrderIds(Set<Id> workOrderIds) {
        Map<Id, List<Opportunity>> results = new Map<Id, List<Opportunity>>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return results;
        }

        Map<Id, Set<Id>> opportunityIdsByWorkOrderId = new Map<Id, Set<Id>>();
        Set<Id> opportunityIds = new Set<Id>();

        for (Opportunity_WorkOrder__c junctionRecord : [
            SELECT Work_Order__c, Opportunity__c
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c IN :workOrderIds
            AND Opportunity__c != null
        ]) {
            if (!opportunityIdsByWorkOrderId.containsKey(junctionRecord.Work_Order__c)) {
                opportunityIdsByWorkOrderId.put(junctionRecord.Work_Order__c, new Set<Id>());
            }

            opportunityIdsByWorkOrderId.get(junctionRecord.Work_Order__c).add(junctionRecord.Opportunity__c);
            opportunityIds.add(junctionRecord.Opportunity__c);
        }

        if (opportunityIds.isEmpty()) {
            return results;
        }

        List<Opportunity> openOpportunities = [
            SELECT Id, Name, StageName, Amount, CloseDate
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND IsClosed = false
            ORDER BY CloseDate ASC NULLS LAST, Name ASC
        ];

        Map<Id, Opportunity> openOpportunitiesById = new Map<Id, Opportunity>(openOpportunities);

        for (Id workOrderId : opportunityIdsByWorkOrderId.keySet()) {
            List<Opportunity> opportunities = new List<Opportunity>();
            for (Opportunity opportunityRecord : openOpportunities) {
                if (opportunityIdsByWorkOrderId.get(workOrderId).contains(opportunityRecord.Id)) {
                    opportunities.add(opportunityRecord);
                }
            }
            results.put(workOrderId, opportunities);
        }

        return results;
    }

    private static String buildCsvFromOpportunities(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return null;
        }

        List<String> ids = new List<String>();
        for (Opportunity opportunityRecord : opportunities) {
            ids.add(String.valueOf(opportunityRecord.Id));
        }
        return String.join(ids, ',');
    }

    private static List<OpportunityOption> toOptions(List<Opportunity> opportunities) {
        List<OpportunityOption> options = new List<OpportunityOption>();
        if (opportunities == null) {
            return options;
        }

        for (Opportunity opportunityRecord : opportunities) {
            OpportunityOption option = new OpportunityOption();
            option.opportunityId = opportunityRecord.Id;
            option.name = opportunityRecord.Name;
            option.stageName = opportunityRecord.StageName;
            option.amount = opportunityRecord.Amount;
            option.closeDate = opportunityRecord.CloseDate;
            options.add(option);
        }

        return options;
    }
}