import { createElement } from 'lwc';
import BillingControlCenterLedgerModal from 'c/billingControlCenterLedgerModal';
import getWorkOrderLedgerDetailForRange from '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetailForRange';

jest.mock(
    '@salesforce/apex/BillingControl_DataProvider.getWorkOrderLedgerDetailForRange',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const LEDGER_ID = 'a1T000000000001';
const AUGUST = { filterKey: 'Custom', startDate: '2026-08-01', endDate: '2026-08-31' };

function emptyDetail() {
    return { ledgerId: LEDGER_ID, opportunities: [], appointments: [], timeline: [] };
}

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        await Promise.resolve();
    }
}

function createModal() {
    return createElement('c-billing-control-center-ledger-modal', {
        is: BillingControlCenterLedgerModal
    });
}

describe('c-billing-control-center-ledger-modal', () => {
    beforeEach(() => {
        getWorkOrderLedgerDetailForRange.mockReset();
        getWorkOrderLedgerDetailForRange.mockResolvedValue(emptyDetail());
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('does not load until it is connected, even if ledgerId is assigned first', async () => {
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        await flush();

        expect(getWorkOrderLedgerDetailForRange).not.toHaveBeenCalled();
    });

    it('sends the window even when ledgerId is assigned before dateFilter, matching template order', async () => {
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        element.dateFilter = AUGUST;
        document.body.appendChild(element);
        await flush();

        expect(getWorkOrderLedgerDetailForRange).toHaveBeenCalledTimes(1);
        expect(getWorkOrderLedgerDetailForRange).toHaveBeenCalledWith({
            ledgerId: LEDGER_ID,
            dateFilter: {
                filterKey: 'Custom',
                startDate: '2026-08-01',
                endDate: '2026-08-31'
            }
        });
    });

    it('reloads when the date window changes after open', async () => {
        const element = createModal();
        element.dateFilter = AUGUST;
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        element.dateFilter = { filterKey: 'Last Year', startDate: null, endDate: null };
        await flush();

        expect(getWorkOrderLedgerDetailForRange).toHaveBeenCalledTimes(2);
        expect(getWorkOrderLedgerDetailForRange.mock.calls[1][0].dateFilter).toEqual({
            filterKey: 'Last Year',
            startDate: null,
            endDate: null
        });
    });

    it('asks for the full diary when connected with no window', async () => {
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        expect(getWorkOrderLedgerDetailForRange).toHaveBeenCalledWith({
            ledgerId: LEDGER_ID,
            dateFilter: null
        });
    });

    it('does not let a slow unwindowed response overwrite a later windowed load', async () => {
        let resolveSlow;
        const slow = new Promise(resolve => {
            resolveSlow = resolve;
        });
        getWorkOrderLedgerDetailForRange.mockReturnValueOnce(slow);

        const element = createModal();
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        getWorkOrderLedgerDetailForRange.mockResolvedValueOnce({
            ...emptyDetail(),
            appointments: [{ appointmentNumber: 'SA-8841' }]
        });
        element.dateFilter = AUGUST;
        await flush();

        resolveSlow({ ...emptyDetail(), appointments: [{ appointmentNumber: 'SA-OLD' }] });
        await flush();

        const numbers = (element.shadowRoot.textContent.match(/SA-\d+/g) || []).join(',');
        expect(numbers).not.toContain('SA-OLD');
    });

    it('surfaces a load failure instead of rendering stale detail', async () => {
        getWorkOrderLedgerDetailForRange.mockRejectedValue({ body: { message: 'no access' } });
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        expect(element.shadowRoot.textContent).toContain('no access');
    });
});
