from pathlib import Path

ROOT = Path(r"c:\Users\matth\Github Local\Propump billing controller\force-app\main\default\classes")

replacements = [
    ("SELECT Id, Invoice__c, Billing_Order__c, Line_Total__c", "SELECT Id, Invoice__c, Line_Total__c"),
    ("SELECT Line_Total__c, Billing_Order__c", "SELECT Line_Total__c"),
    ("SELECT Billing_Order__c, Line_Total__c, Service_Appointment__c", "SELECT Line_Total__c, Service_Appointment__c"),
    ("SELECT Billing_Order__c, Line_Total__c", "SELECT Line_Total__c"),
    ("SELECT Billing_Order__c, Service_Appointment__c, Work_Order__c", "SELECT Service_Appointment__c, Work_Order__c"),
    ("SELECT Billing_Order__c\n            FROM Invoice_Line__c", "SELECT Id\n            FROM Invoice_Line__c"),
    ("System.assertEquals(null, invoiceLineRecord.Billing_Order__c, 'Complete Billing must not write Billing_Order__c.');",
     "System.assertNotEquals(null, invoiceLineRecord.Invoice__c, 'Complete Billing must create Invoice_Line__c.');"),
    ("System.assertEquals(null, createdInvoiceLine.Billing_Order__c, 'Complete Billing must not write Billing_Order__c.');",
     "System.assertNotEquals(null, createdInvoiceLine.Line_Total__c, 'Complete Billing must create Invoice_Line__c.');"),
    ("System.assertEquals(null, createdLine.Billing_Order__c, 'Complete Billing must not write Billing_Order__c.');",
     "System.assertNotEquals(null, createdLine.Line_Total__c, 'Complete Billing must create Invoice_Line__c.');"),
    ("System.assertEquals(null, createdInvoiceLines[0].Billing_Order__c, 'Complete Billing must not write Billing_Order__c.');\n        ",
     ""),
    ("System.assertEquals(null, createdLine.Billing_Order__c, 'INV-Sync must not write Billing_Order__c.');",
     "System.assertNotEquals(null, createdLine.Service_Appointment__c, 'INV-Sync must create Invoice_Line__c.');"),
    ("System.assertEquals(null, createdLine.Billing_Order__c);",
     "System.assertNotEquals(null, createdLine.Id);"),
    ("Service_Appointment__c = appointments[3].Id, Billing_Order__c = diaryOrders[3].Id, Description__c = 'Historical partial amount',",
     "Service_Appointment__c = appointments[3].Id, Description__c = 'Historical partial amount',"),
]

service = ROOT / "BillingControl_InvoicingTest.cls"
text = service.read_text(encoding="utf-8")
for old, new in replacements:
    text = text.replace(old, new)

text = text.replace(
"""        Order readyOrder = [
            SELECT Id, Service_Appointment__c, OpportunityId
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        update new Opportunity(Id = readyOrder.OpportunityId, Amount = 0);

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ readyOrder.Service_Appointment__c },
                new Map<String, String>{ String.valueOf(readyOrder.OpportunityId) => 'NO-AMOUNT-001' }
            );""",
"""        ServiceAppointment readyAppointment = [
            SELECT Id, Opportunity__c
            FROM ServiceAppointment
            WHERE Subject = 'Completed Unbilled Older'
            LIMIT 1
        ];
        update new Opportunity(Id = readyAppointment.Opportunity__c, Amount = 0);

        Test.startTest();
        try {
            BillingControl_Invoicing.completeServiceAppointmentBilling(
                new List<Id>{ readyAppointment.Id },
                new Map<String, String>{ String.valueOf(readyAppointment.Opportunity__c) => 'NO-AMOUNT-001' }
            );"""
)

text = text.replace(
"""        Order readyOrder = [
            SELECT EffectiveDate
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildInvoicingFilter(
                'ORDER',
                'EffectiveDate',
                'Greater Or Equal',
                formatDateValue(readyOrder.EffectiveDate.addDays(-1)),
                'Static',
                10
            )
        );""",
"""        Date effectiveDate = Date.today();

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =
            new BillingControl_DataProvider.BillingFilterContextDTO();
        filterContext.tabKey = 'INVOICING';
        filterContext.datasetKey = 'INVOICING_SERVICE_APPOINTMENTS';
        filterContext.filters.add(
            buildInvoicingFilter(
                'ORDER',
                'EffectiveDate',
                'Greater Or Equal',
                formatDateValue(effectiveDate.addDays(-1)),
                'Static',
                10
            )
        );"""
)
service.write_text(text, encoding="utf-8")
print("service Billing_Order", text.count("Billing_Order__c"))
print("service FROM Order", text.count("FROM Order"))

provider = ROOT / "BillingControl_DataProviderTest.cls"
ptext = provider.read_text(encoding="utf-8")
ptext = ptext.replace(
"""        for (Order orderRecord : [
            SELECT Status
            FROM Order
            WHERE Service_Appointment__c IN :scheduledAppointmentIds
        ]) {
            System.assertEquals('Draft', orderRecord.Status);
        }""",
"""        System.assertEquals(2, scheduledAppointmentIds.size());"""
)
ptext = ptext.replace(
"""        Order filteredOrder = [
            SELECT Id, EffectiveDate, Invoiced_Amount__c
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertNotEquals(null, filteredOrder.EffectiveDate);
        System.assertEquals(0, filteredOrder.Invoiced_Amount__c);

        BillingControl_DataProvider.BillingFilterContextDTO filterContext =""",
"""        BillingControl_DataProvider.BillingFilterContextDTO filterContext ="""
)
ptext = ptext.replace(
"""        Order readyOrder = [
            SELECT Id, AccountId, OpportunityId, Work_Order__c, EffectiveDate
            FROM Order
            WHERE Billing_Diary_Status__c = 'Ready to Bill'
            AND Ready_For_Billing__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        WorkOrder readyWorkOrder = [
            SELECT Id, WorkTypeId
            FROM WorkOrder
            WHERE Id = :readyOrder.Work_Order__c
            LIMIT 1
        ];""",
"""        WorkOrder readyWorkOrder = [
            SELECT Id, WorkTypeId, AccountId
            FROM WorkOrder
            WHERE Subject LIKE 'Provider WO%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Date effectiveDate = Date.today();"""
)
ptext = ptext.replace("readyOrder.EffectiveDate", "effectiveDate")
ptext = ptext.replace("readyOrder.AccountId", "readyWorkOrder.AccountId")
ptext = ptext.replace("readyOrder.OpportunityId", "null")
provider.write_text(ptext, encoding="utf-8")
print("provider FROM Order", ptext.count("FROM Order"))
print("provider Invoiced_Amount", ptext.count("Invoiced_Amount__c"))
