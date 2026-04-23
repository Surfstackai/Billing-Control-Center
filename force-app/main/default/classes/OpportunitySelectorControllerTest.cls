@isTest
private class OpportunitySelectorControllerTest {
    private class TestData {
        Id singleWorkOrderId;
        Id multipleWorkOrderId;
        Id closedOnlyWorkOrderId;
        Id alphaOpportunityId;
        Id betaOpportunityId;
        Id closedOpportunityId;
    }

    @testSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'Opportunity Selector Test Account');
        insert accountRecord;

        WorkType workTypeRecord = TestDataFactory.createWorkType('Test Work Type', 2);

        List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Alpha Eligible Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 100,
                CloseDate = Date.today().addDays(10),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Beta Eligible Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 250,
                CloseDate = Date.today().addDays(15),
                Billing_Status__c = 'Ready for Billing',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Gamma Billed Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 500,
                CloseDate = Date.today().addDays(-1),
                Billing_Status__c = 'Billed (Outstanding Receivable)',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Delta Paid Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 600,
                CloseDate = Date.today().addDays(-2),
                Billing_Status__c = 'Paid',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Epsilon Partially Paid Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Closed Won',
                Amount = 700,
                CloseDate = Date.today().addDays(-3),
                Billing_Status__c = 'Partially Paid',
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Zeta Open Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Prospecting',
                Amount = 800,
                CloseDate = Date.today().addDays(20),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            ),
            new Opportunity(
                Name = 'Eta Open Opportunity',
                AccountId = accountRecord.Id,
                StageName = 'Qualification',
                Amount = 900,
                CloseDate = Date.today().addDays(25),
                Work_Type__c = workTypeRecord.Id,
                Do_not_create_Work_Order__c = true
            )
        };
        insert opportunities;

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
            )
        };
        insert workOrders;

        insert new List<Opportunity_WorkOrder__c>{
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[0].Id,
                Opportunity__c = opportunities[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[1].Id,
                Opportunity__c = opportunities[0].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[1].Id,
                Opportunity__c = opportunities[1].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunities[2].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunities[3].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunities[4].Id
            ),
            new Opportunity_WorkOrder__c(
                Work_Order__c = workOrders[2].Id,
                Opportunity__c = opportunities[5].Id
            )
        };
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

        OpportunitySelectorController.FlowResponse noneResponse =
            responsesByWorkOrderId.get(workOrderIdsBySubject.get('Closed Only Work Order'));
        System.assertEquals(true, noneResponse.hasNoOpportunities, 'Work order with only billed or open opportunities should produce no matches.');
        System.assertEquals(0, noneResponse.opportunityCount, 'Billed and non-Closed Won opportunities must be filtered out.');
    }

    @isTest
    static void testLookupSearchControllerFiltersByAllowedIdsAndSearchText() {
        List<Opportunity> eligibleOpportunities = [
            SELECT Id, Name
            FROM Opportunity
            WHERE Name IN ('Alpha Eligible Opportunity', 'Beta Eligible Opportunity')
            ORDER BY Name ASC
        ];

        List<Id> allowedIds = new List<Id>{ eligibleOpportunities[0].Id, eligibleOpportunities[1].Id };

        Test.startTest();
        List<LookupSearchController.OpportunitySearchResult> blankSearchResults =
            LookupSearchController.searchOpportunities(allowedIds, null);
        List<LookupSearchController.OpportunitySearchResult> nameSearchResults =
            LookupSearchController.searchOpportunities(allowedIds, 'Beta');
        List<LookupSearchController.OpportunitySearchResult> emptyAllowedResults =
            LookupSearchController.searchOpportunities(new List<Id>(), 'Alpha');
        Test.stopTest();

        System.assertEquals(2, blankSearchResults.size(), 'Blank search should return all allowed eligible opportunities.');
        System.assertEquals(1, nameSearchResults.size(), 'Search text should narrow the results.');
        System.assertEquals('Beta Eligible Opportunity', nameSearchResults[0].name, 'Lookup search should return the matching opportunity.');
        System.assertEquals(0, emptyAllowedResults.size(), 'No allowed ids means no lookup results.');
    }
}