# Caller ledger — keep / delete / unknown

Org: `propump-production` (`00D5Y000001bOdpUAE`), 2026-08-30.

Evidence: Tooling `MetadataComponentDependency` (by Id), retrieved CustomApplication/CustomTab/FlexiPage, `PermissionSetTabSetting`, `CronTrigger` JSON, `AsyncApexJob` JSON, Flow retrieve, repo LWC `@salesforce/apex` imports.

**Rule:** later phases may delete only **DELETE** rows. **UNKNOWN** stays until proven. **KEEP** is live.

Tooling is **class-grain**, not method-grain. Event Monitoring / EventLogFile was **not** queried. Therefore Aura methods without a closed-loop LWC/FlexiPage proof stay **UNKNOWN**, even if repo grep finds no LWC import.

KEEP Apex may still call UNKNOWN methods internally (`DataProvider.loadReceivablesRuntimeData` → `Invoicing.getCommissionMetrics` / `getCommissionData`; DataProvider → `WorkOrderLedger.getKpis` / `getBucketWorkOrders`). Those methods are not DELETE.

No org-only Apex class, Flow, or Visualforce appeared as a dependent of `BillingControl_Invoicing`, `BillingControl_DataProvider`, `BillingControl_MigrationService`, or `BillingControl_InvoiceTypeBackfill`.

---

## KEEP

### App / tabs / pages

- BCC app + home Shell FlexiPage (`Billing_Control_Center_Shell`, `Billing_Control_Center_Shell_Tab`)
- Tab `Billing_Control_Center` (Shell)
- Tabs `Billing_Control` (Invoicing), `Orders`, `Commission` (Receivables) — **DefaultOn** on many profiles; host live worklist LWCs
- FlexiPages `Billing_Control1`, `Orders`, `Commission`, `Work_Order_Ledger_Record_Page`, `Invoice_Record_Page`
- Record actions BCC_Record_Invoice / BCC_Record_Deposit / ledger Quick View

### Apex classes / entry points

- `ConfigService.getTabs` / `getTabConfig`
- `BillingReadiness.getTabRuntime` / `flagAppointmentForReview`
- `ReceivablesWorklist.getTabRuntime` / `setInvoiceAmount`
- `CommissionLifecycle.getTabRuntime` / `paySelectedCommissions` / `setManualRate`
- `InvoiceService.createInvoice` / `getInvoiceDefaults` / `listCandidateOpportunities` / `getVisitInvoiceContext`
- `Receivables.postInvoiceReceipt` (class kept; other Receivables methods UNKNOWN)
- `DataProvider` class — `getOrdersRuntimeData`, `getWorkOrderLedgerDetail` live until Phase 2
- `WorkOrderLedger` class — `assignServiceAppointmentOpportunities` live; `getKpis` / `getBucketWorkOrders` used internally by DataProvider (KEEP class, methods not DELETE)
- `Invoicing` class — `syncExistingInvoiceNumbers` live (Billing LWC). Other Invoicing Aura methods UNKNOWN except the three Phase 1 DELETE methods below
- `InvSync` / `InvSyncBatch` — BatchApex in prod 2026-08-25..29 ([async-apex-job-bcc.json](async-apex-job-bcc.json))
- `CompleteBilling` class — still called from Invoicing wrapper; keep until that wrapper is gone
- `WorkOrderLedgerService` + `AutomationControl` + triggers (do not change this cleanup)
- `WorkOrderLedgerBackfillBatch` / `WorkOrderLedgerResetBatch` — no CronTrigger; keep as ops tools until a later phase proves unused. Not Phase 1.
- Opportunity `Billing_Status__c` **field and writes** (InvoiceService/CompleteBilling + org flows `SA_Sync_Opportunity_Billing_Status`, `Set_Ready_for_Billing_Date_on_Opportunity`)

### LWCs

All Shell children except the DELETE set: Billing, Orders, Commission, Commissions, InvoiceModal, PostReceiptModal, LedgerModal, shared chrome, record actions, related work, quick view.

