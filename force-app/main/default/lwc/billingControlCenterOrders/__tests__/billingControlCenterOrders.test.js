import { createElement } from 'lwc';
import BillingControlCenterOrders from 'c/billingControlCenterOrders';
import { resolveDateRange } from 'c/billingControlCenterDateFilter';
import getOrdersRuntimeData from '@salesforce/apex/BillingControl_WorkOrderLedger.getOrdersRuntimeData';
import getTabConfig from '@salesforce/apex/BillingControl_ConfigService.getTabConfig';

jest.mock(
    '@salesforce/apex/BillingControl_WorkOrderLedger.getOrdersRuntimeData',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingControl_ConfigService.getTabConfig',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const BUCKETS = ['READY_TO_SCHEDULE', 'SCHEDULED_APPOINTMENTS', 'IN_PROGRESS'];

/** Builds a runtime payload whose Ready bucket holds one row per supplied work order number. */
function runtimePayload(readyWorkOrderNumbers) {
    return {
        warnings: [],
        kpis: {
            unscheduledCount: readyWorkOrderNumbers.length,
            scheduledCount: 0,
            inProgressCount: 0
        },
        bucketSections: BUCKETS.map(bucketKey => ({
            bucketKey,
            sectionLabel: bucketKey,
            serviceAppointmentCount: bucketKey === 'READY_TO_SCHEDULE' ? readyWorkOrderNumbers.length : 0,
            rows:
                bucketKey === 'READY_TO_SCHEDULE'
                    ? readyWorkOrderNumbers.map(number => ({
                          rowKey: `row-${number}`,
                          workOrderId: `wo-${number}`,
                          workOrderNumber: number,
                          accountName: `Account ${number}`,
                          serviceAppointmentCount: 1,
                          relatedServiceAppointments: []
                      }))
                    : []
        }))
    };
}

function deferred() {
    let resolve;
    const promise = new Promise(inner => {
        resolve = inner;
    });
    return { promise, resolve };
}

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        await Promise.resolve();
    }
}

function build() {
    const element = createElement('c-billing-control-center-orders', {
        is: BillingControlCenterOrders
    });
    document.body.appendChild(element);
    return element;
}

/**
 * Every date-filter change forces a refresh, so a unique custom range guarantees a fresh Apex
 * call. The runtime cache lives at module scope and outlives individual tests.
 */
function customRange(startDate, endDate) {
    return { filterKey: 'Custom', startDate, endDate };
}

function emitDateFilter(element, detail) {
    element.shadowRoot
        .querySelector('c-billing-control-center-date-filter')
        .dispatchEvent(new CustomEvent('datefilterchange', { detail }));
}

function apexCallArgs() {
    return getOrdersRuntimeData.mock.calls.map(call => call[0]);
}

function readyCountLabel(element) {
    const section = Array.from(element.shadowRoot.querySelectorAll('lightning-accordion-section')).find(
        node => node.name === 'READY_TO_SCHEDULE'
    );
    return section ? section.label : null;
}

