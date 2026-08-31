# BCC Phase 0 baseline

Captured **2026-08-30** against `propump-production`.

| Field | Value |
|---|---|
| Alias | `propump-production` |
| Org Id | `00D5Y000001bOdpUAE` |
| Username | `matt@surfstackai-propump.com` |
| Instance | `https://propumpcorp1.my.salesforce.com` |
| Capture date | 2026-08-30 (America/New_York) |

Later phases must diff against these files, not memory.

## Files

| File | What it is |
|---|---|
| [component-inventory.md](component-inventory.md) | Repo + org BCC Apex, LWC, tabs, QAs, triggers |
| [apex-test-results.md](apex-test-results.md) | Targeted BCC Apex run (13 classes) |
| [apex-test-summary.json](apex-test-summary.json) | Machine-readable method counts + coverage |
| [apex-test/](apex-test/) | Raw `sf apex run test` JSON / JUnit / coverage |
| [lwc-jest-results.md](lwc-jest-results.md) | BCC Jest run |
| [lwc-jest-results.json](lwc-jest-results.json) | Raw Jest JSON |
| [lwc-jest-results.txt](lwc-jest-results.txt) | Jest console transcript |
| [metadata-dependencies/](metadata-dependencies/) | Raw Tooling `MetadataComponentDependency` queries |
| [app-tab-flexipage-assignments.md](app-tab-flexipage-assignments.md) | Apps, tabs, FlexiPages, profile tab visibility |
| [permission-set-tab-settings.json](permission-set-tab-settings.json) | Raw tab visibility query |
| [cron-trigger.json](cron-trigger.json) | Production scheduled jobs |
| [async-apex-job-bcc.json](async-apex-job-bcc.json) | Recent `BillingControl_%` AsyncApexJob rows |
| [org-metadata/](org-metadata/) | Retrieved production apps, tabs, FlexiPages, billing-status flows |
| [caller-ledger.md](caller-ledger.md) | **Keep / delete / unknown** — Phase 1+ may not violate this |

## How to re-run

```
sf org display --target-org propump-production
sf apex run test --tests BillingControl_BillingReadinessTest BillingControl_CommissionLifecycleTest BillingControl_ConfigServiceTest BillingControl_DataProviderTest BillingControl_FoundationTest BillingControl_InvSyncRedesignTest BillingControl_InvoiceServiceTest BillingControl_InvoicingTest BillingControl_MigrationServiceTest BillingControl_ReadyToBillKpiTest BillingControl_ReceivablesWorklistTest BillingControl_WorkOrderLedgerTest WorkOrderLedgerServiceTest --target-org propump-production --code-coverage --result-format json --output-dir docs/bcc-cleanup-baseline/apex-test --wait 60
npx sfdx-lwc-jest -- --testPathPattern "billingControlCenter|bccRecord|workOrderLedger"
```

Tooling dependents (filter by Id, not Name):

```
sf data query --use-tooling-api --target-org propump-production -q "SELECT MetadataComponentName, MetadataComponentType, RefMetadataComponentName, RefMetadataComponentType FROM MetadataComponentDependency WHERE RefMetadataComponentId = '<id>'"
```

Production checks in this folder are read-only. No session tokens are stored here.
