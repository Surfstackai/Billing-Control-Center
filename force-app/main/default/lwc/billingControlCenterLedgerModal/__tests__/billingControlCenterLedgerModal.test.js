import { createElement } from 'lwc';
import BillingControlCenterLedgerModal from 'c/billingControlCenterLedgerModal';

const LEDGER_ID = 'a1T000000000001';

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
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('embeds Related Work for the full diary instead of a date-windowed Apex call', async () => {
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        const relatedWork = element.shadowRoot.querySelector('c-work-order-ledger-related-work');
        expect(relatedWork).not.toBeNull();
        expect(relatedWork.recordId).toBe(LEDGER_ID);
    });

    it('keeps Open Full Ledger available when not embedded', async () => {
        const element = createModal();
        element.ledgerId = LEDGER_ID;
        document.body.appendChild(element);
        await flush();

        const buttons = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map(
            node => node.label
        );
        expect(buttons).toContain('Open Full Ledger');
        expect(buttons).toContain('Close');
    });
});
