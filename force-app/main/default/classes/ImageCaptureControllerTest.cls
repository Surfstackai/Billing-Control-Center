@isTest
private class ImageCaptureControllerTest {

    // ─────────────────────────────────────────────
    // Helper: create a minimal ServiceAppointment
    // whose parent is a WorkOrder with line items
    // ─────────────────────────────────────────────
    private static ServiceAppointment createServiceAppointmentWithWorkOrder(List<Id> assetIds) {
        // Create Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create Assets
        // (assetIds are assumed already inserted by the caller)
        // 
         WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        // Create WorkOrder
        WorkOrder wo = new WorkOrder(AccountId = acc.Id, Status = 'New', WorkTypeId = wt.Id);
        insert wo;

        // Create WorkOrderLineItems linked to assets
        List<WorkOrderLineItem> wolis = new List<WorkOrderLineItem>();
        for (Id assetId : assetIds) {
            wolis.add(new WorkOrderLineItem(WorkOrderId = wo.Id, AssetId = assetId));
        }
        if (!wolis.isEmpty()) {
            insert wolis;
        }

        // Create ServiceAppointment whose parent is the WorkOrder
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            EarliestStartTime = System.now(),
            DueDate = System.now().addDays(1)
        );
        insert sa;

        return sa;
    }

    private static List<Asset> createAssets(Integer count) {
        Account acc = new Account(Name = 'Asset Owner ' + count);
        insert acc;

        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < count; i++) {
            assets.add(new Asset(Name = 'Asset ' + i, AccountId = acc.Id));
        }
        insert assets;
        return assets;
    }

    // ─────────────────────────────────────────────
    // uploadFileApex – happy path
    // ─────────────────────────────────────────────
    @isTest
    static void testUploadFileApex_ReturnsContentDocumentId() {
        String fileName    = 'test-image.png';
        String description = 'Unit test upload';
        // Minimal valid base64 (1×1 white PNG)
        String base64Data  = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

        Test.startTest();
        Id contentDocumentId = ImageCaptureController.uploadFileApex(fileName, base64Data, description);
        Test.stopTest();

        System.assertNotEquals(null, contentDocumentId, 'ContentDocumentId should not be null');

        // Verify the ContentVersion was created with correct values
        List<ContentVersion> cvs = [
            SELECT Title, Description, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
        ];
        System.assertEquals(1, cvs.size(), 'Exactly one ContentVersion should exist');
        System.assertEquals(fileName,    cvs[0].Title,       'Title should match fileName');
        System.assertEquals(description, cvs[0].Description, 'Description should match');
    }

    // ─────────────────────────────────────────────
    // uploadFileApex – different file names / descriptions
    // ─────────────────────────────────────────────
    @isTest
    static void testUploadFileApex_StoresCorrectMetadata() {
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('hello world'));

        Test.startTest();
        Id docId = ImageCaptureController.uploadFileApex('report.pdf', base64Data, 'A PDF report');
        Test.stopTest();

        ContentVersion cv = [SELECT Title, Description FROM ContentVersion WHERE ContentDocumentId = :docId LIMIT 1];
        System.assertEquals('report.pdf',  cv.Title);
        System.assertEquals('A PDF report', cv.Description);
    }

    // ─────────────────────────────────────────────
    // getAssetsForServiceAppointment – parent is WorkOrder
    // ─────────────────────────────────────────────
    @isTest
    static void testGetAssets_ParentIsWorkOrder_ReturnsAssets() {
        List<Asset> assets = createAssets(3);
        List<Id> assetIds = new List<Id>();
        for (Asset a : assets) assetIds.add(a.Id);

        ServiceAppointment sa = createServiceAppointmentWithWorkOrder(assetIds);

        Test.startTest();
        List<ImageCaptureController.PicklistOption> options =
            ImageCaptureController.getAssetsForServiceAppointment(sa.Id);
        Test.stopTest();

        System.assertEquals(3, options.size(), 'Should return 3 picklist options');
        // Options should be sorted by Name ASC – verify labels & values are populated
        for (ImageCaptureController.PicklistOption opt : options) {
            System.assertNotEquals(null, opt.label,  'Label should not be null');
            System.assertNotEquals(null, opt.value,  'Value should not be null');
        }
    }

    // ─────────────────────────────────────────────
    // getAssetsForServiceAppointment – parent is WorkOrderLineItem
    // ─────────────────────────────────────────────
    @isTest
    static void testGetAssets_ParentIsWorkOrderLineItem_ReturnsAssets() {
        List<Asset> assets = createAssets(2);

        // Create supporting records
        Account acc = new Account(Name = 'WOLI Parent Account');
        insert acc;
        
         WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        // Create WorkOrder
        WorkOrder wo = new WorkOrder(AccountId = acc.Id, Status = 'New', WorkTypeId = wt.Id);
        insert wo;

        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = wo.Id,
            AssetId     = assets[0].Id
        );
        insert woli;

        // Another WOLI on the same WO
        WorkOrderLineItem woli2 = new WorkOrderLineItem(
            WorkOrderId = wo.Id,
            AssetId     = assets[1].Id
        );
        insert woli2;

        // ServiceAppointment whose parent is a WorkOrderLineItem
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId  = woli.Id,
            EarliestStartTime = System.now(),
            DueDate           = System.now().addDays(1)
        );
        insert sa;

        Test.startTest();
        List<ImageCaptureController.PicklistOption> options =
            ImageCaptureController.getAssetsForServiceAppointment(sa.Id);
        Test.stopTest();

        // Both assets on the WorkOrder should be returned
        System.assertEquals(2, options.size(), 'Should return 2 picklist options via WOLI parent');
    }

    // ─────────────────────────────────────────────
    // getAssetsForServiceAppointment – no line items with assets
    // ─────────────────────────────────────────────
    @isTest
    static void testGetAssets_NoAssets_ReturnsEmptyList() {
        // WorkOrder with a WOLI that has no AssetId
        Account acc = new Account(Name = 'No Asset Account');
        insert acc;

        WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        // Create WorkOrder
        WorkOrder wo = new WorkOrder(AccountId = acc.Id, Status = 'New', WorkTypeId = wt.Id);
        insert wo;

        WorkOrderLineItem woli = new WorkOrderLineItem(WorkOrderId = wo.Id);
        insert woli;

        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId    = wo.Id,
            EarliestStartTime = System.now(),
            DueDate           = System.now().addDays(1)
        );
        insert sa;

        Test.startTest();
        List<ImageCaptureController.PicklistOption> options =
            ImageCaptureController.getAssetsForServiceAppointment(sa.Id);
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Should return empty list when no assets');
    }

    // ─────────────────────────────────────────────
    // getAssetsForServiceAppointment – no line items at all
    // ─────────────────────────────────────────────
    @isTest
    static void testGetAssets_NoLineItems_ReturnsEmptyList() {
        Account acc = new Account(Name = 'Empty WO Account');
        insert acc;

        WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        // Create WorkOrder
        WorkOrder wo = new WorkOrder(AccountId = acc.Id, Status = 'New', WorkTypeId = wt.Id);
        insert wo;

        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId    = wo.Id,
            EarliestStartTime = System.now(),
            DueDate           = System.now().addDays(1)
        );
        insert sa;

        Test.startTest();
        List<ImageCaptureController.PicklistOption> options =
            ImageCaptureController.getAssetsForServiceAppointment(sa.Id);
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Should return empty list when no WOLIs');
    }

    // ─────────────────────────────────────────────
    // PicklistOption inner class
    // ─────────────────────────────────────────────
    @isTest
    static void testPicklistOption_ConstructorSetsFields() {
        ImageCaptureController.PicklistOption opt =
            new ImageCaptureController.PicklistOption('My Label', 'my-value');

        System.assertEquals('My Label',  opt.label,  'Label should be set by constructor');
        System.assertEquals('my-value',  opt.value,  'Value should be set by constructor');
    }

    // ─────────────────────────────────────────────
    // Result ordering – assets returned A-Z by Name
    // ─────────────────────────────────────────────
    @isTest
    static void testGetAssets_ReturnedInAlphaOrder() {
        Account acc = new Account(Name = 'Order Test Account');
        insert acc;

        List<Asset> assets = new List<Asset>{
            new Asset(Name = 'Zebra Asset',  AccountId = acc.Id),
            new Asset(Name = 'Alpha Asset',  AccountId = acc.Id),
            new Asset(Name = 'Middle Asset', AccountId = acc.Id)
        };
        insert assets;

        List<Id> assetIds = new List<Id>();
        for (Asset a : assets) assetIds.add(a.Id);

        ServiceAppointment sa = createServiceAppointmentWithWorkOrder(assetIds);

        Test.startTest();
        List<ImageCaptureController.PicklistOption> options =
            ImageCaptureController.getAssetsForServiceAppointment(sa.Id);
        Test.stopTest();

        System.assertEquals(3, options.size());
        System.assertEquals('Alpha Asset',  options[0].label, 'First option should be Alpha Asset');
        System.assertEquals('Middle Asset', options[1].label, 'Second option should be Middle Asset');
        System.assertEquals('Zebra Asset',  options[2].label, 'Third option should be Zebra Asset');
    }
}