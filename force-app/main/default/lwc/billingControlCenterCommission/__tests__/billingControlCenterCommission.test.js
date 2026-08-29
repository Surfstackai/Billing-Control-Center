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
    '@salesforce/apex/BillingControl_Invoicing.updateCommissionPaid',
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
        payments: [],
        ...overrides
    };
}

describe('c-billing-control-center-commission', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders outstanding AR invoices even when This Month is selected', async () => {
        getTabConfig.mockResolvedValue({ kpis: [], sections: [], actions: [] });
        getTabRuntime.mockResolvedValue({
            metrics: {
                outstandingAr: 2500,
                outstandingArCount: 1,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0
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

        const element = createElement('c-billing-control-center-commission', {
            is: BillingControlCenterCommission
        });
        element.dateFilter = uniqueWindow();
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

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
        expect(element.shadowRoot.querySelector('lightning-button-group')).not.toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('Commission close date');
        expect(element.shadowRoot.textContent).not.toContain('Commission Close Date');
    });

    it('groups invoices by salesperson and keeps a flat all-receivables view', async () => {
        getTabConfig.mockResolvedValue({ kpis: [], sections: [], actions: [] });
        getTabRuntime.mockResolvedValue({
            metrics: {
                outstandingAr: 4000,
                outstandingArCount: 2,
                overdue: 0,
                overdueCount: 0,
                partiallyPaid: 0,
                partiallyPaidCount: 0,
                needsAmountCount: 0,
                depositsOutstanding: 0,
                depositsOutstandingCount: 0
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
                            opportunityName: 'Job Two'
                        })
                    ]
                }
            ],
            warnings: []
        });

        const element = createElement('c-billing-control-center-commission', {
            is: BillingControlCenterCommission
        });
        element.dateFilter = uniqueWindow();
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

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
        const oppHeaders = Array.from(
            element.shadowRoot.querySelectorAll('.opp-group-header__name')
        ).map(node => node.textContent.trim());
        expect(oppHeaders).toEqual(expect.arrayContaining(['Job One', 'Job Two']));

        const joshCard = Array.from(element.shadowRoot.querySelectorAll('.salesperson-card')).find(
            card => card.querySelector('.salesperson-card__name')?.textContent === 'Josh Cohen'
        );
        const overdueChip = Array.from(joshCard.querySelectorAll('.status-chip')).find(chip =>
            chip.textContent.includes('Overdue')
        );
        overdueChip.click();
        await Promise.resolve();

        const namesAfter = Array.from(
            element.shadowRoot.querySelectorAll('.salesperson-card__name')
        ).map(node => node.textContent);
        expect(namesAfter).toEqual(expect.arrayContaining(['Josh Cohen', 'Ari Brickman']));
        const joshAfter = Array.from(element.shadowRoot.querySelectorAll('.salesperson-card')).find(
            card => card.querySelector('.salesperson-card__name')?.textContent === 'Josh Cohen'
        );
        expect(joshAfter.textContent).toContain('No invoices in this status for this salesperson.');
        const ariCard = Array.from(element.shadowRoot.querySelectorAll('.salesperson-card')).find(
            card => card.querySelector('.salesperson-card__name')?.textContent === 'Ari Brickman'
        );
        expect(ariCard.textContent).toContain('INV-inv-b');

        element.shadowRoot.querySelector('lightning-button[data-view="all"]').click();
        await Promise.resolve();
        expect(element.shadowRoot.querySelector('[aria-label="All receivables"]')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Salesperson');
        expect(element.shadowRoot.textContent).toContain('Ari Brickman');
    });
});
