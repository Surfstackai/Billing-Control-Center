import { createElement } from 'lwc';
import BillingControlCenterBilling from 'c/billingControlCenterBilling';
import getTabRuntime from '@salesforce/apex/BillingControl_BillingReadiness.getTabRuntime';
import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';
import flagAppointmentForReview from '@salesforce/apex/BillingControl_BillingReadiness.flagAppointmentForReview';

jest.mock(
    '@salesforce/apex/BillingControl_BillingReadiness.getTabRuntime',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_BillingReadiness.flagAppointmentForReview',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_ConfigService.getTabConfig',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_Invoicing.syncExistingInvoiceNumbers',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults',
    () => ({ default: jest.fn(() => Promise.resolve({})) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.createInvoice',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/customPermission/Billing_Control_Center_Admin_Access',
    () => ({ default: false }),
    { virtual: true }
);

const BUCKETS = ['DEPOSITS_DUE', 'BALANCES_READY', 'UNDER_INVOICED', 'NEEDS_REVIEW', 'BLOCKED'];
let windowSeq = 0;

function uniqueWindow() {
    windowSeq += 1;
    const day = String(windowSeq).padStart(2, '0');
    return { filterKey: 'Custom', startDate: `2026-03-${day}`, endDate: `2026-03-${day}` };
}

function opportunityRow(opportunityId, extras = {}) {
    return {
        opportunityId,
        opportunityName: extras.opportunityName || `Opportunity ${opportunityId}`,
        accountId: 'acc-1',
        accountName: 'Acme',
        quoteNumber: extras.quoteNumber || 'Q-1',
        amountQuoted: extras.amountQuoted ?? 1000,
        invoicedTotal: extras.invoicedTotal ?? 0,
        remaining: extras.remaining ?? 1000,
        readinessReasons: extras.readinessReasons || ['Balance Ready'],
        invoices: extras.invoices || [],
        workOrders: extras.workOrders || [
            {
                workOrderId: `wo-${opportunityId}`,
                workOrderNumber: `WO-${opportunityId}`,
                ledgerId: extras.ledgerId,
                appointments: extras.appointments || [
                    {
                        serviceAppointmentId: extras.serviceAppointmentId || `sa-${opportunityId}`,
                        serviceAppointmentNumber: extras.serviceAppointmentId || `sa-${opportunityId}`,
                        billed: false
                    }
                ]
            }
        ],
        ...extras
    };
}

function runtimePayload() {
    const balance = opportunityRow('opp-balance', {
        serviceAppointmentId: 'sa-balance',
        amountQuoted: 100,
        remaining: 100
    });
    const under = opportunityRow('opp-under', {
        serviceAppointmentId: 'sa-under',
        amountQuoted: 400,
        invoicedTotal: 200,
        remaining: 200,
        readinessReasons: ['Under-Invoiced']
    });

    return {
        warnings: [],
        metrics: {
            readyToBill: 2,
            depositsDueCount: 0,
            depositsDueAmount: 0,
            balancesReadyCount: 1,
            balancesReadyAmount: 100,
            underInvoicedCount: 1,
            underInvoicedAmount: 200,
            needsReviewCount: 0,
            blockedCount: 0
        },
        groups: [
            {
                categoryKey: 'DEPOSITS_DUE',
                categoryLabel: 'Deposits Due',
                serviceAppointmentCount: 0,
                opportunityRows: []
            },
            {
                categoryKey: 'BALANCES_READY',
                categoryLabel: 'Balances Ready',
                serviceAppointmentCount: 1,
                opportunityRows: [balance]
            },
            {
                categoryKey: 'UNDER_INVOICED',
                categoryLabel: 'Under-Invoiced',
                serviceAppointmentCount: 1,
                opportunityRows: [under]
            },
            {
                categoryKey: 'NEEDS_REVIEW',
                categoryLabel: 'Needs Review',
                serviceAppointmentCount: 0,
                opportunityRows: []
            },
            {
                categoryKey: 'BLOCKED',
                categoryLabel: 'Blocked',
                serviceAppointmentCount: 0,
                opportunityRows: []
            }
        ]
    };
}

function tabConfig() {
    return {
        label: 'Invoicing',
        description: 'Review billable Opportunities and create invoices.',
        kpis: BUCKETS.map(developerKey => ({ developerKey })),
        sections: [{ developerKey: 'READY_TO_INVOICE' }],
        actions: [{ developerKey: 'REFRESH' }, { developerKey: 'COMPLETE_BILLING' }],
        columns: [],
        datasets: [{ developerKey: 'INVOICING_SERVICE_APPOINTMENTS' }]
    };
}

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        await Promise.resolve();
    }
}

function build(dateFilter) {
    const element = createElement('c-billing-control-center-billing', {
        is: BillingControlCenterBilling
    });
    if (dateFilter) {
        element.dateFilter = dateFilter;
    }
    document.body.appendChild(element);
    return element;
}

function accordionSections(element) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-accordion-section'));
}

function checkboxFor(element, bucket) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-input')).find(
        node => node.dataset.bucket === bucket
    );
}

