from pathlib import Path
import re

path = Path(__file__).resolve().parents[1] / "force-app/main/default/classes/BillingControl_Invoicing.cls"
text = path.read_text(encoding="utf-8")
lines = text.splitlines()


def find_method(name, match_text=None):
    pattern = re.compile(rf"^\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:public|private).*?\s{name}\s*\(")
    for index, line in enumerate(lines):
        if not pattern.search(line):
            continue
        window = "\n".join(lines[index : index + 6])
        if match_text and match_text not in window:
            continue
        start = index
        while start > 0 and lines[start - 1].strip().startswith("@"):
            start -= 1
        brace = 0
        started = False
        end = start
        for cursor in range(start, len(lines)):
            for char in lines[cursor]:
                if char == "{":
                    brace += 1
                    started = True
                elif char == "}":
                    brace -= 1
            if started and brace == 0:
                end = cursor
                break
        return start, end
    raise SystemExit("Missing method %s %s" % (name, match_text or ""))


replacements = {
    ("completeServiceAppointmentBilling", None): """    @AuraEnabled
    public static CompleteBillingResultWrapper completeServiceAppointmentBilling(
        List<Id> serviceAppointmentIds,
        Map<String, String> invoiceNumberByOpportunityId
    ) {
        return BillingControl_CompleteBilling.completeServiceAppointmentBilling(
            serviceAppointmentIds,
            invoiceNumberByOpportunityId
        );
    }""",
    ("queryInvSyncCandidateAppointments", None): """    public static List<ServiceAppointment> queryInvSyncCandidateAppointments(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter
    ) {
        return BillingControl_InvSync.queryInvSyncCandidateAppointments(dateFilter);
    }""",
    ("processInvSyncAppointments", None): """    public static InvSyncResultWrapper processInvSyncAppointments(
        List<ServiceAppointment> appointments,
        String opportunityOwnerId
    ) {
        return BillingControl_InvSync.processInvSyncAppointments(appointments, opportunityOwnerId);
    }""",
    ("executeInvSyncNow", None): """    @TestVisible
    private static InvSyncResultWrapper executeInvSyncNow(
        BillingControl_DataProvider.BillingDateFilterDTO dateFilter,
        String opportunityOwnerId
    ) {
        return BillingControl_InvSync.executeInvSyncNow(dateFilter, opportunityOwnerId);
    }""",
    ("postReceipt", None): """    @AuraEnabled
    public static PaymentReceiptResultWrapper postReceipt(PostReceiptInputWrapper input) {
        return BillingControl_Receivables.postReceipt(input);
    }""",
    ("getCommissionMetrics", "invoicesFilterContext"): """    public static CommissionMetricsWrapper getCommissionMetrics(
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        return BillingControl_Receivables.getCommissionMetrics(invoicesFilterContext, commissionsFilterContext);
    }""",
    ("getCommissionData", "invoicesFilterContext"): """    public static List<CommissionKpiCategoryWrapper> getCommissionData(
        String subtabType,
        BillingControl_DataProvider.BillingFilterContextDTO invoicesFilterContext,
        BillingControl_DataProvider.BillingFilterContextDTO commissionsFilterContext
    ) {
        return BillingControl_Receivables.getCommissionData(subtabType, invoicesFilterContext, commissionsFilterContext);
    }""",
    ("updateCommissionPaid", None): """    @AuraEnabled
    public static void updateCommissionPaid(List<Id> commissionIds) {
        BillingControl_Receivables.updateCommissionPaid(commissionIds);
    }""",
    ("createCommissionRecords", None): """    @AuraEnabled
    public static CommissionResultWrapper createCommissionRecords(List<CommissionInputWrapper> inputs) {
        return BillingControl_Receivables.createCommissionRecords(inputs);
    }""",
}

# Replace from the bottom so indexes stay valid
jobs = []
for key, body in replacements.items():
    start, end = find_method(*key)
    jobs.append((start, end, body))
jobs.sort(reverse=True)
for start, end, body in jobs:
    lines[start : end + 1] = body.splitlines()

remove_names = [
    ("stampOpportunityLedgerIds", None),
    ("addInvSyncWarning", None),
    ("coalesceInvoiceNumber", None),
    ("queryReceivableOrderSummaries", None),
    ("queryOrderLinkedReceivableCommissionRecords", None),
    ("filterReceivablesCommissionRecords", None),
    ("matchesReceivablesCommissionFilters", None),
    ("summarizeReceivableInvoices", None),
    ("buildOpportunityFromReceivableSummary", None),
    ("buildOpportunityFromOrderLinkedCommission", None),
    ("addOpportunityToCommissionSection", None),
    ("getOpenReceivableInvoice", None),
    ("applyPartialCommissionAccrual", None),
    ("resolveAttributedOpportunitiesForBilling", None),
    ("resolveInvoiceNumberForBilling", None),
    ("buildInvoiceNumber", None),
    ("buildReceivableInvoicesWhereClause", None),
    ("buildCommissionWhereClause", None),
    ("buildCommissionPrefilterWhereClause", None),
    ("getReceivableInvoiceFilterFieldMappings", None),
    ("getCommissionFilterFieldMappings", None),
]

# Refresh after replacements
text = "\n".join(lines)
lines = text.splitlines()
jobs = []
for key in remove_names:
    try:
        start, end = find_method(*key)
    except SystemExit:
        print("skip missing", key)
        continue
    jobs.append((start, end))
jobs.sort(reverse=True)
for start, end in jobs:
    del lines[start : end + 1]
    if start < len(lines) and lines[start].strip() == "":
        del lines[start]

text = "\n".join(lines)
text = re.sub(
    r"\n    private class InvSyncGroup \{.*?\n    \}\n",
    "\n",
    text,
    flags=re.S,
)
text = re.sub(
    r"\n    private class ReceivableOrderSummary \{.*?\n    \}\n",
    "\n",
    text,
    flags=re.S,
)
path.write_text(text.rstrip() + "\n", encoding="utf-8")
print("delegated facade, lines now", len(text.splitlines()))
