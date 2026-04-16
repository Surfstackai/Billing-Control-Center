/**
 * Description: Controller for ImageCapture LWC.
 */

public class ImageCaptureController {

	@AuraEnabled
	public static Id uploadFileApex(String fileName, String base64Data, String description) {
    Blob body = EncodingUtil.base64Decode(base64Data);

    ContentVersion cv = new ContentVersion();
    cv.Title = fileName;
    cv.PathOnClient = fileName;
    cv.VersionData = body;
    cv.Description = description;
    insert cv;

    // Get ContentDocumentId
    cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

    return cv.ContentDocumentId;
	}

	@AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAssetsForServiceAppointment(Id serviceAppointmentId) {
        ServiceAppointment sa = [
            SELECT ParentRecordId, ParentRecordType
            FROM ServiceAppointment
            WHERE Id = :serviceAppointmentId
            LIMIT 1
        ];
        String workOrderId;
        if (sa.ParentRecordId != null && sa.ParentRecordType == 'WorkOrder') {
            workOrderId = sa.ParentRecordId;
        } else if (sa.ParentRecordId != null && sa.ParentRecordType == 'WorkOrderLineItem') {
            WorkOrderLineItem woli = [
                SELECT WorkOrderId FROM WorkOrderLineItem WHERE Id = :sa.ParentRecordId LIMIT 1
            ];
            workOrderId = woli.WorkOrderId;
        }
        if (String.isBlank(workOrderId)) {
            return new List<PicklistOption>();
        }
        List<WorkOrderLineItem> lineItems = [
            SELECT AssetId FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId AND AssetId != null
        ];
        Set<Id> assetIds = new Set<Id>();
        for (WorkOrderLineItem item : lineItems) {
            assetIds.add(item.AssetId);
        }
        if (assetIds.isEmpty()) {
            return new List<PicklistOption>();
        }
        List<Asset> assets = [SELECT Id, Name FROM Asset WHERE Id IN :assetIds ORDER BY Name ASC];
        List<PicklistOption> options = new List<PicklistOption>();
        for (Asset a : assets) {
            options.add(new PicklistOption(a.Name, a.Id));
        }
        return options;
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