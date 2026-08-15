from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "force-app/main/default/classes/BillingControl_Invoicing.cls"
META = """<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <status>Active</status>
</ApexClass>
"""

text = SRC.read_text(encoding="utf-8")
lines = text.splitlines()


def find_method_start(name, match_text=None):
    pattern = re.compile(rf"^\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:public|private|@TestVisible).*?\s{name}\s*\(")
    for index, line in enumerate(lines):
        if not pattern.search(line):
            continue
        window = "\n".join(lines[index : index + 6])
        if match_text and match_text not in window:
            continue
        start = index
        while start > 0 and lines[start - 1].strip().startswith("@"):
            start -= 1
        return start
    raise SystemExit(f"Method not found: {name} {match_text or ''}")


def extract_method(name, match_text=None):
    start = find_method_start(name, match_text)
    brace_count = 0
    started = False
    end = start
    for index in range(start, len(lines)):
        for char in lines[index]:
            if char == "{":
                brace_count += 1
                started = True
            elif char == "}":
                brace_count -= 1
        if started and brace_count == 0:
            end = index
            break
    return "\n".join(lines[start : end + 1])


def rewrite_body(body: str) -> str:
    replacements = [
        ("private static", "public static"),
        ("@TestVisible\n    private static", "public static"),
        ("@TestVisible\n    public static", "public static"),
        ("queryHistoricalInvoiceTotalByOpportunityId(", "BillingControl_Invoicing.queryHistoricalInvoiceTotalByOpportunityId("),
        ("allocateInvoiceTotalAcrossAppointments(", "BillingControl_Invoicing.allocateInvoiceTotalAcrossAppointments("),
        ("getOutstandingReceivableStatusForUpdate()", "BillingControl_Invoicing.getOutstandingReceivableStatusForUpdate()"),
        ("isOutstandingReceivableStatus(", "BillingControl_Invoicing.isOutstandingReceivableStatus("),
        ("buildHandledException(", "BillingControl_Invoicing.buildHandledException("),
        ("queryWorkOrdersById(", "BillingControl_Invoicing.queryWorkOrdersById("),
        ("queryJunctionsByWorkOrderId(", "BillingControl_Invoicing.queryJunctionsByWorkOrderId("),
        ("coalesceDecimal(", "BillingControl_Invoicing.coalesceDecimal("),
        ("extractInteger(", "BillingControl_Invoicing.extractInteger("),
        ("extractDecimal(", "BillingControl_Invoicing.extractDecimal("),
        ("addRuntimeWarning(", "BillingControl_Invoicing.addRuntimeWarning("),
        ("evaluateFilter(", "BillingControl_Invoicing.evaluateFilter("),
        ("evaluateDateFilter(", "BillingControl_Invoicing.evaluateDateFilter("),
        ("normalizeFilterValue(", "BillingControl_Invoicing.normalizeFilterValue("),
        ("containsExcludedInvoicingMarker(", "BillingControl_Invoicing.containsExcludedInvoicingMarker("),
        ("containsExcludedInvoicingMarkerForAccount(", "BillingControl_Invoicing.containsExcludedInvoicingMarkerForAccount("),
    ]
    for old, new in replacements:
        body = body.replace(old, new)
    # Avoid double-prefixing already rewritten calls
    body = body.replace("BillingControl_Invoicing.BillingControl_Invoicing.", "BillingControl_Invoicing.")
    return body


def strip_debug(body: str) -> str:
    cleaned = []
    for line in body.splitlines():
        if "System.debug(LoggingLevel.ERROR" in line:
            continue
        cleaned.append(line)
    return "\n".join(cleaned)


def write_class(name: str, header: str, methods: list) -> None:
    pieces = [header]
    for method in methods:
        if isinstance(method, tuple):
            method_name, match_text = method
        else:
            method_name, match_text = method, None
        body = rewrite_body(extract_method(method_name, match_text))
        if method_name == "createCommissionRecords":
            body = strip_debug(body)
        pieces.append(body)
        pieces.append("")
    pieces.append("}")
    path = ROOT / f"force-app/main/default/classes/{name}.cls"
    path.write_text("\n".join(pieces).rstrip() + "\n", encoding="utf-8")
    path.with_name(f"{name}.cls-meta.xml").write_text(META, encoding="utf-8")
    print(f"Wrote {path}")