describe('c-billing-control-center-billing KPI lists', () => {
    beforeEach(() => {
        getTabConfig.mockReset();
        getTabConfig.mockResolvedValue(tabConfig());
        getTabRuntime.mockReset();
        getTabRuntime.mockResolvedValue(runtimePayload());
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders one accordion list per readiness KPI with matching counts', async () => {
        const element = build(uniqueWindow());
        await flush();

        const tiles = element.shadowRoot.querySelector('c-billing-control-center-kpi-grid').tiles;
        expect(tiles.map(tile => tile.developerKey)).toEqual(BUCKETS);
        expect(tiles.map(tile => tile.metricText)).toEqual(['0', '1', '1', '0', '0']);

        const sections = accordionSections(element);
        expect(sections.map(section => section.name)).toEqual(BUCKETS);
        expect(sections[1].label).toContain('Balances Ready (1)');
        expect(sections[2].label).toContain('Under-Invoiced (1)');
    });

    it('counts overlapping Opportunities once in the list summary', async () => {
        const element = build(uniqueWindow());
        await flush();

        expect(element.shadowRoot.querySelector('.table-meta').textContent).toContain(
            '2 Opportunities across lists'
        );
    });

    it('selecting a Balances Ready row sets the invoice Opportunity without attaching every visit', async () => {
        const element = build(uniqueWindow());
        await flush();

        const todayCheckbox = checkboxFor(element, 'BALANCES_READY');
        expect(todayCheckbox).toBeTruthy();
        todayCheckbox.checked = true;
        todayCheckbox.dispatchEvent(new CustomEvent('change'));
        await flush();

        element.shadowRoot
            .querySelector('c-billing-control-center-action-bar')
            .dispatchEvent(new CustomEvent('actionclick', { detail: { key: 'completeBilling' } }));
        await flush();

        const modal = element.shadowRoot.querySelector('c-billing-control-center-invoice-modal');
        expect(modal).toBeTruthy();
        expect(modal.serviceAppointments).toEqual([]);
        expect(modal.contextOpportunityId).toBe('opp-balance');
    });

    it('opens the invoice modal with no visits selected so a deposit can be recorded', async () => {
        const element = build(uniqueWindow());
        await flush();

        const todayCheckbox = checkboxFor(element, 'BALANCES_READY');
        todayCheckbox.checked = true;
        todayCheckbox.dispatchEvent(new CustomEvent('change'));
        await flush();

        element.shadowRoot
            .querySelector('c-billing-control-center-action-bar')
            .dispatchEvent(new CustomEvent('actionclick', { detail: { key: 'completeBilling' } }));
        await flush();

        const modal = element.shadowRoot.querySelector('c-billing-control-center-invoice-modal');
        expect(modal).toBeTruthy();
        expect(modal.serviceAppointments).toEqual([]);
        expect(modal.contextOpportunityId).toBe('opp-balance');
    });

    it('does not open Record Invoice without an Opportunity or visit selection', async () => {
        const element = build(uniqueWindow());
        await flush();

        element.shadowRoot
            .querySelector('c-billing-control-center-action-bar')
            .dispatchEvent(new CustomEvent('actionclick', { detail: { key: 'completeBilling' } }));
        await flush();

        expect(element.shadowRoot.querySelector('c-billing-control-center-invoice-modal')).toBeNull();
    });

    it('checking a visit attaches that Service Appointment without selecting the Opportunity row', async () => {
        const element = build(uniqueWindow());
        await flush();

        const evidenceToggle = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find(node => node.label && String(node.label).startsWith('Evidence'));
        expect(evidenceToggle).toBeTruthy();
        evidenceToggle.click();
        await flush();

        const evidenceCheckbox = Array.from(element.shadowRoot.querySelectorAll('lightning-input')).find(
            node => node.dataset.saId === 'sa-balance'
        );
        expect(evidenceCheckbox).toBeTruthy();
        evidenceCheckbox.checked = true;
        evidenceCheckbox.dispatchEvent(new CustomEvent('change'));
        await flush();

        element.shadowRoot
            .querySelector('c-billing-control-center-action-bar')
            .dispatchEvent(new CustomEvent('actionclick', { detail: { key: 'completeBilling' } }));
        await flush();

        const modal = element.shadowRoot.querySelector('c-billing-control-center-invoice-modal');
        expect(modal).toBeTruthy();
        expect(modal.serviceAppointments.map(row => row.serviceAppointmentId)).toEqual(['sa-balance']);
        expect(modal.serviceAppointments[0].opportunityId).toBeNull();
        expect(modal.contextOpportunityId).toBe('opp-balance');
    });

    it('flags a visit for review', async () => {
        flagAppointmentForReview.mockResolvedValue(undefined);
        const element = build(uniqueWindow());
        await flush();

        const evidenceToggle = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find(node => node.label && String(node.label).startsWith('Evidence'));
        evidenceToggle.click();
        await flush();

        const flagButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'Flag for review'
        );
        expect(flagButton).toBeTruthy();
        flagButton.click();
        await flush();
        await flush();

        expect(flagAppointmentForReview).toHaveBeenCalledWith({ serviceAppointmentId: 'sa-balance' });
        const flaggedButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'Flagged for review'
        );
        expect(flaggedButton).toBeTruthy();
        expect(flaggedButton.disabled).toBe(true);
    });
});
