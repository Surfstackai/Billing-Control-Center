# MetadataComponentDependency index

Queries used `RefMetadataComponentId` (Name filter is not allowed on this org). Raw JSON in this folder.

| Target | Id | Non-test dependents |
|---|---|---|
| BillingControl_Invoicing | 01pQj00000Q6HqRIAV | BCC Apex + LWCs Billing, OpportunityOrders, CompleteBillingModal. **No Flow/Aura/VF/org-only Apex.** |
| BillingControl_DataProvider | 01pQj00000QMlXbIAL | BCC Apex + LWCs Orders, workOrderLedgerRelatedWork |
| billingControlCenterCompleteBillingModal | 0RbQj0000003KiBKAU | **none** |
| billingControlCenterOpportunityTable | 0RbQj0000003KiDKAU | **none** |
| billingControlCenterOpportunityOrders | 0RbQj0000003KiCKAU | FlexiPage Orders2 only |
| BillingControl_MigrationService | 01pQj00000QeVKiIAN | MigrationServiceTest only |
| BillingControl_InvoiceTypeBackfill | 01pQj00000QeQWLIA3 | FoundationTest only |
| BillingControl_InvSync | 01pQj00000Qas9PIAR | Invoicing only (facade) |
| BillingControl_Receivables | 01pQj00000Qas9SIAR | Invoicing, tests, PostReceiptModal |

IN-clause on `RefMetadataComponentName` failed (`unknown` field in WHERE). Describe still lists the field; filter by Id.
