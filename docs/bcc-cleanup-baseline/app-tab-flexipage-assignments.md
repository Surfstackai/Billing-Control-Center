# App / tab / FlexiPage assignments

Org: `00D5Y000001bOdpUAE`. Retrieved apps/tabs/pages live under [org-metadata/](org-metadata/).

## Lightning apps that include BCC nav tabs

Only **Billing Control Center** (`Billing_Control_Center`) includes `Billing_Control_Center` as a nav tab. Home override is FlexiPage `Billing_Control_Center_Shell`.

No other retrieved CustomApplication includes `Billing_Control`, `Orders`, `Commission`, or `Billing_Control_Center`. That includes Propump - Accounting, Propump Management, Sales, Service Console, Executive App, and Billing Control Center Config (config objects only).

App launcher entries: `Billing_Control_Center`, `Billing_Control_Center_Config`.

## Custom tabs (exist in org)

| API name | Label | Points at |
|---|---|---|
| `Billing_Control_Center` | Billing Control Center | LWC `billingControlCenterShell` |
| `Billing_Control` | Invoicing | FlexiPage `Billing_Control1` (`billingControlCenterBilling`) |
| `Orders` | Orders | FlexiPage `Orders` (`billingControlCenterOrders`) |
| `Commission` | Receivables | FlexiPage `Commission` (`billingControlCenterCommission`) |
| `Work_Order_Ledger__c` | Work Order Ledgers | object tab |

## Profile / permission-set tab visibility

`PermissionSetTabSetting` query saved as [permission-set-tab-settings.json](permission-set-tab-settings.json) (71 rows).

- `Billing_Control`, `Orders`, `Commission` are **DefaultOn** for many **profiles** (owned-by-profile permission sets). They are reachable from App Launcher / All Tabs even though they are not in the BCC app nav.
- `Billing_Control_Center` is DefaultOn for permission sets `Billing_Control_Center_Admin` and `Billing_Control_Center_User`.

**Do not delete** the standalone Invoicing / Orders / Receivables tabs in Phase 1. They host live components and profiles still expose them.

## FlexiPages

| DeveloperName | Type | Hosts | In an app/tab? |
|---|---|---|---|
| Billing_Control_Center_Shell | HomePage | Shell | BCC app home — **keep** |
| Billing_Control_Center_Shell_Tab | AppPage | Shell | **keep** |
| Billing_Control1 | AppPage | Billing | tab `Billing_Control` — **keep** |
| Billing_Control | AppPage | Billing (duplicate of live tab host) | no tab in retrieved CustomTab (tab uses Billing_Control1) — **UNKNOWN** |
| Orders | AppPage | Orders | tab `Orders` — **keep** |
| Orders2 | AppPage | OpportunityOrders | **no tab, no app** — delete with that LWC |
| Commission | AppPage | Receivables LWC | tab `Commission` — **keep** |
| Commission1 | AppPage | same Receivables LWC | org-only, **no tab** — **UNKNOWN** (Lightning URL unproven) |
| Work_Order_Ledger_Record_Page | RecordPage | related work | **keep** |
| Invoice_Record_Page | RecordPage | Invoice__c | **keep** |

## Scheduled jobs

Raw: [cron-trigger.json](cron-trigger.json) — 8 jobs, none named BillingControl / InvSync / Migration / Ledger backfill.

## Async Apex (recent)

Raw: [async-apex-job-bcc.json](async-apex-job-bcc.json). `BillingControl_InvSyncBatch` ran as **BatchApex** on 2026-08-25, 08-26, and 08-29 (completed). Not scheduled; invoked from the live Billing-tab sync path. **Keep** InvSync / InvSyncBatch.

No `MigrationService` or `InvoiceTypeBackfill` async jobs in the last sampled rows.

## Flows touching billing status (do not call BCC Apex)

Retrieved under `org-metadata/flows/`. None reference `BillingControl_*`.

- `SA_Sync_Opportunity_Billing_Status` — active after-save
- `Set_Ready_for_Billing_Date_on_Opportunity` — active before-save
- `Work_Order_Validate_Billing_Opportunity_For_Scheduling` — inactive

These are a reason to **keep Opportunity.Billing_Status__c writes**, not the legacy Invoicing **read** APIs.

## List views

Opportunity list view `All Opptys and Billing status = blank` (`All_Opptys_and_Billing_status_blank`) exists. Field usage; not an Apex caller.
