Date today = Date.today();
List<Map<String, Object>> logs = new List<Map<String, Object>>();

List<ServiceAppointment> completedTodaySAs = [
    SELECT Id, AppointmentNumber, ParentRecordId, Status, ActualEndTime, Opportunity__c
    FROM ServiceAppointment
    WHERE Status = 'Completed'
    AND ActualEndTime != null
];

Set<Id> relevantWoIds = new Set<Id>();
for (ServiceAppointment sa : completedTodaySAs) {
    if (sa.ActualEndTime.date() == today) {
        relevantWoIds.add(sa.ParentRecordId);
    }
}

Map<Id, WorkOrder> woById = new Map<Id, WorkOrder>([
    SELECT Id, WorkOrderNumber, Status, TotalPrice
    FROM WorkOrder
    WHERE Id IN :relevantWoIds
]);

Map<Id, List<Id>> oppIdsByWoId = new Map<Id, List<Id>>();
for (Opportunity_WorkOrder__c j : [
    SELECT Opportunity__c, Work_Order__c
    FROM Opportunity_WorkOrder__c
    WHERE Work_Order__c IN :relevantWoIds
]) {
    if (!oppIdsByWoId.containsKey(j.Work_Order__c)) {
        oppIdsByWoId.put(j.Work_Order__c, new List<Id>());
    }
    oppIdsByWoId.get(j.Work_Order__c).add(j.Opportunity__c);
}

Set<Id> allOppIds = new Set<Id>();
for (List<Id> ids : oppIdsByWoId.values()) { allOppIds.addAll(ids); }
Map<Id, Opportunity> oppById = new Map<Id, Opportunity>([
    SELECT Id, Name, Amount, StageName, CloseDate
    FROM Opportunity
    WHERE Id IN :allOppIds
]);

BillingControl_Orders.KpiWrapper kpis = BillingControl_Orders.getKpis();
List<BillingControl_Orders.BucketSectionWrapper> sections = BillingControl_Orders.getBucketWorkOrders();

Map<String, Object> kpiSummary = new Map<String, Object>();
kpiSummary.put('completedTodaySAs_count', kpis.serviceAppointmentsCompletedTodayCount);
kpiSummary.put('completedTodaySAs_revenue', kpis.serviceAppointmentsCompletedTodayRevenue);

Map<String, Integer> sectionCounts = new Map<String, Integer>();
Boolean completedTodayWoIdsFoundInDrilldown = false;
for (BillingControl_Orders.BucketSectionWrapper s : sections) {
    sectionCounts.put(s.bucketKey, s.rows.size());
    if (s.bucketKey == 'COMPLETED_TODAY') {
        for (BillingControl_Orders.WorkOrderRowWrapper r : s.rows) {
            if (relevantWoIds.contains(r.workOrderId)) completedTodayWoIdsFoundInDrilldown = true;
        }
    }
}

for (ServiceAppointment sa : completedTodaySAs) {
    if (sa.ActualEndTime.date() != today) continue;
    WorkOrder wo = woById.get(sa.ParentRecordId);
    List<Id> oppIds = oppIdsByWoId.get(sa.ParentRecordId);
    List<Map<String, Object>> oppsSummary = new List<Map<String, Object>>();
    if (oppIds != null) {
        for (Id oid : oppIds) {
            Opportunity o = oppById.get(oid);
            if (o == null) continue;
            Map<String, Object> oppRow = new Map<String, Object>();
            oppRow.put('id', String.valueOf(o.Id));
            oppRow.put('name', o.Name);
            oppRow.put('stage', o.StageName);
            oppRow.put('closeDate', String.valueOf(o.CloseDate));
            oppRow.put('inScopeLastThreeYears', o.CloseDate != null && o.CloseDate >= Date.today().addYears(-3));
            oppRow.put('isClosedWon', o.StageName == 'Closed Won');
            oppRow.put('amount', o.Amount);
            oppsSummary.add(oppRow);
        }
    }
    Map<String, Object> row = new Map<String, Object>();
    row.put('hypothesisId', 'H1_H2_H3');
    row.put('saId', String.valueOf(sa.Id));
    row.put('saNumber', sa.AppointmentNumber);
    row.put('actualEndTime', String.valueOf(sa.ActualEndTime));
    row.put('saOpportunityField', String.valueOf(sa.Opportunity__c));
    row.put('workOrderId', String.valueOf(sa.ParentRecordId));
    row.put('workOrderNumber', wo != null ? wo.WorkOrderNumber : null);
    row.put('workOrderStatus', wo != null ? wo.Status : null);
    row.put('workOrderTotalPrice', wo != null ? wo.TotalPrice : null);
    row.put('junctionOpportunities', oppsSummary);
    logs.add(row);
}

Map<String, Object> payload = new Map<String, Object>();
payload.put('message', 'Completed Today KPI vs drilldown diagnostic');
payload.put('today', String.valueOf(today));
payload.put('kpi', kpiSummary);
payload.put('drilldownSectionRowCounts', sectionCounts);
payload.put('completedTodayWoAppearsInDrilldown', completedTodayWoIdsFoundInDrilldown);
payload.put('rows', logs);

System.debug('DEBUG_FFBC1B_PAYLOAD_START');
System.debug(JSON.serialize(payload));
System.debug('DEBUG_FFBC1B_PAYLOAD_END');