---

## DELETE (Phase 1)

Closed loop only: Tooling empty or only another DELETE row. No Event Monitoring required because the **component** has zero metadata dependents.

| Surface | Evidence |
|---|---|
| LWC `billingControlCenterCompleteBillingModal` | Tooling dependents: **0**. `isExposed=false`. |
| LWC `billingControlCenterOpportunityTable` | Tooling dependents: **0**. `isExposed=false`. |
| LWC `billingControlCenterOpportunityOrders` | Only FlexiPage `Orders2`. |
| FlexiPage `Orders2` | Retrieved; not a CustomTab target; not in any CustomApplication. |
| `Invoicing.completeServiceAppointmentBilling` | Only imported by CompleteBillingModal (DELETE). |
| `Invoicing.getOpportunityBillingMetrics` | Only imported by OpportunityOrders (DELETE). |
| `Invoicing.getReadyForBillingOpportunities` | Only imported by OpportunityOrders (DELETE). |

After those LWC deletions, also delete tests that exist **only** to cover those three methods / those bundles.

---

## UNKNOWN (do not delete)

| Surface | Why |
|---|---|
| All other `Invoicing` Aura methods (`getAwaitingBillingOpportunities`, `getOutstandingReceivableOpportunities`, `getBillingControlMetrics`, `getBillableOpportunities`, `getBillingReadinessMetrics`, `getServiceAppointmentBillingMetrics*`, `getBillableServiceAppointmentGroups*`, `postReceipt`, `updateCommissionPaid`, `createCommissionRecords`, `getCommissionMetrics`, `getCommissionData`, …) | No Event Monitoring. Tooling is class-grain. KEEP DataProvider still calls `getCommissionMetrics` / `getCommissionData`. |
| `DataProvider.getInvoicingRuntimeData*` / `getReceivablesRuntimeData*` / `getWorkOrderLedgerValidationCounts` | No LWC, but class is KEEP; method-grain unproven. |
| `WorkOrderLedger.getKpis` / `getBucketWorkOrders` Aura | DataProvider still calls them. Not DELETE. |
| `Receivables.markCommissionsPayable` / `getOpenReceivableInvoice` / `payCommissions` | No LWC; class KEEP for `postInvoiceReceipt`. |
| `ConfigService.getConfig` | Tests only; no Event Monitoring. |
| `MigrationService` | Tooling dependents: test class only; no CronTrigger. Still UNKNOWN until Event Monitoring / ops runbook, not Phase 1 UI. |
| `InvoiceTypeBackfill` | Tooling dependents: FoundationTest only. Same. |
| Standalone tabs `Billing_Control` / `Orders` / `Commission` | **DefaultOn** for many profiles. Live alternate entry points. Listed KEEP above for the tabs themselves. |
| FlexiPage `Billing_Control` (vs `Billing_Control1`) | Duplicate Billing host; tab uses `Billing_Control1`. Lightning page URL unproven. |
| FlexiPage `Commission1` | Org-only; hosts live Receivables LWC; no tab. URL unproven. |
| Aura method invocation logs | Event Monitoring not pulled. |
| Bookmarks / custom links / unmanaged buttons | Not in Tooling dependents. |

---

## Phase 1 allowed set (narrow)

Delete **only**:

1. `billingControlCenterCompleteBillingModal` (+ tests if any)
2. `billingControlCenterOpportunityTable` (+ tests if any)
3. `billingControlCenterOpportunityOrders` (+ tests)
4. FlexiPage `Orders2`
5. Invoicing methods `completeServiceAppointmentBilling`, `getOpportunityBillingMetrics`, `getReadyForBillingOpportunities`
6. Tests that exist **only** to cover those deleted methods/bundles

Do **not** in Phase 1: delete DataProvider, delete the Invoicing class, delete other Invoicing Aura methods, delete standalone tabs, delete Commission1 / Billing_Control FlexiPages, collapse facades, merge test suites, touch triggers, delete MigrationService / InvoiceTypeBackfill / ledger batches.
