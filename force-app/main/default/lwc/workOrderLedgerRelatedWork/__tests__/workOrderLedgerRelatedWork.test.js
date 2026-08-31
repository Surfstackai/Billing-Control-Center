import { createElement } from 'lwc';
import WorkOrderLedgerRelatedWork from 'c/workOrderLedgerRelatedWork';
import getWorkOrderLedgerDetail from '@salesforce/apex/BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail';
import assignServiceAppointmentOpportunities from '@salesforce/apex/BillingControl_WorkOrderLedger.assignServiceAppointmentOpportunities';

jest.mock(
    '@salesforce/apex/BillingControl_WorkOrderLedger.getWorkOrderLedgerDetail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/BillingControl_WorkOrderLedger.assignServiceAppointmentOpportunities',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

async function flush() {
    await Promise.resolve();
    await Promise.resolve();
}

function newVisitButtons(root) {
    return Array.from(root.querySelectorAll('lightning-button')).filter(
        node => node.label === 'New visit — choose Opportunity'
    );
}

function baseDetail(overrides = {}) {
    return {
        ledgerId: 'ledger-1',
        workOrderId: 'wo-1',
        accountName: 'Acme',
        workOrderNumber: '0001',
        reconciliationStatus: 'Needs Review',
        attentionRequired: true,
        attentionReason: 'No Opportunity linked to this Work Order.',
        opportunities: [],
        eligibleOpportunities: [],
        appointments: [],
        timeline: [],
        ...overrides
    };
}

describe('c-work-order-ledger-related-work', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('does not launch a new-visit flow and overlays assignment copy for blank visits', async () => {
        getWorkOrderLedgerDetail.mockResolvedValue(
            baseDetail({
                attentionReason: 'This Work Order has more than one Opportunity.',
                opportunities: [
                    { opportunityId: 'opp-1', name: 'Job A' },
                    { opportunityId: 'opp-2', name: 'Job B' }
                ],
                eligibleOpportunities: [
                    { opportunityId: 'opp-1', name: 'Job A' },
                    { opportunityId: 'opp-2', name: 'Job B' }
                ],
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
                ]
            })
        );

        const element = createElement('c-work-order-ledger-related-work', {
            is: WorkOrderLedgerRelatedWork
        });
        document.body.appendChild(element);
        element.recordId = 'ledger-1';
        await flush();
        await flush();

        expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();
        expect(newVisitButtons(element.shadowRoot)).toHaveLength(0);

        const alert = element.shadowRoot.querySelector('.ledger-attention');
        expect(alert).not.toBeNull();
        expect(alert.textContent).toContain(
            '1 service appointment needs Opportunity assignment. Select the correct Opportunity for each visit below.'
        );
        expect(alert.textContent).not.toContain('This Work Order has more than one Opportunity.');
        expect(alert.textContent).not.toContain('No Opportunity linked');

        const saLink = Array.from(element.shadowRoot.querySelectorAll('a')).find(
            node => node.textContent === 'SA-BLANK'
        );
        expect(saLink).toBeTruthy();
        expect(saLink.getAttribute('target')).toBe('_blank');
        expect(saLink.getAttribute('rel')).toContain('noopener');
        expect(saLink.getAttribute('rel')).toContain('noreferrer');
        expect(saLink.getAttribute('href')).toBe('/lightning/r/ServiceAppointment/sa-blank/view');

        const assignedLink = Array.from(element.shadowRoot.querySelectorAll('a')).find(
            node => node.textContent === 'Job A'
        );
        expect(assignedLink).toBeTruthy();
        expect(assignedLink.getAttribute('href')).toBe('/lightning/r/Opportunity/opp-1/view');

        expect(element.shadowRoot.querySelector('lightning-combobox')).not.toBeNull();
        const saveButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'Save Assignments'
        );
        expect(saveButton).toBeTruthy();
        expect(saveButton.disabled).toBe(true);
        expect(element.shadowRoot.textContent).toContain('1 visit need an Opportunity.');
    });

    it('saves selected Opportunities and reloads so the visit moves to assigned', async () => {
        getWorkOrderLedgerDetail
            .mockResolvedValueOnce(
                baseDetail({
                    opportunities: [
                        { opportunityId: 'opp-1', name: 'Job A' },
                        { opportunityId: 'opp-2', name: 'Job B' }
                    ],
                    eligibleOpportunities: [
                        { opportunityId: 'opp-1', name: 'Job A' },
                        { opportunityId: 'opp-2', name: 'Job B' }
                    ],
                    appointments: [
                        {
                            serviceAppointmentId: 'sa-blank',
                            appointmentNumber: 'SA-BLANK',
                            opportunityId: null,
                            status: 'None'
                        }
                    ]
                })
            )
            .mockResolvedValueOnce(
                baseDetail({
                    attentionRequired: false,
                    opportunities: [
                        { opportunityId: 'opp-1', name: 'Job A' },
                        { opportunityId: 'opp-2', name: 'Job B' }
                    ],
                    eligibleOpportunities: [
                        { opportunityId: 'opp-1', name: 'Job A' },
                        { opportunityId: 'opp-2', name: 'Job B' }
                    ],
                    appointments: [
                        {
                            serviceAppointmentId: 'sa-blank',
                            appointmentNumber: 'SA-BLANK',
                            opportunityId: 'opp-2',
                            opportunityName: 'Job B',
                            status: 'None'
                        }
                    ]
                })
            );
        assignServiceAppointmentOpportunities.mockResolvedValue({
            savedIds: ['sa-blank'],
            conflicts: [],
            errors: []
        });

        const element = createElement('c-work-order-ledger-related-work', {
            is: WorkOrderLedgerRelatedWork
        });
        document.body.appendChild(element);
        element.recordId = 'ledger-1';
        await flush();
        await flush();

        const picker = element.shadowRoot.querySelector('lightning-combobox');
        picker.dataset.saId = 'sa-blank';
        picker.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'opp-2' }, bubbles: true })
        );
        await flush();

        const saveButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'Save Assignments'
        );
        expect(saveButton.disabled).toBe(false);
        saveButton.click();
        await flush();
        await flush();
        await flush();

        expect(assignServiceAppointmentOpportunities).toHaveBeenCalledWith({
            workOrderId: 'wo-1',
            assignments: [{ serviceAppointmentId: 'sa-blank', opportunityId: 'opp-2' }]
        });
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Job B');
        expect(element.shadowRoot.textContent).toContain('Assigned to a job');
    });

    it('does not show a picker or no-opportunity copy when a junction exists but is not eligible', async () => {
        getWorkOrderLedgerDetail.mockResolvedValue(
            baseDetail({
                attentionRequired: true,
                attentionReason:
                    '2 service appointments need Opportunity assignment. Select the correct Opportunity for each visit below.',
                opportunities: [{ opportunityId: 'opp-open', name: 'Open Job', stageName: 'Prospecting' }],
                eligibleOpportunities: [],
                appointments: [
                    {
                        serviceAppointmentId: 'sa-blank',
                        appointmentNumber: 'SA-BLANK',
                        opportunityId: null,
                        status: 'None'
                    }
                ]
            })
        );

        const element = createElement('c-work-order-ledger-related-work', {
            is: WorkOrderLedgerRelatedWork
        });
        document.body.appendChild(element);
        element.recordId = 'ledger-1';
        await flush();
        await flush();

        expect(element.shadowRoot.querySelector('.ledger-attention')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('No Opportunity linked');
        expect(element.shadowRoot.textContent).not.toContain('Select the correct Opportunity for each visit below.');
        expect(newVisitButtons(element.shadowRoot)).toHaveLength(0);
    });

    it('keeps a blank Opportunity cell when only one eligible Opportunity exists', async () => {
        getWorkOrderLedgerDetail.mockResolvedValue(
            baseDetail({
                attentionRequired: false,
                opportunities: [{ opportunityId: 'opp-1', name: 'Job A' }],
                eligibleOpportunities: [{ opportunityId: 'opp-1', name: 'Job A' }],
                appointments: [
                    {
                        serviceAppointmentId: 'sa-blank',
                        appointmentNumber: 'SA-BLANK',
                        opportunityId: null,
                        status: 'Completed'
                    }
                ]
            })
        );

        const element = createElement('c-work-order-ledger-related-work', {
            is: WorkOrderLedgerRelatedWork
        });
        document.body.appendChild(element);
        element.recordId = 'ledger-1';
        await flush();
        await flush();

        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        expect(
            Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
                node => node.label === 'Save Assignments'
            )
        ).toBeUndefined();
    });
});