describe('c-billing-control-center-orders date filtering', () => {
    beforeEach(() => {
        // A null config keeps the component on its default presentation instead of the
        // config-driven empty state, so the bucket accordion actually renders.
        getTabConfig.mockResolvedValue(null);
        getOrdersRuntimeData.mockReset();
        getOrdersRuntimeData.mockResolvedValue(runtimePayload([]));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the buckets returned by Apex', async () => {
        getOrdersRuntimeData.mockResolvedValue(runtimePayload(['WO-1', 'WO-2', 'WO-3']));
        const element = build();
        await flush();

        const names = Array.from(element.shadowRoot.querySelectorAll('lightning-accordion-section')).map(
            node => node.name
        );
        expect(names).toEqual(BUCKETS);
        expect(readyCountLabel(element)).toContain('(3)');
    });

    it('sends the selected preset to Apex', async () => {
        const element = build();
        await flush();

        emitDateFilter(element, { filterKey: 'Last Year', startDate: null, endDate: null });
        await flush();

        const lastCall = apexCallArgs().pop();
        expect(lastCall.filterKey).toBe('Last Year');
        expect(lastCall.startDate).toBe(resolveDateRange('Last Year').startDate);
        expect(lastCall.endDate).toBe(resolveDateRange('Last Year').endDate);
        expect(lastCall.dateFilter).toBeUndefined();
    });

    it('sends This Month start and end dates so Apex cannot fall back to Current Year', async () => {
        const element = build();
        await flush();

        emitDateFilter(element, { filterKey: 'This Month', startDate: null, endDate: null });
        await flush();

        const lastCall = apexCallArgs().pop();
        const thisMonth = resolveDateRange('This Month');
        expect(lastCall.filterKey).toBe('This Month');
        expect(lastCall.startDate).toBe(thisMonth.startDate);
        expect(lastCall.endDate).toBe(thisMonth.endDate);
        expect(lastCall.startDate.endsWith('-01')).toBe(true);
        expect(lastCall.endDate).not.toBeNull();
    });

    it('replaces the rendered dataset when the window changes', async () => {
        const element = build();
        await flush();

        getOrdersRuntimeData.mockResolvedValueOnce(runtimePayload(['WO-1', 'WO-2', 'WO-3']));
        emitDateFilter(element, customRange('2026-08-01', '2026-08-31'));
        await flush();
        expect(readyCountLabel(element)).toContain('(3)');

        getOrdersRuntimeData.mockResolvedValueOnce(runtimePayload(['WO-9']));
        emitDateFilter(element, customRange('2025-01-01', '2025-12-31'));
        await flush();

        expect(readyCountLabel(element)).toContain('(1)');
    });

    it('keys its cache on the custom start and end dates independently', async () => {
        const element = build();
        await flush();

        emitDateFilter(element, customRange('2026-06-01', '2026-06-30'));
        await flush();
        emitDateFilter(element, customRange('2026-06-01', '2026-07-31'));
        await flush();
        emitDateFilter(element, customRange('2026-05-01', '2026-07-31'));
        await flush();

        const ranges = apexCallArgs()
            .filter(args => args.filterKey === 'Custom')
            .map(args => `${args.startDate}..${args.endDate}`);
        expect(ranges).toEqual([
            '2026-06-01..2026-06-30',
            '2026-06-01..2026-07-31',
            '2026-05-01..2026-07-31'
        ]);
    });

    it('sends opportunityOwnerId alongside the window so the cache cannot merge owners', async () => {
        const element = build();
        await flush();

        element.shadowRoot
            .querySelector('lightning-record-picker')
            .dispatchEvent(new CustomEvent('change', { detail: { recordId: '005000000000001' } }));
        await flush();

        const lastCall = apexCallArgs().pop();
        expect(lastCall.opportunityOwnerId).toBe('005000000000001');
        expect(lastCall.filterKey).toBe('This Month');
    });

    it('defaults the date window to This Month', async () => {
        const element = build();
        await flush();

        expect(element.dateFilter).toEqual(resolveDateRange('This Month'));
    });

    it('opens the matching accordion section when a KPI tile is clicked', async () => {
        const element = build();
        await flush();

        getOrdersRuntimeData.mockResolvedValueOnce(runtimePayload(['WO-1']));
        emitDateFilter(element, customRange('2026-09-01', '2026-09-30'));
        await flush();

        element.shadowRoot
            .querySelector('c-billing-control-center-kpi-grid')
            .dispatchEvent(
                new CustomEvent('tileclick', {
                    detail: { key: 'readyToSchedule', developerKey: 'READY_TO_SCHEDULE' }
                })
            );
        await flush();

        const accordion = element.shadowRoot.querySelector('lightning-accordion');
        expect(accordion.activeSectionName).toEqual(['READY_TO_SCHEDULE']);
    });

    it('keeps rendered rows while a refresh is in flight', async () => {
        const element = build();
        await flush();

        getOrdersRuntimeData.mockResolvedValueOnce(runtimePayload(['WO-1', 'WO-2']));
        emitDateFilter(element, customRange('2026-10-01', '2026-10-31'));
        await flush();
        expect(readyCountLabel(element)).toContain('(2)');

        const pending = deferred();
        getOrdersRuntimeData.mockReturnValueOnce(pending.promise);
        const refreshPromise = element.refreshData();
        await flush(2);

        expect(readyCountLabel(element)).toContain('(2)');
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();

        pending.resolve(runtimePayload(['WO-9']));
        await refreshPromise;
        await flush();
        expect(readyCountLabel(element)).toContain('(1)');
    });

    it('starts with work-type groups expanded', async () => {
        const element = build();
        await flush();

        getOrdersRuntimeData.mockResolvedValueOnce(runtimePayload(['WO-1']));
        emitDateFilter(element, customRange('2026-11-01', '2026-11-30'));
        await flush();

        const expandIcons = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button-icon')
        ).filter(node => (node.iconName || '').includes('chevron'));
        expect(expandIcons.some(node => node.iconName === 'utility:chevrondown')).toBe(true);
    });

    it('does not let a slow earlier response overwrite a newer date filter', async () => {
        const element = build();
        await flush();

        const slowWideWindow = deferred();
        getOrdersRuntimeData.mockReturnValueOnce(slowWideWindow.promise);
        emitDateFilter(element, customRange('2020-01-01', '2026-12-31'));
        await flush(2);

        getOrdersRuntimeData.mockReturnValueOnce(Promise.resolve(runtimePayload(['WO-NEW'])));
        emitDateFilter(element, customRange('2026-08-01', '2026-08-31'));
        await flush();
        expect(readyCountLabel(element)).toContain('(1)');

        // The abandoned wide-window request lands late with a much larger population.
        slowWideWindow.resolve(runtimePayload(['A', 'B', 'C', 'D', 'E']));
        await flush();

        expect(readyCountLabel(element)).toContain('(1)');
    });

    it('clears the spinner once the newest request settles', async () => {
        const element = build();
        await flush();

        emitDateFilter(element, customRange('2026-02-01', '2026-02-28'));
        await flush();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('opens the ledger modal without passing a date window (full Related Work diary)', async () => {
        const element = build();
        await flush();

        const payload = runtimePayload(['WO-LEDGER']);
        payload.bucketSections[0].rows[0].ledgerId = 'a1T000000000001';
        getOrdersRuntimeData.mockResolvedValueOnce(payload);
        emitDateFilter(element, customRange('2026-03-01', '2026-03-31'));
        await flush();

        const viewLedger = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find(node => node.label === 'View Ledger');
        expect(viewLedger).toBeTruthy();
        viewLedger.click();
        await flush();

        const modal = element.shadowRoot.querySelector('c-billing-control-center-ledger-modal');
        expect(modal).not.toBeNull();
        expect(modal.ledgerId).toBe('a1T000000000001');
    });

    it('keeps billed-excluded Apex totals on the tile and omits billed rows from pit/other splits', async () => {
        getOrdersRuntimeData.mockResolvedValue({
            warnings: [],
            kpis: {
                unscheduledCount: 0,
                unscheduledRevenue: 0,
                scheduledCount: 1,
                scheduledRevenue: 300,
                inProgressCount: 0,
                inProgressRevenue: 0
            },
            bucketSections: [
                { bucketKey: 'READY_TO_SCHEDULE', sectionLabel: 'Ready', rows: [] },
                {
                    bucketKey: 'SCHEDULED_APPOINTMENTS',
                    sectionLabel: 'Scheduled',
                    rows: [
                        {
                            rowKey: 'open',
                            workOrderId: 'wo-open',
                            workOrderNumber: 'WO-OPEN',
                            billedBadge: false,
                            operationalAmount: 300,
                            visitAmount: 900,
                            opportunityAmount: 900,
                            relatedServiceAppointments: []
                        },
                        {
                            rowKey: 'billed',
                            workOrderId: 'wo-billed',
                            workOrderNumber: 'WO-BILLED',
                            billedBadge: true,
                            operationalAmount: 600,
                            visitAmount: 900,
                            opportunityAmount: 900,
                            relatedServiceAppointments: []
                        }
                    ]
                },
                { bucketKey: 'IN_PROGRESS', sectionLabel: 'In Progress', rows: [] }
            ]
        });
        const element = build();
        await flush();

        emitDateFilter(element, customRange('2026-04-01', '2026-04-30'));
        await flush();

        const grid = element.shadowRoot.querySelector('c-billing-control-center-kpi-grid');
        const scheduledTile = (grid.tiles || []).find(tile => tile.developerKey === 'SCHEDULED_APPOINTMENTS');
        expect(scheduledTile.countText).toContain('1');
        expect(scheduledTile.metricText).toContain('300');
        expect(scheduledTile.splitColumns.map(column => column.countText).join(' ')).toContain('1 records');
        expect(scheduledTile.splitColumns.map(column => column.metricText).join(' ')).toContain('300');
        expect(scheduledTile.splitColumns.map(column => column.metricText).join(' ')).not.toContain('1,800');
        expect(scheduledTile.splitColumns.map(column => column.metricText).join(' ')).not.toContain('900');

        const tileText = grid.shadowRoot.textContent;
        expect(tileText).toContain('1 records');
        expect(tileText).not.toContain('2 records');
    });
});
