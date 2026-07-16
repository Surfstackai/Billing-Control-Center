public with sharing class LookupSearchController {
    private static final String STAGE_CLOSED_WON = 'Closed Won';
    private static final Set<String> EXCLUDED_BILLING_STATUSES = new Set<String>{
        'Billed (Outstanding Receivable)',
        'Billed (Outstanding Receivables)',
        'Paid',
        'Partially Paid'
    };

    public class OpportunitySearchResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunitySearchResult> searchOpportunities(List<Id> allowedIds, String searchText) {
        Set<Id> filteredIds = new Set<Id>();
        if (allowedIds != null) {
            filteredIds.addAll(allowedIds);
        }

        if (filteredIds.isEmpty()) {
            return new List<OpportunitySearchResult>();
        }

        List<OpportunitySearchResult> results = new List<OpportunitySearchResult>();
        List<Opportunity> opportunityRecords;

        if (String.isBlank(searchText)) {
            opportunityRecords = [
                SELECT Id, Name, StageName, Amount, CloseDate
                FROM Opportunity
                WHERE Id IN :filteredIds
                AND StageName = :STAGE_CLOSED_WON
                AND (
                    Billing_Status__c = null
                    OR Billing_Status__c NOT IN :EXCLUDED_BILLING_STATUSES
                )
                ORDER BY Name ASC
                LIMIT 25
            ];
        } else {
            String normalizedSearch = '%' + searchText.trim() + '%';
            opportunityRecords = [
                SELECT Id, Name, StageName, Amount, CloseDate
                FROM Opportunity
                WHERE Id IN :filteredIds
                AND StageName = :STAGE_CLOSED_WON
                AND (
                    Billing_Status__c = null
                    OR Billing_Status__c NOT IN :EXCLUDED_BILLING_STATUSES
                )
                AND (
                    Name LIKE :normalizedSearch
                    OR StageName LIKE :normalizedSearch
                )
                ORDER BY Name ASC
                LIMIT 25
            ];
        }

        for (Opportunity opportunityRecord : opportunityRecords) {
            OpportunitySearchResult resultItem = new OpportunitySearchResult();
            resultItem.id = opportunityRecord.Id;
            resultItem.name = opportunityRecord.Name;
            resultItem.stageName = opportunityRecord.StageName;
            resultItem.amount = opportunityRecord.Amount;
            resultItem.closeDate = opportunityRecord.CloseDate;
            results.add(resultItem);
        }

        return results;
    }
}