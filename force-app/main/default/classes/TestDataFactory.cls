@IsTest
public class TestDataFactory {
    private static User systemAdministratorUser;

    public static WorkType createWorkType() {
        return createWorkType('Test Work Type', 1);
    }

    public static WorkType createWorkType(String name) {
        return createWorkType(name, 1);
    }

    public static WorkType createWorkType(String name, Integer estimatedDuration) {
        WorkType workType = new WorkType(
            Name = name,
            EstimatedDuration = estimatedDuration,
            DurationType = 'Hours',
            ShouldAutoCreateSvcAppt = false
        );

        System.runAs(getSystemAdministratorUser()) {
            insert workType;
        }

        return workType;
    }

    private static User getSystemAdministratorUser() {
        if (systemAdministratorUser == null) {
            Profile systemAdministratorProfile = [
                SELECT Id
                FROM Profile
                WHERE Name = 'System Administrator'
                LIMIT 1
            ];

            String uniqueToken = String.valueOf(DateTime.now().getTime());
            systemAdministratorUser = new User(
                Alias = 'tadm',
                Email = 'testadmin+' + uniqueToken + '@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'TestAdmin',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = systemAdministratorProfile.Id,
                TimeZoneSidKey = 'America/New_York',
                UserName = 'testadmin+' + uniqueToken + '@example.com'
            );
            insert systemAdministratorUser;
        }

        return systemAdministratorUser;
    }
}