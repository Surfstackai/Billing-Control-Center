# Apex shim deprecation — monitoring & removal record

Legacy classes `BillingControlCenterController` and `BillingControlCenterService` existed as **delegating shims** to `BillingControl_Orders` and `BillingControl_Invoicing` after the Apex rename, so cached Lightning bundles would not throw “No apex action available”.

## Authoritative replacements

| Deprecated (removed from repo) | Use instead |
|--------------------------------|-------------|
| `BillingControlCenterController` | `BillingControl_Orders` |
| `BillingControlCenterService` | `BillingControl_Invoicing` |

## Runtime log tokens (historical)

While shims existed, each method emitted deterministic Apex debug lines for log filtering:

- Prefix: `SHIM_USAGE_BillingControlCenterController` — methods: `.getKpis`, `.getBucketWorkOrders`, `.getOrders`
- Prefix: `SHIM_USAGE_BillingControlCenterService` — methods: `.getReadyForBillingOpportunities`, `.getAwaitingBillingOpportunities`, `.getOutstandingReceivableOpportunities`, `.getOpportunityBillingMetrics`, `.getServiceAppointmentBillingMetrics`, `.getBillableServiceAppointmentGroups`, `.completeServiceAppointmentBilling`, `.getBillingControlMetrics`, `.postReceipt`, `.getCommissionMetrics`, `.getCommissionData`, `.updateCommissionPaid`, `.createCommissionRecords`

**Salesforce Debug Log filter:** search for `SHIM_USAGE_BillingControlCenter` (covers both classes).

## Static reference checks (each release)

From the project root (or CI):

```bash
# Should return no matches in force-app after shim removal
rg "BillingControlCenterController|BillingControlCenterService" force-app --glob "!**/docs/**"
```

In the org, also check **Setup → Apex Classes**, Flows, and **Custom Metadata** for references to the old class names before deleting deployed shims.

## Removal sign-off checklist

- [ ] `rg` (above) is clean in source.
- [ ] LWCs / Aura use `@salesforce/apex/BillingControl_Orders.*` and `BillingControl_Invoicing.*` only.
- [ ] Optional: 1–2 release cycles with **zero** `SHIM_USAGE_BillingControlCenter` lines in sampled user/integration logs (if shims were deployed with markers).
- [ ] Deploy deletion to sandbox → run Apex tests → production validate + deploy.
- [ ] Smoke: Orders, Invoicing, Receivables tabs and Complete Billing / Post Receipt flows.

## Repo change (this codebase)

Shim Apex classes and shim-only tests were **removed** from this repository after confirming no `force-app` references to the legacy class names. Org deployments should omit deleted classes (metadata deploy will remove them from the target org when deployed).

## Regression (Apex)

After shim removal, run the impacted test classes (they exercise `BillingControl_Orders` and `BillingControl_Invoicing`):

```bash
sf apex run test --tests BillingControlCenterControllerTest --tests BillingControlCenterServiceTest --result-format human --synchronous
```

Example successful run (sandbox): **17/17 passed** — `BillingControlCenterControllerTest` + `BillingControlCenterServiceTest`.

**Production deploy:** validate with your manifest, then quick-deploy; smoke-test Orders, Invoicing, Receivables (see checklist above).

### Optional: intermediate “monitoring” deploy

If you need **1–2 release cycles** of Apex log monitoring before deleting shims in the org, deploy shim classes that:

- are annotated `@Deprecated`,
- delegate only to `BillingControl_Orders` / `BillingControl_Invoicing`,
- emit `System.debug(LoggingLevel.INFO, 'SHIM_USAGE_BillingControlCenterController.<method>'` (and the parallel `...Service...` prefix) at the start of each method.

Retrieve the last revision of those classes from git history (`git log --all --full-history -- "**/BillingControlCenterController.cls"`), or recreate from the token list above. After logs show **zero** shim hits and static scans are clean, deploy **deletion** of the shim classes.

---

## Appendix — archived shim reference (pre-removal)

Below is the **last intended** shim implementation (for audit / copy-paste into a monitoring-only branch if needed).

### `BillingControlCenterController` (deprecated; delegates to `BillingControl_Orders`)

