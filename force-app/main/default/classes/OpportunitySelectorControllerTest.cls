@isTest
private class OpportunitySelectorControllerTest {
    private static Set<String> getBillingStatusPicklistValues() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : Opportunity.Billing_Status__c.getDescribe().getPicklistValues()) {
            values.add(entry.getValue());
        }
        return values;
    }

    private static String firstAvailableStatus(Set<String> availableValues, List<String> candidates) {
        for (String candidate : candidates) {
            if (availableValues.contains(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    @testSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'Opportunity Selector Test Account');
        insert accountRecord;

        WorkType workTypeRecord = TestDataFactory.createWorkType('Test Work Type', 2);

        Set<String> availableBillingStatuses = getBillingStatusPicklistValues();
        String billedStatus = firstAvailableStatus(
            availableBillingStatuses,
            new List<String>{ 'Billed (Outstanding Receivable)', 'Billed (Outstanding Receivables)' }
        );
        String paidStatus = availableBillingStatuses.contains('Paid') ? 'Paid' : null;
        String partiallyPaidStatus = availableBillingStatuses.contains('Partially Paid') ? 'Partially Paid' : null;

        List<Opportunity> opportunities = new List<Opportunity>();
        opportunities.add(
            new Opportunity(
                Name = 'Alpha Eligible Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 100,
                CloseDate = Date.today(),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        );
        opportunities.add(
            new Opportunity(
                Name = 'Beta Eligible Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 250,
                CloseDate = Date.today(),
                Billing_Status__c = 'Awaiting Billing',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        );
        opportunities.add(
            new Opportunity(
                Name = 'Zeta Non Closed Won Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Prospecting',
                Amount = 800,
                CloseDate = Date.today().addDays(20),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        );
        opportunities.add(
            new Opportunity(
                Name = 'Eta Different Work Order Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 900,
                CloseDate = Date.today(),
                Billing_Status__c = 'Awaiting Billing',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        );

        if (billedStatus != null) {
            opportunities.add(
                new Opportunity(
                    Name = 'Gamma Billed Opportunity',
                    AccountId = accountRecord.Id,
                    StageName = 'Closed Won',
                    Amount = 500,
                    CloseDate = Date.today().addDays(-1),
                    Billing_Status__c = billedStatus,
                    Work_Type__c = workTypeRecord.Id,
                    Do_not_create_Work_Order__c = true
                )
            );
        }
        if (paidStatus != null) {
            opportunities.add(
                new Opportunity(
                    Name = 'Delta Paid Opportunity',
                    AccountId = accountRecord.Id,
                    StageName = 'Closed Won',
                    Amount = 600,
                    CloseDate = Date.today().addDays(-2),
                    Billing_Status__c = paidStatus,
                    Work_Type__c = workTypeRecord.Id,
                    Do_not_create_Work_Order__c = true
                )
            );
        }
        if (partiallyPaidStatus != null) {
            opportunities.add(
                new Opportunity(
                    Name = 'Epsilon Partially Paid Opportunity',
                    AccountId = accountRecord.Id,
                    StageName = 'Closed Won',
                    Amount = 700,
                    CloseDate = Date.today().addDays(-3),
                    Billing_Status__c = partiallyPaidStatus,
                    Work_Type__c = workTypeRecord.Id,
                    Do_not_create_Work_Order__c = true
                )
            );
        }
        insert opportunities;

        Map<String, Opportunity> opportunityByName = new Map<String, Opportunity>();
        for (Opportunity opportunityRecord : [
            SELECT Id, Name
            FROM Opportunity
            WHERE AccountId = :accountRecord.Id
        ]) {
            opportunityByName.put(opportunityRecord.Name, opportunityRecord);
        }

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(
                Subject = 'Single Opportunity Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Multiple Opportunity Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Closed Only Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            ),
            new WorkOrder(
                Subject = 'Different Junction Work Order',
                Status = 'New',
                AccountId = accountRecord.Id,
                WorkTypeId = workTypeRecord.Id
            )
        };
        insert workOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[0].Id,
                Opportunity__c = opportunityByName.get('Alpha Eligible Opportunity').Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[1].Id,
                Opportunity__c = opportunityByName.get('Alpha Eligible Opportunity').Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[1].Id,
                Opportunity__c = opportunityByName.get('Beta Eligible Opportunity').Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunityByName.get('Zeta Non Closed Won Opportunity').Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[3].Id,
                Opportunity__c = opportunityByName.get('Eta Different Work Order Opportunity').Id
            )
        };

        if (opportunityByName.containsKey('Gamma Billed Opportunity')) {
            insert new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunityByName.get('Gamma Billed Opportunity').Id
            );
        }
        if (opportunityByName.containsKey('Delta Paid Opportunity')) {
            insert new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunityByName.get('Delta Paid Opportunity').Id
            );
        }
        if (opportunityByName.containsKey('Epsilon Partially Paid Opportunity')) {
            insert new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunityByName.get('Epsilon Partially Paid Opportunity').Id
            );
        }
    }

    @isTest
    static void testGetOpenOpportunitiesReturnsOnlyEligibleRecords() {
        WorkOrder singleWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Single Opportunity Work Order'
            LIMIT 1
        ];

        Test.startTest();
        List<OpportunitySelectorController.OpportunityOption> results =
            OpportunitySelectorController.getOpenOpportunities(singleWorkOrder.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only one eligible opportunity should be returned.');
        System.assertEquals('Alpha Eligible Opportunity', results[0].name, 'The eligible opportunity should match the junction.');
        System.assertEquals('Closed Won', results[0].stageName, 'Stage should be exposed to the UI.');
    }

    @isTest
    static void testGetOpenOpportunitiesIncludesAwaitingAndNullBilling() {
        WorkOrder multipleWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Multiple Opportunity Work Order'
            LIMIT 1
        ];

        Test.startTest();
        List<OpportunitySelectorController.OpportunityOption> results =
            OpportunitySelectorController.getOpenOpportunities(multipleWorkOrder.Id);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Both Closed Won opportunities with null or Awaiting Billing should be eligible.');
        Set<String> returnedNames = new Set<String>();
        for (OpportunitySelectorController.OpportunityOption option : results) {
            returnedNames.add(option.name);
        }
        System.assert(returnedNames.contains('Alpha Eligible Opportunity'), 'Closed Won with null Billing_Status__c must be included.');
        System.assert(returnedNames.contains('Beta Eligible Opportunity'), 'Closed Won with Awaiting Billing must be included.');
    }

    @isTest
    static void testGetOpenOpportunitiesExcludesStatusesStageAndDifferentWorkOrder() {
        Map<String, Id> workOrderIdsBySubject = new Map<String, Id>();
        for (WorkOrder workOrderRecord : [
            SELECT Id, Subject
            FROM WorkOrder
            WHERE Subject IN ('Single Opportunity Work Order', 'Closed Only Work Order')
        ]) {
            workOrderIdsBySubject.put(workOrderRecord.Subject, workOrderRecord.Id);
        }

        Test.startTest();
        List<OpportunitySelectorController.OpportunityOption> excludedResults =
            OpportunitySelectorController.getOpenOpportunities(workOrderIdsBySubject.get('Closed Only Work Order'));
        List<OpportunitySelectorController.OpportunityOption> singleResults =
            OpportunitySelectorController.getOpenOpportunities(workOrderIdsBySubject.get('Single Opportunity Work Order'));
        Test.stopTest();

        Integer closedWonOnClosedOnly = [
            SELECT COUNT()
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c = :workOrderIdsBySubject.get('Closed Only Work Order')
            AND Opportunity__r.StageName = 'Closed Won'
        ];
        System.assertEquals(
            closedWonOnClosedOnly,
            excludedResults.size(),
            'Closed Won billed/paid jobs stay selectable; Prospecting stays out.'
        );
        System.assertEquals(1, singleResults.size(), 'Only the directly related eligible opportunity should be returned.');
        System.assertEquals('Alpha Eligible Opportunity', singleResults[0].name, 'Opportunity from a different work order junction must be excluded.');
    }

    @isTest
    static void testGetOpenOpportunitiesForFlowHandlesSingleMultipleAndNone() {
        Map<String, Id> workOrderIdsBySubject = new Map<String, Id>();
        for (WorkOrder workOrderRecord : [
            SELECT Id, Subject
            FROM WorkOrder
            WHERE Subject IN (
                'Single Opportunity Work Order',
                'Multiple Opportunity Work Order',
                'Closed Only Work Order'
            )
        ]) {
            workOrderIdsBySubject.put(workOrderRecord.Subject, workOrderRecord.Id);
        }

        List<OpportunitySelectorController.FlowRequest> requests =
            new List<OpportunitySelectorController.FlowRequest>();

        for (String subject : workOrderIdsBySubject.keySet()) {
            OpportunitySelectorController.FlowRequest requestItem =
                new OpportunitySelectorController.FlowRequest();
            requestItem.workOrderId = workOrderIdsBySubject.get(subject);
            requests.add(requestItem);
        }

        Test.startTest();
        List<OpportunitySelectorController.FlowResponse> responses =
            OpportunitySelectorController.getOpenOpportunitiesForFlow(requests);
        Test.stopTest();

        System.assertEquals(3, responses.size(), 'Each request should produce a response.');

        Map<Id, OpportunitySelectorController.FlowResponse> responsesByWorkOrderId =
            new Map<Id, OpportunitySelectorController.FlowResponse>();
        for (OpportunitySelectorController.FlowResponse responseItem : responses) {
            responsesByWorkOrderId.put(responseItem.workOrderId, responseItem);
        }

        OpportunitySelectorController.FlowResponse singleResponse =
            responsesByWorkOrderId.get(workOrderIdsBySubject.get('Single Opportunity Work Order'));
        System.assertEquals(true, singleResponse.hasSingleOpportunity, 'Single work order should auto-select.');
        System.assertNotEquals(null, singleResponse.selectedOpportunityId, 'Auto-selected opportunity should be returned.');
        System.assertEquals(1, singleResponse.opportunityCount, 'Single response should count one opportunity.');

        OpportunitySelectorController.FlowResponse multipleResponse =
            responsesByWorkOrderId.get(workOrderIdsBySubject.get('Multiple Opportunity Work Order'));
        System.assertEquals(true, multipleResponse.hasMultipleOpportunities, 'Multiple work order should require selection.');
        System.assertEquals(2, multipleResponse.opportunityCount, 'Two eligible opportunities should be returned.');
        System.assertEquals(null, multipleResponse.selectedOpportunityId, 'No auto-selection should happen for multiple matches.');
        System.assert(
            multipleResponse.allowedOpportunityIdsCsv.contains(','),
            'The CSV should carry both ids for the flow screen component.'
        );

        OpportunitySelectorController.FlowResponse billedJunctionResponse =
            responsesByWorkOrderId.get(workOrderIdsBySubject.get('Closed Only Work Order'));
        Integer closedWonOnClosedOnly = [
            SELECT COUNT()
            FROM Opportunity_WorkOrder__c
            WHERE Work_Order__c = :workOrderIdsBySubject.get('Closed Only Work Order')
            AND Opportunity__r.StageName = 'Closed Won'
        ];
        System.assertEquals(
            closedWonOnClosedOnly == 0,
            billedJunctionResponse.hasNoOpportunities,
            'hasNoOpportunities is true only when there is no Closed Won junction.'
        );
        System.assertEquals(
            closedWonOnClosedOnly,
            billedJunctionResponse.opportunityCount,
            'Billing status must not empty the picker when Closed Won junctions exist.'
        );
    }

    @isTest
    static void testLookupSearchControllerFiltersByAllowedIdsAndSearchText() {
        List<Opportunity> eligibleOpportunities = [
            SELECT Id, Name, StageName
            FROM Opportunity
            WHERE Name IN (
                'Alpha Eligible Opportunity',
                'Beta Eligible Opportunity',
                'Gamma Billed Opportunity',
                'Delta Paid Opportunity',
                'Epsilon Partially Paid Opportunity',
                'Zeta Non Closed Won Opportunity'
            )
            ORDER BY Name ASC
        ];

        List<Id> allowedIds = new List<Id>();
        for (Opportunity opportunityRecord : eligibleOpportunities) {
            allowedIds.add(opportunityRecord.Id);
        }

        Test.startTest();
        List<LookupSearchController.OpportunitySearchResult> blankSearchResults =
            LookupSearchController.searchOpportunities(allowedIds, null);
        List<LookupSearchController.OpportunitySearchResult> nameSearchResults =
            LookupSearchController.searchOpportunities(allowedIds, 'Beta');
        List<LookupSearchController.OpportunitySearchResult> billedSearchResults =
            LookupSearchController.searchOpportunities(allowedIds, 'Billed');
        List<LookupSearchController.OpportunitySearchResult> emptyAllowedResults =
            LookupSearchController.searchOpportunities(new List<Id>(), 'Alpha');
        Test.stopTest();

        Integer expectedBlank = 0;
        for (Opportunity opportunityRecord : eligibleOpportunities) {
            if (opportunityRecord.StageName == 'Closed Won') {
                expectedBlank++;
            }
        }
        System.assertEquals(
            expectedBlank,
            blankSearchResults.size(),
            'Blank search should return Closed Won allowed ids, including billed jobs.'
        );
        System.assertEquals(1, nameSearchResults.size(), 'Search text should narrow the results.');
        System.assertEquals('Beta Eligible Opportunity', nameSearchResults[0].name, 'Lookup search should return the matching opportunity.');
        Boolean gammaExists = false;
        for (Opportunity opportunityRecord : eligibleOpportunities) {
            if (opportunityRecord.Name == 'Gamma Billed Opportunity') {
                gammaExists = true;
            }
        }
        System.assertEquals(
            gammaExists ? 1 : 0,
            billedSearchResults.size(),
            'Billed Closed Won opportunities should appear when they are in the allowed id list.'
        );
        System.assertEquals(0, emptyAllowedResults.size(), 'No allowed ids means no lookup results.');
    }
}