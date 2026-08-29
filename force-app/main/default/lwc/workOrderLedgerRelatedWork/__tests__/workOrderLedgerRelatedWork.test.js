import { createElement } from 'lwc';
import WorkOrderLedgerRelatedWork from 'c/workOrderLedgerRelatedWork';
import getWorkOrderLedgerDetail from '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetail';

jest.mock(
    '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

async function flush() {
    await Promise.resolve();
    await Promise.resolve();
}

describe('c-work-order-ledger-related-work', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens the guided Opportunity flow for the Work Order without auto-starting it', async () => {
        getWorkOrderLedgerDetail.mockResolvedValue({
            ledgerId: 'ledger-1',
            workOrderId: 'wo-1',
            accountName: 'Acme',
            workOrderNumber: '0001',
            attentionRequired: true,
            attentionReason: 'Assign completed visits.',
            opportunities: [],
            appointments: [
                {
                    serviceAppointmentId: 'sa-assigned',
                    appointmentNumber: 'SA-A',
                    opportunityId: 'opp-1',
                    opportunityName: 'Job A',
                    status: 'Completed'
                },
                {
                    serviceAppointmentId: 'sa-blank',
                    appointmentNumber: 'SA-BLANK',
                    opportunityId: null,
                    opportunityName: null,
                    status: 'Completed'
                }
            ],
            timeline: []
        });

        const element = createElement('c-work-order-ledger-related-work', {
            is: WorkOrderLedgerRelatedWork
        });
        document.body.appendChild(element);
        element.recordId = 'ledger-1';
        await flush();
        await flush();

        expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();

        const openButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'New visit — choose Opportunity'
        );
        expect(openButton).toBeTruthy();
        openButton.click();
        await flush();

        const flow = element.shadowRoot.querySelector('lightning-flow');
        expect(flow).toBeTruthy();
        expect(flow.flowApiName).toBe('Work_Order_New_Service_Appointment_Guided');
        expect(flow.flowInputVariables).toEqual([
            { name: 'recordId', type: 'String', value: 'wo-1' }
        ]);
        expect(element.shadowRoot.textContent).toContain('Assigned to a job');
        expect(element.shadowRoot.textContent).toContain('Not assigned');
        expect(element.shadowRoot.textContent).toContain('SA-A');
        expect(element.shadowRoot.textContent).toContain('SA-BLANK');
        expect(element.shadowRoot.textContent).toContain('These visits have no Opportunity on the appointment.');
    });
});