```apex
/**
 * DEPRECATED — Legacy Apex name retained for backward compatibility with cached Lightning bindings.
 *
 * Replace with: BillingControl_Orders
 * Deprecation effective: 2026-04-15
 * Removal gate: delete this class only after 1–2 release cycles AND zero runtime usage
 *   (Apex debug lines containing SHIM_USAGE_BillingControlCenterController.*), AND no metadata
 *   references to "BillingControlCenterController" in the org.
 *
 * This class delegates 1:1 to BillingControl_Orders; behavior is unchanged.
 */
@Deprecated
public with sharing class BillingControlCenterController {
    private static final String SHIM_TOKEN = 'SHIM_USAGE_BillingControlCenterController';

    @AuraEnabled(cacheable=true)
    public static BillingControl_Orders.KpiWrapper getKpis() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getKpis');
        return BillingControl_Orders.getKpis();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Orders.BucketSectionWrapper> getBucketWorkOrders() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getBucketWorkOrders');
        return BillingControl_Orders.getBucketWorkOrders();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Orders.OrderRowWrapper> getOrders() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getOrders');
        return BillingControl_Orders.getOrders();
    }
}
```

### `BillingControlCenterService` (deprecated; delegates to `BillingControl_Invoicing`)

```apex
/**
 * DEPRECATED — Legacy Apex name retained for backward compatibility with cached Lightning bindings.
 *
 * Replace with: BillingControl_Invoicing
 * Deprecation effective: 2026-04-15
 * Removal gate: delete this class only after 1–2 release cycles AND zero runtime usage
 *   (Apex debug lines containing SHIM_USAGE_BillingControlCenterService.*), AND no metadata
 *   references to "BillingControlCenterService" in the org.
 *
 * This class delegates 1:1 to BillingControl_Invoicing; behavior is unchanged.
 */
@Deprecated
public with sharing class BillingControlCenterService {
    private static final String SHIM_TOKEN = 'SHIM_USAGE_BillingControlCenterService';

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.OpportunityWrapper> getReadyForBillingOpportunities() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getReadyForBillingOpportunities');
        return BillingControl_Invoicing.getReadyForBillingOpportunities();
    }

    @AuraEnabled
    public static List<BillingControl_Invoicing.OpportunityWrapper> getAwaitingBillingOpportunities() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getAwaitingBillingOpportunities');
        return BillingControl_Invoicing.getAwaitingBillingOpportunities();
    }

    @AuraEnabled
    public static List<BillingControl_Invoicing.OpportunityWrapper> getOutstandingReceivableOpportunities() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getOutstandingReceivableOpportunities');
        return BillingControl_Invoicing.getOutstandingReceivableOpportunities();
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.OpportunityBillingMetricsWrapper getOpportunityBillingMetrics() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getOpportunityBillingMetrics');
        return BillingControl_Invoicing.getOpportunityBillingMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.BillingControlMetricsWrapper getServiceAppointmentBillingMetrics() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getServiceAppointmentBillingMetrics');
        return BillingControl_Invoicing.getServiceAppointmentBillingMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.ServiceAppointmentOpportunityGroupWrapper> getBillableServiceAppointmentGroups() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getBillableServiceAppointmentGroups');
        return BillingControl_Invoicing.getBillableServiceAppointmentGroups();
    }

    @AuraEnabled
    public static BillingControl_Invoicing.CompleteBillingResultWrapper completeServiceAppointmentBilling(List<Id> serviceAppointmentIds) {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.completeServiceAppointmentBilling');
        return BillingControl_Invoicing.completeServiceAppointmentBilling(serviceAppointmentIds);
    }

    @AuraEnabled
    public static BillingControl_Invoicing.BillingControlMetricsWrapper getBillingControlMetrics() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getBillingControlMetrics');
        return BillingControl_Invoicing.getBillingControlMetrics();
    }

    @AuraEnabled
    public static BillingControl_Invoicing.PaymentReceiptResultWrapper postReceipt(BillingControl_Invoicing.PostReceiptInputWrapper input) {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.postReceipt');
        return BillingControl_Invoicing.postReceipt(input);
    }

    @AuraEnabled(cacheable=true)
    public static BillingControl_Invoicing.CommissionMetricsWrapper getCommissionMetrics() {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getCommissionMetrics');
        return BillingControl_Invoicing.getCommissionMetrics();
    }

    @AuraEnabled(cacheable=true)
    public static List<BillingControl_Invoicing.SalespersonWrapper> getCommissionData(String subtabType) {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.getCommissionData');
        return BillingControl_Invoicing.getCommissionData(subtabType);
    }

    @AuraEnabled
    public static void updateCommissionPaid(List<Id> commissionIds) {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.updateCommissionPaid');
        BillingControl_Invoicing.updateCommissionPaid(commissionIds);
    }

    @AuraEnabled
    public static BillingControl_Invoicing.CommissionResultWrapper createCommissionRecords(
        List<BillingControl_Invoicing.CommissionInputWrapper> inputs
    ) {
        System.debug(LoggingLevel.INFO, SHIM_TOKEN + '.createCommissionRecords');
        return BillingControl_Invoicing.createCommissionRecords(inputs);
    }
}
```
