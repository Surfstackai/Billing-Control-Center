# BCC LWC Jest — local run

Captured 2026-08-30 from repo working tree (not org).

```
npx sfdx-lwc-jest -- --testPathPattern "billingControlCenter|bccRecord|workOrderLedger"
```

- Test suites: **9 passed**, 9 total
- Tests: **47 passed**, 47 total
- Snapshots: 0
- Time: ~16.6 s

Suites:

- bccRecordInvoiceAction
- billingControlCenterInvoiceModal
- billingControlCenterLedgerModal
- billingControlCenterDateFilter
- workOrderLedgerRelatedWork
- billingControlCenterCommissions
- billingControlCenterCommission
- billingControlCenterOrders (console.warn: ORDERS config missing in test doubles — expected)
- billingControlCenterBilling

Raw: [lwc-jest-results.json](lwc-jest-results.json), [lwc-jest-results.txt](lwc-jest-results.txt).
