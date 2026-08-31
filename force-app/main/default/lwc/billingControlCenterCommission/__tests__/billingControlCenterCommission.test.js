import { createElement } from 'lwc';
import BillingControlCenterCommission from 'c/billingControlCenterCommission';
import getTabRuntime from '@salesforce/apex/BillingControl_ReceivablesWorklist.getTabRuntime';
import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';

jest.mock(
    '@salesforce/apex/BillingControl_ReceivablesWorklist.getTabRuntime',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_ReceivablesWorklist.setInvoiceAmount',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_ConfigService.getTabConfig',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/customPermission/Billing_Control_Center_Admin_Access',
    () => ({ default: false }),
    { virtual: true }
);

let windowSeq = 0;
function uniqueWindow() {
    windowSeq += 1;
    const day = String(windowSeq).padStart(2, '0');
    return { filterKey: 'Custom', startDate: `2026-03-${day}`, endDate: `2026-03-${day}` };
}

function invoiceRow(invoiceId, overrides = {}) {
    return {
        invoiceId,
        invoiceNumber: `INV-${invoiceId}`,
        quoteNumber: 'Q-9',
        opportunityId: 'opp-1',
        opportunityName: 'Job One',
        opportunityDescription: 'Pump the outside pit.',
        accountId: 'acc-1',
        accountName: 'Acme',
        ownerId: 'user-josh',
        ownerName: 'Josh Cohen',
        invoiceType: 'Balance',
        status: 'Sent',
        totalAmount: 2500,
        amountPaid: 0,
        balanceDue: 2500,
        canPostReceipt: true,
        needsAmount: false,
        attributedOpportunityNarratives: [
            {
                opportunityId: 'opp-1',
                opportunityName: 'Job One',
                description: 'Pump the outside pit.'
            }
        ],
        payments: [],
        ...overrides
    };
}

async function mountReceivables(runtime) {
    getTabConfig.mockResolvedValue({ kpis: [], sections: [], actions: [] });
    getTabRuntime.mockResolvedValue(runtime);
    const element = createElement('c-billing-control-center-commission', {
        is: BillingControlCenterCommission
    });
    element.dateFilter = uniqueWindow();
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    return element;
}

