import { createElement } from 'lwc';
import BillingControlCenterInvoiceModal from 'c/billingControlCenterInvoiceModal';

import listCandidateOpportunities from '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities';
import getInvoiceDefaults from '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults';

jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.createInvoice',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flush() {
    return new Promise(resolve => {
        Promise.resolve().then(() => Promise.resolve().then(resolve));
    });
}

async function settle() {
    for (let i = 0; i < 10; i += 1) {
        await flush();
    }
}

function buildAppointments() {
    return [
        {
            serviceAppointmentId: 'sa-1',
            serviceAppointmentNumber: 'SA-1',
            workOrderNumber: '0001',
            workOrderId: 'wo-1',
            opportunityId: 'opp-1',
            opportunityName: 'Job A',
            accountName: 'Acme',
            invoiceableOpportunityAmount: 2500
        }
    ];
}

describe('c-billing-control-center-invoice-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    beforeEach(() => {
        listCandidateOpportunities.mockResolvedValue([
            { opportunityId: 'opp-1', name: 'Job A', quoteNumber: 'AAAQ1', remainingAmount: 2500 }
        ]);
        getInvoiceDefaults.mockResolvedValue({ suggestedAmount: 2500 });
    });

    it('requires a positive amount, offers invoice type, and leaves attribution unchecked', async () => {
        const element = createElement('c-billing-control-center-invoice-modal', {
            is: BillingControlCenterInvoiceModal
        });
        document.body.appendChild(element);
        element.serviceAppointments = buildAppointments();
        await settle();

        const createButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            button => button.label === 'Create Invoice'
        );
        expect(createButton.disabled).toBe(false);

        const typeInput = [...element.shadowRoot.querySelectorAll('lightning-combobox')].find(
            input => input.label === 'Invoice type'
        );
        expect(typeInput).toBeTruthy();
        expect(typeInput.value).toBe('Balance');

        const attribution = [...element.shadowRoot.querySelectorAll('lightning-input')].find(
            input => input.label && input.label.includes("Opportunity to this job")
        );
        expect(attribution).toBeUndefined();
        expect(element.shadowRoot.textContent).toContain('Assigned to a job');
    });

    it('keeps Create available with no service appointments once an Opportunity is chosen', async () => {
        listCandidateOpportunities.mockResolvedValue([]);
        const element = createElement('c-billing-control-center-invoice-modal', {
            is: BillingControlCenterInvoiceModal
        });
        document.body.appendChild(element);
        element.serviceAppointments = [];
        await settle();

        expect(element.shadowRoot.querySelector('lightning-record-picker')).toBeTruthy();
        const createButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            button => button.label === 'Create Invoice'
        );
        expect(createButton.disabled).toBe(true);
    });

    it('includes unattributed visits as evidence instead of skipping them', async () => {
        listCandidateOpportunities.mockResolvedValue([
            { opportunityId: 'opp-a', name: 'Job A', quoteNumber: 'Q1' },
            { opportunityId: 'opp-b', name: 'Job B', quoteNumber: 'Q2' }
        ]);
        const element = createElement('c-billing-control-center-invoice-modal', {
            is: BillingControlCenterInvoiceModal
        });
        document.body.appendChild(element);
        element.serviceAppointments = [
            {
                serviceAppointmentId: 'sa-blank',
                serviceAppointmentNumber: 'SA-BLANK',
                workOrderNumber: '00000389',
                workOrderId: 'wo-389',
                opportunityId: null,
                invoiceableOpportunityAmount: 0,
                ledgerId: 'ledger-389'
            }
        ];
        await settle();

        const evidence = element.shadowRoot.textContent;
        expect(evidence).toContain('SA-BLANK');
        expect(evidence).toContain('Not assigned');
        expect(evidence).toContain('not assigned to an Opportunity');
        const attribution = [...element.shadowRoot.querySelectorAll('lightning-input')].find(
            input => input.label && input.label.includes("Opportunity to this job")
        );
        expect(attribution).toBeTruthy();
        expect(attribution.checked).toBe(false);
        const ledgerButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            button => button.label === 'View Ledger'
        );
        expect(ledgerButton).toBeTruthy();
        const createButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            button => button.label === 'Create Invoice'
        );
        expect(createButton.disabled).toBe(true);
        const opportunityPicker = [...element.shadowRoot.querySelectorAll('lightning-combobox')].find(
            input => input.label === 'Opportunity'
        );
        expect(opportunityPicker).toBeTruthy();
        expect(opportunityPicker.options.length).toBe(2);
    });

    it('loads Opportunity candidates from context when no visits are selected', async () => {
        listCandidateOpportunities.mockImplementation(({ objectApiName, recordId }) => {
            if (objectApiName === 'Opportunity' && recordId === 'opp-context') {
                return Promise.resolve([
                    { opportunityId: 'opp-context', name: 'Context Job', quoteNumber: 'Q-C' }
                ]);
            }
            return Promise.resolve([]);
        });
        getInvoiceDefaults.mockResolvedValue({ suggestedAmount: 2500 });

        const element = createElement('c-billing-control-center-invoice-modal', {
            is: BillingControlCenterInvoiceModal
        });
        document.body.appendChild(element);
        element.contextOpportunityId = 'opp-context';
        element.serviceAppointments = [];
        await settle();

        expect(listCandidateOpportunities).toHaveBeenCalledWith({
            objectApiName: 'Opportunity',
            recordId: 'opp-context'
        });
        const amount = [...element.shadowRoot.querySelectorAll('lightning-input')].find(
            input => input.label === 'Invoice amount'
        );
        expect(amount.value).toBe(2500);
    });
});
