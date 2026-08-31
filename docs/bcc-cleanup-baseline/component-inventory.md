# BCC component inventory

Source: repo `force-app/main/default` plus Tooling queries against `00D5Y000001bOdpUAE` on 2026-08-30. Org class list matched the repo (38 Apex classes: 25 production + 13 tests). Org LWC list matched the repo except `workOrderOpportunityLookup` and `serviceAppointmentNewRedirect` were not in the LIKE filter; they exist in the repo for the guided SA flow.

## Production Apex (org Status = Active)

Facades: `BillingControl_Invoicing`, `BillingControl_DataProvider`, `BillingControl_InvSyncBatch`, `BillingControl_Orders` (DTO shell).

Domain: `BillingControl_BillingReadiness`, `BillingControl_InvoiceService`, `BillingControl_ReceivablesWorklist`, `BillingControl_Receivables`, `BillingControl_CommissionLifecycle`, `BillingControl_WorkOrderLedger`, `BillingControl_CompleteBilling`, `BillingControl_InvSync`, `BillingControl_ConfigService`, `WorkOrderLedgerService`.

Kernel: `BillingControl_Attribution`, `BillingControl_BillingTruth`, `BillingControl_InvoiceMath`, `BillingControl_OpportunityFinancials`, `BillingControl_InvoiceRecordFactory`, `BillingControl_InvoiceNumberParser`.

Ops: `BillingControl_MigrationService`, `BillingControl_InvoiceTypeBackfill`, `WorkOrderLedgerBackfillBatch`, `WorkOrderLedgerResetBatch`, `WorkOrderLedgerAutomationControl`.

## Live LWC Aura imports (repo `.js`, not tests)

| LWC | Apex |
|---|---|
| `billingControlCenterShell` | `ConfigService.getTabs` |
| `billingControlCenterOrders` | `ConfigService.getTabConfig`, `DataProvider.getOrdersRuntimeData` |
| `billingControlCenterBilling` | `ConfigService.getTabConfig`, `BillingReadiness.getTabRuntime`, `BillingReadiness.flagAppointmentForReview`, `Invoicing.syncExistingInvoiceNumbers` |
| `billingControlCenterCommission` | `ConfigService.getTabConfig`, `ReceivablesWorklist.getTabRuntime`, `ReceivablesWorklist.setInvoiceAmount` |
| `billingControlCenterCommissions` | `CommissionLifecycle.getTabRuntime`, `paySelectedCommissions`, `setManualRate` |
| `billingControlCenterOpportunityOrders` | `Invoicing.getOpportunityBillingMetrics`, `Invoicing.getReadyForBillingOpportunities` |
| `billingControlCenterInvoiceModal` | `InvoiceService.createInvoice`, `getInvoiceDefaults`, `listCandidateOpportunities` |
| `billingControlCenterCompleteBillingModal` | `Invoicing.completeServiceAppointmentBilling` |
| `billingControlCenterPostReceiptModal` | `Receivables.postInvoiceReceipt` |
| `bccRecordInvoiceAction` | InvoiceService create/defaults/candidates + `getVisitInvoiceContext` |
| `bccRecordDepositAction` | InvoiceService create/defaults/candidates |
| `workOrderLedgerRelatedWork` | `DataProvider.getWorkOrderLedgerDetail`, `WorkOrderLedger.assignServiceAppointmentOpportunities` |
| `workOrderOpportunityLookup` | `LookupSearchController.searchOpportunities` (not BCC Apex) |

## Exposed vs child LWCs (org `IsExposed`)

Exposed: Shell, Billing, Orders, Commission, Commissions, OpportunityOrders, bccRecordInvoiceAction, bccRecordDepositAction, workOrderLedgerQuickView, workOrderLedgerRelatedWork.

Not exposed: CompleteBillingModal, OpportunityTable, InvoiceModal, PostReceiptModal, LedgerModal, DateFilter, KpiGrid, ActionBar, Diagnostics, AccountGroup, ColumnResize, Styles.

## Quick actions (repo)

- `Opportunity.BCC_Record_Invoice`, `Opportunity.BCC_Record_Deposit`
- `WorkOrder.BCC_Record_Invoice`, `WorkOrder.BCC_Record_Deposit`
- `ServiceAppointment.BCC_Record_Invoice`
- `Work_Order_Ledger__c.Quick_View`

## Triggers (do not touch this cleanup)

- `WorkOrderLedger`
- `ServiceAppointmentLedger`
- `OpportunityWorkOrderLedger`

## Org-only FlexiPage not in the repo

- `Commission1` — AppPage hosting `billingControlCenterCommission` (same live Receivables LWC as `Commission`). No CustomTab points at it.
