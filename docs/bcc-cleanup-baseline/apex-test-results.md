# Targeted BCC Apex tests — production run

- Org: `propump-production` / `00D5Y000001bOdpUAE`
- Command time: 2026-08-30T20:10:16Z
- Test run id: `707Qj00002flWbS`
- Outcome: **Passed** (0 failing)
- Salesforce summary: **164** `testsRan` / **164** passing (see `apex-test-summary.json` `summary`)
- `tests` array: **161** methods across the 13 named classes (sum of `methodsByClass`). Use **161** as the method inventory; the extra 3 in `testsRan` are unexplained by FullName rows.
- Test-run coverage (classes in this run): **87%**
- Org-wide coverage (whole org, not a BCC metric): 46%

Raw files: [apex-test/](apex-test/) and [apex-test-summary.json](apex-test-summary.json).

## Methods per class

| Class | Pass |
|---|---:|
| BillingControl_InvoicingTest | 47 |
| BillingControl_WorkOrderLedgerTest | 27 |
| BillingControl_DataProviderTest | 25 |
| WorkOrderLedgerServiceTest | 14 |
| BillingControl_BillingReadinessTest | 12 |
| BillingControl_ReceivablesWorklistTest | 9 |
| BillingControl_FoundationTest | 8 |
| BillingControl_InvoiceServiceTest | 7 |
| BillingControl_CommissionLifecycleTest | 3 |
| BillingControl_ConfigServiceTest | 3 |
| BillingControl_InvSyncRedesignTest | 3 |
| BillingControl_MigrationServiceTest | 2 |
| BillingControl_ReadyToBillKpiTest | 1 |

## Coverage for BCC production types (this run)

| Type | Covered % |
|---|---:|
| BillingControl_Attribution | 94 |
| BillingControl_BillingReadiness | 95 |
| BillingControl_BillingTruth | 100 |
| BillingControl_CommissionLifecycle | 84 |
| BillingControl_CompleteBilling | 98 |
| BillingControl_ConfigService | 95 |
| BillingControl_DataProvider | 83 |
| BillingControl_InvoiceMath | 97 |
| BillingControl_InvoiceNumberParser | 99 |
| BillingControl_InvoiceRecordFactory | 79 |
| BillingControl_InvoiceService | 86 |
| BillingControl_InvoiceTypeBackfill | 100 |
| BillingControl_Invoicing | 82 |
| BillingControl_InvSync | 87 |
| BillingControl_InvSyncBatch | 100 |
| BillingControl_MigrationService | 92 |
| BillingControl_OpportunityFinancials | 91 |
| BillingControl_Orders | 89 |
| BillingControl_Receivables | 89 |
| BillingControl_ReceivablesWorklist | 86 |
| BillingControl_WorkOrderLedger | 90 |
| WorkOrderLedger (trigger) | 100 |
| ServiceAppointmentLedger implied via run | — |
| OpportunityWorkOrderLedger (trigger) | 100 |
| WorkOrderLedgerAutomationControl | 83 |
| WorkOrderLedgerBackfillBatch | 97 |
| WorkOrderLedgerResetBatch | 100 |
| WorkOrderLedgerService | 83 |
