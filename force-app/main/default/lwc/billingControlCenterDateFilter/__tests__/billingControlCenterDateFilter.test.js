import { createElement } from 'lwc';
import BillingControlCenterDateFilter from 'c/billingControlCenterDateFilter';

function build(props = {}) {
    const element = createElement('c-billing-control-center-date-filter', {
        is: BillingControlCenterDateFilter
    });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

function selectPreset(element, value) {
    element.shadowRoot
        .querySelector('lightning-button-menu')
        .dispatchEvent(new CustomEvent('select', { detail: { value } }));
}

function changeDate(element, index, value) {
    element.shadowRoot.querySelectorAll('lightning-input')[index].dispatchEvent(
        new CustomEvent('change', { detail: { value } })
    );
}

describe('c-billing-control-center-date-filter', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('defaults to This Year', () => {
        expect(build().selectedFilterKey).toBe('This Year');
    });

    it('emits a preset without custom dates', async () => {
        const element = build();
        const handler = jest.fn();
        element.addEventListener('datefilterchange', handler);

        selectPreset(element, 'Last Year');
        await Promise.resolve();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            filterKey: 'Last Year',
            startDate: null,
            endDate: null
        });
    });

    it('emits every preset key the server can resolve', async () => {
        const element = build();
        const emitted = [];
        element.addEventListener('datefilterchange', event => emitted.push(event.detail.filterKey));

        ['This Month', 'This Quarter', 'This Year', 'Last Year'].forEach(key => selectPreset(element, key));
        await Promise.resolve();

        expect(emitted).toEqual(['This Month', 'This Quarter', 'This Year', 'Last Year']);
    });

    it('carries both boundaries when a custom range is chosen', async () => {
        const element = build();
        selectPreset(element, 'Custom');
        await Promise.resolve();

        const handler = jest.fn();
        element.addEventListener('datefilterchange', handler);
        changeDate(element, 0, '2026-06-01');
        changeDate(element, 1, '2026-06-30');
        await Promise.resolve();

        const lastCall = handler.mock.calls[handler.mock.calls.length - 1][0];
        expect(lastCall.detail).toEqual({
            filterKey: 'Custom',
            startDate: '2026-06-01',
            endDate: '2026-06-30'
        });
    });

    it('does not emit a half-filled custom range', async () => {
        const element = build();
        selectPreset(element, 'Custom');
        await Promise.resolve();

        const handler = jest.fn();
        element.addEventListener('datefilterchange', handler);
        changeDate(element, 1, '');
        await Promise.resolve();

        expect(handler).not.toHaveBeenCalled();
    });
});
