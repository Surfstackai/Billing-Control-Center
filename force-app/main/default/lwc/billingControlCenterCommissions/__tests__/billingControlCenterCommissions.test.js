import { createElement } from 'lwc';
import BillingControlCenterCommissions from 'c/billingControlCenterCommissions';
import getTabRuntime from '@salesforce/apex/BillingControl_CommissionLifecycle.getTabRuntime';
import paySelectedCommissions from '@salesforce/apex/BillingControl_CommissionLifecycle.paySelectedCommissions';

jest.mock(
    '@salesforce/apex/BillingControl_CommissionLifecycle.getTabRuntime',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_CommissionLifecycle.paySelectedCommissions',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_CommissionLifecycle.setManualRate',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-billing-control-center-commissions', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders accrued payable and paid sections', async () => {
        getTabRuntime.mockResolvedValue({
            metrics: { accrued: 0, accruedCount: 1, payable: 10, payableCount: 1, paidThisPeriod: 5, paidThisPeriodCount: 1 },
            sections: [
                { categoryKey: 'ACCRUED', categoryLabel: 'Accrued', recordCount: 1, rows: [{ commissionId: 'a1', opportunityName: 'Job A', status: 'Accrued' }] },
                { categoryKey: 'PAYABLE', categoryLabel: 'Payable', recordCount: 1, rows: [{ commissionId: 'a2', opportunityName: 'Job B', status: 'Payable' }] },
                { categoryKey: 'PAID', categoryLabel: 'Paid', recordCount: 1, rows: [{ commissionId: 'a3', opportunityName: 'Job C', status: 'Paid', paidDate: '2026-08-01' }] }
            ],
            warnings: []
        });

        const element = createElement('c-billing-control-center-commissions', { is: BillingControlCenterCommissions });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        expect(getTabRuntime).toHaveBeenCalled();
        const headings = Array.from(element.shadowRoot.querySelectorAll('h2')).map(node => node.textContent);
        expect(headings.join(' ')).toContain('Paid');
        expect(headings.join(' ')).toContain('Accrued');
        const inputLabels = Array.from(element.shadowRoot.querySelectorAll('lightning-input')).map(
            node => node.label
        );
        expect(inputLabels).toContain('Paid date');
    });

    it('pays with explicit paid date not the section filter end', async () => {
        getTabRuntime.mockResolvedValue({
            metrics: { accrued: 0, accruedCount: 0, payable: 10, payableCount: 1, paidThisPeriod: 0, paidThisPeriodCount: 0 },
            sections: [
                { categoryKey: 'ACCRUED', categoryLabel: 'Accrued', recordCount: 0, rows: [] },
                {
                    categoryKey: 'PAYABLE',
                    categoryLabel: 'Payable',
                    recordCount: 1,
                    rows: [{ commissionId: 'a2', opportunityName: 'Job B', status: 'Payable' }]
                },
                { categoryKey: 'PAID', categoryLabel: 'Paid', recordCount: 0, rows: [] }
            ],
            warnings: []
        });
        paySelectedCommissions.mockResolvedValue(undefined);

        const element = createElement('c-billing-control-center-commissions', { is: BillingControlCenterCommissions });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        const checkbox = element.shadowRoot.querySelector('lightning-input[data-id="a2"]');
        checkbox.checked = true;
        checkbox.dispatchEvent(new CustomEvent('change'));
        const paidDateInput = Array.from(element.shadowRoot.querySelectorAll('lightning-input')).find(
            node => node.label === 'Paid date'
        );
        paidDateInput.value = '2026-08-28';
        paidDateInput.dispatchEvent(new CustomEvent('change'));
        const payButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            node => node.label === 'Pay Commission'
        );
        payButton.click();
        await Promise.resolve();
        await Promise.resolve();

        expect(paySelectedCommissions).toHaveBeenCalledWith({
            commissionIds: ['a2'],
            paidDate: '2026-08-28'
        });
    });
});
