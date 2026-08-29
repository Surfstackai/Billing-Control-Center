import { createElement } from 'lwc';
import BccRecordInvoiceAction from 'c/bccRecordInvoiceAction';

import listCandidateOpportunities from '@salesforce/apex/BillingControl_InvoiceService.listCandidateOpportunities';
import getInvoiceDefaults from '@salesforce/apex/BillingControl_InvoiceService.getInvoiceDefaults';
import getVisitInvoiceContext from '@salesforce/apex/BillingControl_InvoiceService.getVisitInvoiceContext';

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
jest.mock(
    '@salesforce/apex/BillingControl_InvoiceService.getVisitInvoiceContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    'lightning/actions',
    () => ({
        CloseActionScreenEvent: class CloseActionScreenEvent extends CustomEvent {
            constructor() {
                super('close');
            }
        }
    }),
    { virtual: true }
);

function flush() {
    return new Promise(resolve => {
        Promise.resolve().then(() => Promise.resolve().then(resolve));
    });
}

async function settle() {
    for (let i = 0; i < 12; i += 1) {
        await flush();
    }
}

describe('c-bcc-record-invoice-action', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('warns when the Service Appointment has no operational Opportunity', async () => {
        listCandidateOpportunities.mockResolvedValue([
            { opportunityId: 'opp-1', name: 'Job A', quoteNumber: 'Q1' }
        ]);
        getInvoiceDefaults.mockResolvedValue({ suggestedAmount: 100 });
        getVisitInvoiceContext.mockResolvedValue({
            serviceAppointmentId: 'sa-1',
            serviceAppointmentNumber: 'SA-1',
            opportunityId: null,
            opportunityName: null,
            workOrderNumber: '0001',
            ledgerId: 'ledger-1',
            unassigned: true
        });

        const element = createElement('c-bcc-record-invoice-action', {
            is: BccRecordInvoiceAction
        });
        document.body.appendChild(element);
        element.objectApiName = 'ServiceAppointment';
        element.recordId = 'sa-1';
        await settle();

        expect(element.shadowRoot.textContent).toContain('Not assigned');
        expect(element.shadowRoot.textContent).toContain('not assigned to an Opportunity');
        const attribution = [...element.shadowRoot.querySelectorAll('lightning-input')].find(
            input => input.label && input.label.includes("Opportunity to this job")
        );
        expect(attribution).toBeTruthy();
        expect(attribution.checked).toBe(false);
        const ledgerButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            button => button.label === 'View Ledger'
        );
        expect(ledgerButton).toBeTruthy();
    });
});
