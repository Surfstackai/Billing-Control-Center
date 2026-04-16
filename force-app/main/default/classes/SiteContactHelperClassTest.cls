@isTest(seeAllData=false)
public class SiteContactHelperClassTest {

    @isTest
    static void testGetSiteContacts() {
        
        Account acc = new Account();
        acc.Name = 'Test Account';
        acc.BillingStreet = '47 West 13th Streeta';
        acc.BillingCity ='New York';
        acc.BillingCountry = 'United States';
        acc.BillingPostalCode ='13867';
        acc.BillingState = 'NY';
           insert acc;
        
        
        WorkType wt = TestDataFactory.createWorkType('Inspection', 2);

        
        Contact con = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = acc.Id);
        insert con;
        
       WorkOrder wo = new WorkOrder(
            Subject = 'Test Work Order',
           Status = 'For Clearance',
            AccountId = acc.Id,
            WorkTypeId = wt.Id);
        insert wo;   
       
        Site_Contact__c siteContact = new Site_Contact__c(
            Account__c = acc.Id,
            Contact__c = con.Id,
            Work_Order__c = wo.Id);
        insert siteContact;

        Test.startTest();
        List<Site_Contact__c> result = SiteContactHelperClass.getSiteContacts(wo.Id);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(acc.Name, result[0].Account__r.Name, 'Account name should be populated');
        System.assertEquals(con.FirstName + ' ' + con.LastName, result[0].Contact__r.Name, 'Contact name should be populated');
    }
}