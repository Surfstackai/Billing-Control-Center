@isTest
public class AssessmentControllerTest {

    // Setup method to create test data once for all test methods
    @testSetup
    static void setupTestData() {
        List<Assessment__c> assessments = new List<Assessment__c>();
        for (Integer i = 1; i <= 5; i++) {
            assessments.add(new Assessment__c(
                Sequence__c = i,
                Question__c = 'Question ' + i,
                Data_Type__c = 'Text',
                IsTemplate__c = true,
                Required__c = true,
                IsActive__c = true
            ));
        }
        insert assessments;

        // Create Account (required for Asset)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        // Create Asset
        Asset asset = new Asset(
            Name = 'Test Asset',
            AccountId = acc.Id,
            Status = 'Installed'
        );
        insert asset;

        // Create Work Order
        WorkOrder wo = new WorkOrder(
            Subject = 'Test Work Order',
            Status = 'New',
            AccountId = acc.Id,
            WorkTypeId = wt.Id
        );
        insert wo;

        // Create Work Order Line Item
        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = wo.Id,
            AssetId = asset.Id
        );
        insert woli;

        // Service Appointment linked to Work Order
        ServiceAppointment saWO = new ServiceAppointment(
            ParentRecordId = wo.Id,
            Status = 'Scheduled',
            EarliestStartTime = System.now(),
            DueDate = System.now().addHours(2)
        );
        insert saWO;

        // Service Appointment linked to Work Order Line Item
        ServiceAppointment saWOLI = new ServiceAppointment(
            ParentRecordId = woli.Id,
            Status = 'Scheduled',
            EarliestStartTime = System.now(),
            DueDate = System.now().addHours(2)
        );
        insert saWOLI;
    }

    // Test method for getAssessmentQuestions()
    @isTest
    static void testGetAssessmentQuestions() {
        Test.startTest();
        List<Assessment__c> results = AssessmentController.getAssessmentQuestions();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Result should not be null');
        System.assertEquals(5, results.size(), 'Expected 5 assessment records');
    }

    // Test method for saveAssessmentAnswers()
    @isTest
    static void testSaveAssessmentAnswers() {
        List<Assessment__c> assessments = [SELECT Id, Answer__c FROM Assessment__c];
        for (Assessment__c a : assessments) {
            a.Answer__c = 'Sample Answer';
        }

        Test.startTest();
        AssessmentController.saveAssessmentAnswers(assessments);

        Boolean exceptionThrown = false;
        try {
            AssessmentController.saveAssessmentAnswers(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        List<Assessment__c> updatedAssessments = [SELECT Id, Answer__c FROM Assessment__c];
        for (Assessment__c a : updatedAssessments) {
            System.assertEquals('Sample Answer', a.Answer__c, 'Answer should be updated');
        }

        System.assertEquals(true, exceptionThrown, 'Exception should be thrown for null input');
    }

    // =========================
    // Test: Parent = WorkOrder
    // =========================
    @isTest
    static void testInitAssessment_WorkOrder() {

        ServiceAppointment sa = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordType = 'WorkOrder'
            LIMIT 1
        ];

        Test.startTest();
        AssessmentController.AssessmentInitWrapper result =
            AssessmentController.initAssessment(sa.Id, Long.valueOf('1'));
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should not be null');
        System.assertNotEquals(null, result.questions, 'Questions should not be null');
        System.assertEquals(5, result.questions.size(), 'Expected 5 template questions');

        System.assertNotEquals(null, result.assetOptions, 'Asset options should not be null');
        System.assertEquals(1, result.assetOptions.size(), 'Expected 1 asset option');

        AssessmentController.PicklistOption option = result.assetOptions[0];
        System.assertNotEquals(null, option.label, 'Asset label should be populated');
        System.assertNotEquals(null, option.value, 'Asset value should be populated');
    }

    // =====================================
    // Test: Parent = WorkOrderLineItem
    // =====================================
    @isTest
    static void testInitAssessment_WorkOrderLineItem() {

        ServiceAppointment sa = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordType = 'WorkOrderLineItem'
            LIMIT 1
        ];

        Test.startTest();
        AssessmentController.AssessmentInitWrapper result =
            AssessmentController.initAssessment(sa.Id, Long.valueOf('1'));
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should not be null');
        System.assertEquals(5, result.questions.size(), 'Expected 5 template questions');

        System.assertEquals(1, result.assetOptions.size(), 'Expected 1 asset from WOLI');
    }

    // =========================
    // Test: No Assets scenario
    // =========================
    @isTest
    static void testInitAssessment_NoAssets() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        WorkOrder woNoAsset = new WorkOrder(
            Subject = 'WO Without Asset',
            Status = 'New',
            AccountId = acc.Id,
            WorkTypeId = wt.Id
        );
        insert woNoAsset;

        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = woNoAsset.Id,
            Status = 'Scheduled',
            EarliestStartTime = System.now(),
            DueDate = System.now().addHours(1)
        );
        insert sa;

        Test.startTest();
        AssessmentController.AssessmentInitWrapper result =
            AssessmentController.initAssessment(sa.Id, Long.valueOf('1'));
        Test.stopTest();

        System.assertEquals(5, result.questions.size(), 'Questions should still be returned');
        System.assertEquals(
            true,
            result.assetOptions == null || result.assetOptions.isEmpty(),
            'Asset options should be empty when no assets exist'
        );
    }
}