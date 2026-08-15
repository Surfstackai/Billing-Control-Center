from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "force-app/main/default/classes"

wrappers = [
    "PaymentReceiptResultWrapper",
    "PostReceiptInputWrapper",
    "CommissionMetricsWrapper",
    "CommissionKpiCategoryWrapper",
    "SalespersonWrapper",
    "OpportunityWrapper",
    "CommissionResultWrapper",
    "CommissionInputWrapper",
    "CompleteBillingResultWrapper",
    "InvoiceGroupResultWrapper",
    "InvSyncResultWrapper",
]


def prefix_wrappers(text):
    for name in wrappers:
        text = re.sub(
            rf"(?<!BillingControl_Invoicing\.)\b{name}\b",
            f"BillingControl_Invoicing.{name}",
            text,
        )
    return re.sub(r"@AuraEnabled(?:\([^)]*\))?\s*\n\s*", "", text)


inv_lines = (root / "BillingControl_Invoicing.cls").read_text(encoding="utf-8").splitlines()
start = None
for index, line in enumerate(inv_lines):
    window = "\n".join(inv_lines[index : index + 4])
    if "public static CommissionMetricsWrapper getCommissionMetrics(" in line and "invoicesFilterContext" in window:
        start = index
        break
if start is None:
    raise SystemExit("Could not find getCommissionMetrics implementation")

brace = 0
started = False
end = start
for index in range(start, len(inv_lines)):
    for char in inv_lines[index]:
        if char == "{":
            brace += 1
            started = True
        elif char == "}":
            brace -= 1
    if started and brace == 0:
        end = index
        break

metrics_impl = "\n".join(inv_lines[start : end + 1])
metrics_impl = metrics_impl.replace("extractInteger(", "BillingControl_Invoicing.extractInteger(")
metrics_impl = metrics_impl.replace("extractDecimal(", "BillingControl_Invoicing.extractDecimal(")
metrics_impl = prefix_wrappers(metrics_impl)

recv_path = root / "BillingControl_Receivables.cls"
recv = prefix_wrappers(recv_path.read_text(encoding="utf-8"))
recv, count = re.subn(
    r"    public static BillingControl_Invoicing.CommissionMetricsWrapper getCommissionMetrics\(\) \{\n        return getCommissionMetrics\(null, null\);\n    \}\n",
    metrics_impl + "\n\n",
    recv,
    count=1,
)
if count != 1:
    raise SystemExit("Failed to replace getCommissionMetrics stub: %s" % count)

if "private class ReceivableOrderSummary" not in recv:
    recv = recv.rstrip() + """

    private class ReceivableOrderSummary {
        public Id opportunityId;
        public String opportunityName;
        public String accountName;
        public Date closeDate;
        public Id ownerId;
        public String ownerName;
        public String billingStatus;
        public Decimal amount;
        public Decimal amountPaid;
        public Decimal balanceDue;
    }
}
"""
recv_path.write_text(recv if recv.endswith("\n") else recv + "\n", encoding="utf-8")

complete_path = root / "BillingControl_CompleteBilling.cls"
complete = prefix_wrappers(complete_path.read_text(encoding="utf-8"))
if "SERVICE_APPOINTMENT_STATUS_COMPLETED" not in complete:
    complete = complete.replace(
        "public with sharing class BillingControl_CompleteBilling {\n",
        "public with sharing class BillingControl_CompleteBilling {\n"
        "    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';\n",
    )
complete_path.write_text(complete, encoding="utf-8")

invsync_path = root / "BillingControl_InvSync.cls"
invsync_path.write_text(prefix_wrappers(invsync_path.read_text(encoding="utf-8")), encoding="utf-8")
print("fixed domain classes")