receivables_header = """/**
 * Receivables, receipts, and commission commands for Billing Control Center.
 */
public with sharing class BillingControl_Receivables {
    private static final Integer MAX_ROWS_PER_SECTION = 500;
    private static final Integer QUERY_ROW_LIMIT = 501;
    private static final String ROW_LIMIT_WARNING_MESSAGE =
        'Showing first 500 records. Narrow the date filter/search for more specific results.';
    private static final String OUTSTANDING_RECEIVABLE = 'Billed (Outstanding Receivable)';
    private static final String OUTSTANDING_RECEIVABLES = 'Billed (Outstanding Receivables)';
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final String KPI_CATEGORY_REVENUE_UNDER_COLLECTION = 'REVENUE_UNDER_COLLECTION';
    private static final String KPI_CATEGORY_COMMISSION_EARNED = 'COMMISSION_EARNED';
    private static final String KPI_CATEGORY_COMMISSION_PAYABLE = 'COMMISSION_PAYABLE';
    private static final String KPI_LABEL_REVENUE_UNDER_COLLECTION = 'Receivables Outstanding';
    private static final String KPI_LABEL_COMMISSION_EARNED = 'Commission Accrued';
    private static final String KPI_LABEL_COMMISSION_PAYABLE = 'Commission Payable';
    private static final String INVOICE_STATUS_PARTIALLY_PAID = 'Partially Paid';
    private static final String INVOICE_STATUS_PAID = 'Paid';
"""

complete_header = """/**
 * Interactive Complete Billing command. Fail-fast validation stays in this class.
 */
public with sharing class BillingControl_CompleteBilling {
"""

invsync_header = """/**
 * INV-Sync candidate query and best-effort invoice backfill.
 */
public with sharing class BillingControl_InvSync {
    private static final Integer INV_SYNC_MAX_WARNINGS = 25;
    private static final String SERVICE_APPOINTMENT_STATUS_COMPLETED = 'Completed';
    private static final String PAID = 'Paid';
    private static final String PARTIALLY_PAID = 'Partially Paid';
    private static final List<String> EXCLUDED_INVOICING_WORK_ORDER_STATUSES = new List<String>{
        'For Clearance',
        'For Appointment Booking',
        'Appointments Booked',
        'Canceled',
        'Billing Completed',
        'Cannot Complete – Rescheduled'
    };

    private class InvSyncGroup {
        public Id opportunityId;
        public String invoiceNumber;
        public Date invoiceDate;
        public List<ServiceAppointment> appointments;
    }
"""

write_class(
    "BillingControl_Receivables",
    receivables_header,
    [
        "postReceipt",
        ("getCommissionMetrics", "invoicesFilterContext"),
        ("getCommissionData", "invoicesFilterContext"),
        "queryReceivableOrderSummaries",
        "queryOrderLinkedReceivableCommissionRecords",
        "filterReceivablesCommissionRecords",
        "matchesReceivablesCommissionFilters",
        "summarizeReceivableInvoices",
        "buildOpportunityFromReceivableSummary",
        "buildOpportunityFromOrderLinkedCommission",
        "addOpportunityToCommissionSection",
        "stampOpportunityLedgerIds",
        "updateCommissionPaid",
        "createCommissionRecords",
        "getOpenReceivableInvoice",
        "applyPartialCommissionAccrual",
        "buildReceivableInvoicesWhereClause",
        "buildCommissionWhereClause",
        "buildCommissionPrefilterWhereClause",
        "getReceivableInvoiceFilterFieldMappings",
        "getCommissionFilterFieldMappings",
    ],
)

write_class(
    "BillingControl_CompleteBilling",
    complete_header,
    [
        "completeServiceAppointmentBilling",
        "resolveAttributedOpportunitiesForBilling",
        "resolveInvoiceNumberForBilling",
        "buildInvoiceNumber",
    ],
)

write_class(
    "BillingControl_InvSync",
    invsync_header,
    [
        "executeInvSyncNow",
        "queryInvSyncCandidateAppointments",
        "processInvSyncAppointments",
        "addInvSyncWarning",
        "coalesceInvoiceNumber",
    ],
)