describe('c-billing-control-center-commission', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders outstanding AR invoices even when This Month is selected', async () => {
        const element = await mountReceivables({
            metrics: {
                outstandingAr: 2500,
                outstandingArCount: 1,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0,
                allReceivables: 2500,
                allReceivablesCount: 1
            },
            invoiceSections: [
                {
                    categoryKey: 'OUTSTANDING_AR',
                    categoryLabel: 'Outstanding AR',
                    isInvoiceSection: true,
                    rows: [invoiceRow('inv-1')]
                }
            ],
            commissionSections: [],
            warnings: []
        });

        expect(getTabRuntime).toHaveBeenCalled();
        const toggle = element.shadowRoot.querySelector('.salesperson-card__toggle');
        if (toggle && toggle.getAttribute('aria-expanded') !== 'true') {
            toggle.click();
            await Promise.resolve();
        }
        const invoiceLink = element.shadowRoot.querySelector('button.slds-text-link');
        expect(invoiceLink).not.toBeNull();
        expect(invoiceLink.textContent).toContain('INV-inv-1');
        expect(element.shadowRoot.querySelector('lightning-accordion')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Josh Cohen');
        expect(element.shadowRoot.querySelector('.view-by__switch')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.opp-group-header__name')).toBeNull();
        expect(element.shadowRoot.querySelector('.invoice-identity__account')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Acme');
        expect(element.shadowRoot.textContent).toContain('Job One');
        expect(element.shadowRoot.textContent).toContain('Q-9');
        expect(element.shadowRoot.textContent).not.toContain('Commission close date');
    });

    it('groups invoices by salesperson without repeating salesperson as a column', async () => {
        const element = await mountReceivables({
            metrics: {
                outstandingAr: 4000,
                outstandingArCount: 2,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0,
                allReceivables: 4000,
                allReceivablesCount: 2
            },
            invoiceSections: [
                {
                    categoryKey: 'OUTSTANDING_AR',
                    categoryLabel: 'Outstanding AR',
                    isInvoiceSection: true,
                    rows: [
                        invoiceRow('inv-a', { ownerId: 'user-josh', ownerName: 'Josh Cohen' }),
                        invoiceRow('inv-b', {
                            invoiceId: 'inv-b',
                            ownerId: 'user-ari',
                            ownerName: 'Ari Brickman',
                            opportunityId: 'opp-2',
                            opportunityName: 'Job Two',
                            opportunityDescription: 'Second job'
                        })
                    ]
                }
            ],
            warnings: []
        });

        Array.from(element.shadowRoot.querySelectorAll('.salesperson-card__toggle')).forEach(button => {
            if (button.getAttribute('aria-expanded') !== 'true') {
                button.click();
            }
        });
        await Promise.resolve();

        const names = Array.from(element.shadowRoot.querySelectorAll('.salesperson-card__name')).map(
            node => node.textContent
        );
        expect(names).toEqual(expect.arrayContaining(['Josh Cohen', 'Ari Brickman']));
        expect(element.shadowRoot.querySelectorAll('.opp-group-header__name')).toHaveLength(0);
        expect(element.shadowRoot.querySelector('.status-chip')).toBeNull();
        const joshCard = Array.from(element.shadowRoot.querySelectorAll('.salesperson-card')).find(
            card => card.querySelector('.salesperson-card__name')?.textContent === 'Josh Cohen'
        );
        expect(joshCard.querySelector('.invoice-identity__account')).not.toBeNull();
        expect(joshCard.textContent).toContain('Acme');
        expect(joshCard.textContent).toContain('Q-9');
        const joshHeaders = Array.from(joshCard.querySelectorAll('.grouped-diary-table__header-label')).map(node =>
            node.textContent.trim()
        );
        expect(joshHeaders).toContain('Account');
        expect(joshHeaders).not.toContain('Quote #');
        expect(joshHeaders).not.toContain('Opportunity');
        expect(joshHeaders).not.toContain('Salesperson');
        expect(joshCard.querySelectorAll('.bcc-column-resize-handle').length).toBeGreaterThan(8);

        element.shadowRoot.querySelector('button[data-view="invoice"]').click();
        await Promise.resolve();
        expect(element.shadowRoot.querySelector('[aria-label="Receivables by invoice"]')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Salesperson');
        expect(element.shadowRoot.textContent).toContain('Ari Brickman');
        expect(element.shadowRoot.querySelector('.salesperson-card')).toBeNull();
    });

    it('counts an invoice once when Apex status sections overlap', async () => {
        const shared = invoiceRow('inv-dup', { balanceDue: 541, amountPaid: 2500, totalAmount: 3041 });
        const element = await mountReceivables({
            metrics: {
                outstandingAr: 541,
                outstandingArCount: 1,
                overdue: 541,
                overdueCount: 1,
                partiallyPaid: 541,
                partiallyPaidCount: 1,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0,
                allReceivables: 541,
                allReceivablesCount: 1
            },
            invoiceSections: [
                {
                    categoryKey: 'OUTSTANDING_AR',
                    categoryLabel: 'Outstanding AR',
                    isInvoiceSection: true,
                    rows: [shared]
                },
                {
                    categoryKey: 'OVERDUE',
                    categoryLabel: 'Overdue',
                    isInvoiceSection: true,
                    rows: [shared]
                },
                {
                    categoryKey: 'PARTIALLY_PAID',
                    categoryLabel: 'Partially Paid',
                    isInvoiceSection: true,
                    rows: [shared]
                }
            ],
            warnings: []
        });

        const card = element.shadowRoot.querySelector('.salesperson-card');
        const metricValues = Array.from(
            card.querySelectorAll('.salesperson-card__metrics lightning-formatted-number')
        ).map(node => Number(node.value));
        expect(metricValues[2]).toBe(1);
        const invoiceLinks = Array.from(card.querySelectorAll('button.slds-text-link')).filter(node =>
            node.textContent.includes('INV-inv-dup')
        );
        expect(invoiceLinks).toHaveLength(1);
    });

    it('shows worklist invoices on All even when they are absent from status buckets', async () => {
        const openInvoice = invoiceRow('inv-open');
        const paidInvoice = invoiceRow('inv-paid', {
            status: 'Paid',
            amountPaid: 2500,
            balanceDue: 0,
            canPostReceipt: false
        });
        const element = await mountReceivables({
            metrics: {
                outstandingAr: 2500,
                outstandingArCount: 1,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0,
                allReceivables: 2500,
                allReceivablesCount: 2
            },
            invoices: [openInvoice, paidInvoice],
            invoiceSections: [
                {
                    categoryKey: 'OUTSTANDING_AR',
                    categoryLabel: 'Outstanding AR',
                    isInvoiceSection: true,
                    rows: [openInvoice]
                }
            ],
            warnings: []
        });

        expect(element.shadowRoot.textContent).toContain('INV-inv-open');
        expect(element.shadowRoot.textContent).not.toContain('INV-inv-paid');
        const outstandingCount = Array.from(
            element.shadowRoot.querySelectorAll('.salesperson-card__metrics lightning-formatted-number')
        ).map(node => Number(node.value));
        expect(outstandingCount[2]).toBe(1);

        const allTab = Array.from(element.shadowRoot.querySelectorAll('.ar-summary-strip__item')).find(
            button => button.getAttribute('data-status') === 'ALL_RECEIVABLES'
        );
        allTab.click();
        await Promise.resolve();
        expect(element.shadowRoot.textContent).toContain('INV-inv-paid');
        expect(element.shadowRoot.textContent).toContain('INV-inv-open');
        const allCount = Array.from(
            element.shadowRoot.querySelectorAll('.salesperson-card__metrics lightning-formatted-number')
        ).map(node => Number(node.value));
        expect(allCount[2]).toBe(2);
    });

    it('expands an invoice for opportunity description then payments', async () => {
        const element = await mountReceivables({
            metrics: {
                outstandingAr: 2500,
                outstandingArCount: 1,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0,
                allReceivables: 2500,
                allReceivablesCount: 1
            },
            invoiceSections: [
                {
                    categoryKey: 'OUTSTANDING_AR',
                    categoryLabel: 'Outstanding AR',
                    isInvoiceSection: true,
                    rows: [
                        invoiceRow('inv-1', {
                            payments: [
                                {
                                    paymentId: 'pay-1',
                                    paymentDate: '2026-03-01',
                                    amountReceived: 400,
                                    paymentMethod: 'Check',
                                    referenceNumber: 'CHK-9'
                                }
                            ]
                        })
                    ]
                }
            ],
            warnings: []
        });

        const expand = element.shadowRoot.querySelector('lightning-button-icon[data-key="inv-inv-1"]');
        expand.click();
        await Promise.resolve();
        expect(element.shadowRoot.textContent).toContain('Pump the outside pit.');
        expect(element.shadowRoot.textContent).toContain('CHK-9');
        expect(element.shadowRoot.textContent).toContain('Payment Date');
    });
});
